import Foundation

/// 本地状态中心：授权、规则、隧道参数
///
/// 注意：规则不再写本地。`RuleService` 只把明文放在内存里，
/// 这里只负责把它交给界面和隧道配置。
final class ConfigStore {

    static let shared = ConfigStore()

    private let defaults = UserDefaults.standard
    private let licenseKey = "hm.license.v1"
    private let statsKey   = "hm.stats.v1"

    private(set) var license: LicenseState

    private init() {
        if let data = defaults.data(forKey: licenseKey),
           let st = try? JSONDecoder().decode(LicenseState.self, from: data) {
            license = st
        } else {
            license = .empty(pin: ConfigStore.makePin())
        }
        /* 旧版本可能把规则明文存在这里，升级后清掉 */
        defaults.removeObject(forKey: "hm.remotePayload.v1")
    }

    // MARK: - 设备码

    /// 设备码：服务端要求 8 位纯数字（非数字会被服务端过滤掉导致校验失败）
    /// 首次启动生成后固定保存在本地
    static func makePin() -> String {
        let key = "hm.pin.v1"
        if let saved = UserDefaults.standard.string(forKey: key),
           saved.count == AppConfig.pinLength,
           saved.allSatisfy({ $0.isNumber }) {
            return saved
        }
        var digits = ""
        for _ in 0..<AppConfig.pinLength {
            digits.append(Character(String(Int.random(in: 0...9))))
        }
        UserDefaults.standard.set(digits, forKey: key)
        return digits
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
        st.verdict = .noCard
        st.verifiedAt = nil
        save(license: st)
        RuleService.shared.clear()
    }

    var isAuthorized: Bool { license.isUsable() }

    /// 卡密与在线窗口的一次刷新（兑换 / 续期 / 校验 / 查询共用）
    ///
    /// 判定结果（verdict）永远用服务端最新给的那份；
    /// 只有卡密到期时间在服务端没带回来时才沿用本地的，避免显示成「—」。
    func applySession(_ st: LicenseState, pin: String, code: String) {
        var merged = st
        merged.pin = pin
        merged.code = code.isEmpty ? license.code : code
        if merged.expireAt == nil && merged.code == license.code {
            merged.expireAt = license.expireAt
        }
        /* 服务端明确判死时，本地校验窗口一并作废，防止界面残留旧窗口误导 */
        if merged.verdict.isHardFailure {
            merged.sessionUntil = Date(timeIntervalSince1970: 0)
            merged.authorized = false
        }
        save(license: merged)
    }

    // MARK: - 规则装配（仅内存）

    func currentRulesText() -> String {
        RuleService.shared.text ?? ""
    }

    func currentRuleSet() -> RuleSet {
        RuleSet.parse(text: currentRulesText())
    }

    var rulesSourceLabel: String {
        let v = RuleService.shared.version
        return v.isEmpty ? "未加载" : "云端下发 · v\(v)"
    }

    var rulesVersion: String { RuleService.shared.version }

    var cloudNotice: String? { nil }

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
            "rulesVersion": RuleService.shared.version,
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
