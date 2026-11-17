import Foundation
import NetworkExtension
import Combine

/// 隧道生命周期管理
final class TunnelController: ObservableObject {

    static let shared = TunnelController()

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var lastError: String?
    /// 最近一次统计拉取的失败原因（只用于排查，不弹给用户）
    private(set) var lastStatsError: String?

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
                self.manager = TunnelController.pick(managers)
                self.status = self.manager?.connection.status ?? .invalid
            }
        }
    }

    /// 从系统里的 VPN 配置里挑出「正在用的那一条」
    ///
    /// 以前一律取 `managers.first`。设备上只要残留过一条旧配置（重装、改过
    /// bundle id、手动新建过都会留下），拿到的就可能是那条早就断开的配置：
    /// 拦截照旧在另一条上跑，而统计永远问一条不存在的隧道 —— 表现就是
    /// 「拦得住、数字全 0」。现在优先取在连接/恢复中的，其次取 bundle id 对得上的。
    static func pick(_ managers: [NETunnelProviderManager]?) -> NETunnelProviderManager? {
        guard let list = managers, !list.isEmpty else { return nil }
        let live: [NEVPNStatus] = [.connected, .connecting, .reasserting, .disconnecting]
        if let active = list.first(where: { live.contains($0.connection.status) }) {
            return active
        }
        if let ours = list.first(where: {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                == AppConfig.tunnelBundleID
        }) {
            return ours
        }
        return list.first
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

            let manager = TunnelController.pick(managers) ?? NETunnelProviderManager()
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
    /// 三条通道按顺序试，谁先给出数字用谁：
    ///   1. 本机直连（扩展里的统计服务，回环 TCP）—— 不依赖沙箱共享目录和消息回调，
    ///      伪签名环境、隧道刚重连都不影响，是现在的主通道
    ///   2. sendProviderMessage（官方通道）—— 环境正常时的备选
    ///   3. 扩展落盘的快照 —— 前两条都断了才用（由调用方读 StatsBridge）
    func fetchStats(completion: @escaping ([String: Any], String) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let direct = StatsLink.fetch()
            if !direct.isEmpty {
                DispatchQueue.main.async { completion(direct, "本机直连") }
                return
            }
            DispatchQueue.main.async { self?.fetchStatsViaMessage(completion: completion) }
        }
    }

    /// 官方通道：问扩展要一份统计
    ///
    /// `sendProviderMessage` 没有重传，扩展忙或系统切换网络时会一直不回调。
    /// 这里加 2 秒硬超时，保证每次轮询一定有结果（拿不到就回空，上层读落盘快照）。
    ///
    /// 顺带修一处：以前 `session.status != .connected` 就直接返回空。
    /// 隧道正在 reassert（切网）或者 manager 拿到的是另一条旧配置时，
    /// 这一条 guard 会把统计通道整条掐死，面板永远 0。
    /// 现在只要 manager 在就发一次，发不出去由 try? 吞掉，上层照样读落盘快照。
    private func fetchStatsViaMessage(completion: @escaping ([String: Any], String) -> Void) {
        guard let session = manager?.connection as? NETunnelProviderSession else {
            completion([:], ""); return
        }

        let lock = NSLock()
        var done = false
        let finish: ([String: Any], String) -> Void = { obj, channel in
            lock.lock()
            if done { lock.unlock(); return }
            done = true
            lock.unlock()
            completion(obj, channel)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
            finish([:], "")
        }

        do {
            try session.sendProviderMessage(Data("stats".utf8)) { data in
                guard let data = data,
                      let any = try? JSONSerialization.jsonObject(with: data),
                      let obj = any as? [String: Any] else {
                    finish([:], ""); return
                }
                finish(obj, "隧道回包")
            }
        } catch {
            lastStatsError = error.localizedDescription
            finish([:], "")
        }
    }
}
