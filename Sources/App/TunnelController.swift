import Foundation
import NetworkExtension
import Combine

/// 隧道生命周期管理
final class TunnelController: ObservableObject {

    static let shared = TunnelController()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let conn = note.object as? NEVPNConnection else { return }
            self?.status = conn.status
        }
        reload()
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    var isConnected: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    var statusText: String {
        switch status {
        case .connected:    return "防护运行中"
        case .connecting:   return "正在连接"
        case .disconnecting:return "正在断开"
        case .reasserting:  return "正在恢复"
        case .disconnected: return "未开启"
        case .invalid:      return "待授权"
        default:            return "未开启"
        }
    }

    // MARK: - 读取现有配置

    func reload() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.manager = managers?.first
                self.status = self.manager?.connection.status ?? .invalid
            }
        }
    }

    // MARK: - 启动

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        guard RuleService.shared.isLoaded else {
            completion(.failure(LicenseError.badResponse("云端规则还没加载好，稍后再试")))
            return
        }
        let conf = ConfigStore.shared.tunnelConfiguration()

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let manager = managers?.first ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = AppConfig.tunnelBundleID
            proto.serverAddress = AppConfig.dnsProxyIP
            proto.providerConfiguration = conf
            proto.disconnectOnSleep = false

            manager.protocolConfiguration = proto
            manager.localizedDescription = AppConfig.appName
            manager.isEnabled = true

            manager.saveToPreferences { error in
                if let error = error {
                    let friendly = TunnelController.explain(error)
                    DispatchQueue.main.async {
                        self.lastError = friendly.localizedDescription
                        completion(.failure(friendly))
                    }
                    return
                }
                manager.loadFromPreferences { _ in
                    do {
                        try manager.connection.startVPNTunnel()
                        DispatchQueue.main.async {
                            self.manager = manager
                            self.status = manager.connection.status
                            completion(.success(()))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.lastError = error.localizedDescription
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
        DispatchQueue.main.async { self.status = .disconnected }
    }

    /// 把系统给的干巴巴错误码翻成用户能照着做的提示
    ///
    /// 签名不完整（尤其是扩展没签上）时，系统只会甩一句 permission denied，
    /// 用户完全不知道该干嘛。这里按错误内容给出具体动作。
    static func explain(_ error: Error) -> Error {
        let ns = error as NSError
        let raw = ns.localizedDescription.lowercased()

        if raw.contains("permission") || raw.contains("entitled")
            || raw.contains("entitlement") || raw.contains("code sign")
            || raw.contains("codesign") || raw.contains("not valid") {
            return LicenseError.badResponse(
                "系统拒绝了隧道权限：安装包签名不完整。用巨魔的请装 TrollStore 专用包，用 ESign / 爱思的请把主程序和扩展一起签。")
        }

        if ns.domain == NEVPNErrorDomain {
            switch ns.code {
            case NEVPNError.configurationInvalid.rawValue,
                 NEVPNError.configurationReadWriteFailed.rawValue:
                return LicenseError.badResponse("VPN 配置写入失败，通常是签名或权限问题，重装一次安装包再试。")
            case NEVPNError.configurationDisabled.rawValue:
                return LicenseError.badResponse("VPN 配置被系统停用，去「设置 - 通用 - VPN 与设备管理」里删掉旧配置再开。")
            case NEVPNError.connectionFailed.rawValue:
                return LicenseError.badResponse("隧道启动失败，检查卡密状态后重试。")
            default:
                break
            }
        }
        return error
    }

    /// 规则热更新：把新规则推给扩展
    func pushRules(_ text: String) {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        guard let data = "rules:\(text)".data(using: .utf8) else { return }
        try? session.sendProviderMessage(data) { _ in }
    }

    /// 拉统计
    ///
    /// `sendProviderMessage` 没有重传，扩展忙或系统切换网络时会一直不回调。
    /// 这里加 1 秒硬超时，保证每次轮询一定有结果（拿不到就回空，上层读扩展落盘的快照）。
    func fetchStats(completion: @escaping ([String: Any]) -> Void) {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else {
            completion([:]); return
        }

        let lock = NSLock()
        var done = false
        let finish: ([String: Any]) -> Void = { obj in
            lock.lock()
            if done { lock.unlock(); return }
            done = true
            lock.unlock()
            completion(obj)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            finish([:])
        }

        try? session.sendProviderMessage(Data("stats".utf8)) { data in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                finish([:]); return
            }
            finish(obj)
        }
    }
}
