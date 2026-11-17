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
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        completion(.failure(error))
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

    /// 规则热更新：把新规则推给扩展
    func pushRules(_ text: String) {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        guard let data = "rules:\(text)".data(using: .utf8) else { return }
        try? session.sendProviderMessage(data) { _ in }
    }

    /// 拉统计
    func fetchStats(completion: @escaping ([String: Any]) -> Void) {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected else {
            completion([:]); return
        }
        try? session.sendProviderMessage(Data("stats".utf8)) { data in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion([:]); return
            }
            completion(obj)
        }
    }
}
