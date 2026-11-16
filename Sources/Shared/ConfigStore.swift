import Foundation

/// 本地状态中心：授权、规则、隧道参数
final class ConfigStore {

    static let shared = ConfigStore()

    private let defaults = UserDefaults.standard
    private let licenseKey = "hm.license.v1"
    private let payloadKey = "hm.remotePayload.v1"
    private let statsKey   = "hm.stats.v1"

    private(set) var license: LicenseState
    private var remotePayload: RemoteConfigPayload?

    private init() {
        if let data = defaults.data(forKey: licenseKey),
           let st = try? JSONDecoder().decode(LicenseState.self, from: data) {
            license = st
        } else {
            license = .empty(pin: ConfigStore.makePin())
        }
        if let data = defaults.data(forKey: payloadKey) {
            remotePayload = try? JSONDecoder().decode(RemoteConfigPayload.self, from: data)
        }
    }

    // MARK: - 设备码

    /// 设备码：首次启动生成后固定保存在本地
    static func makePin() -> String {
        let key = "hm.pin.v1"
        if let saved = UserDefaults.standard.string(forKey: key), saved.count >= 10 {
            return saved
        }
        let seed = UUID().uuidString + "|" + String(Date().timeIntervalSince1970)
        let pin = "HM" + CryptoBox.fingerprint(seed)
        UserDefaults.standard.set(pin, forKey: key)
        return pin
    }

    var pin: String { license.pin.isEmpty ? ConfigStore.makePin() : license.pin }

    // MARK: - 授权

    func save(license st: LicenseState) {
        license = st
        if let data = try? JSONEncoder().encode(st) {
            defaults.set(data, forKey: licenseKey)
        }
    }

    func clearLicense() {
        var st = LicenseState.empty(pin: ConfigStore.makePin())
        st.lastCheck = .distantPast
        save(license: st)
    }

    var isAuthorized: Bool { license.isUsable() }

    // MARK: - 云端配置包

    func saveRemotePayload(_ p: RemoteConfigPayload) {
        remotePayload = p
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: payloadKey)
        }
    }

    func invalidateRemotePayload() {
        remotePayload = nil
        defaults.removeObject(forKey: payloadKey)
    }

    // MARK: - 规则装配

    /// 优先级：云端下发的加密包 > 安装包内置规则
    func currentRulesText() -> String {
        if let p = remotePayload, p.version >= 1, !p.rules.isEmpty {
            return p.rules
        }
        if let url = Bundle.main.url(forResource: "rules", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return ""
    }

    func currentRuleSet() -> RuleSet {
        RuleSet.parse(text: currentRulesText())
    }

    var rulesSourceLabel: String {
        if let p = remotePayload, !p.rules.isEmpty {
            return "云端下发 · \(p.version)"
        }
        return "内置规则库"
    }

    /// 云端公告优先，其次服务端 announcement
    var cloudNotice: String? {
        guard let n = remotePayload?.notice, !n.isEmpty else { return nil }
        return n
    }

    // MARK: - 隧道参数

    /// 通过 providerConfiguration 传给扩展（不依赖 App Group，签名更省事）
    func tunnelConfiguration() -> [String: Any] {
        let rules = currentRuleSet()
        let routes: [[String: Any]] = rules.includedRoutes().map {
            ["ip": $0.0 as Any, "prefix": $0.1 as Any]
        }
        return [
            "pin": pin,
            "code": license.code,
            "expireAt": license.expireAt?.timeIntervalSince1970 ?? 0,
            "configExpire": license.configExpire?.timeIntervalSince1970 ?? 0,
            "rulesText": currentRulesText(),
            "routes": routes,
            "dnsIP": AppConfig.dnsProxyIP,
            "clientIP": AppConfig.clientIP,
            "mtu": AppConfig.mtu
        ]
    }

    // MARK: - 统计

    struct Stats: Codable {
        var blockedPackets: Int = 0
        var blockedDomains: Int = 0
        var blockedTCP: Int = 0
        var blockedUDP: Int = 0
        var passedDNS: Int = 0
        var startedAt: Date?
    }

    func saveStats(_ s: Stats) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: statsKey)
        }
    }

    func loadStats() -> Stats {
        if let data = defaults.data(forKey: statsKey),
           let s = try? JSONDecoder().decode(Stats.self, from: data) {
            return s
        }
        return Stats()
    }
}
