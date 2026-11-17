import Foundation
import CryptoKit

/// 本地状态中心：授权、规则、隧道参数
///
/// 线程约定：
///   - 写入（save/applySession/clearLicense）只在 WorkQueue 上做
///   - 读取可以在任意线程，内部有锁，拿到的永远是完整的一份
///
/// 规则不再写本地。`RuleService` 只把明文和解析结果放在内存里，
/// 这里只负责把它交给界面和隧道配置，不再每次重新解析一遍。
final class ConfigStore {

    static let shared = ConfigStore()

    private let defaults = UserDefaults.standard
    private let licenseKey = "hm.license.v1"
    private let statsKey   = "hm.stats.v1"

    private let lock = NSRecursiveLock()
    private var _license: LicenseState

    var license: LicenseState {
        lock.lock(); defer { lock.unlock() }
        return _license
    }

    private init() {
        /* 本地这份授权带签名校验：直接改 UserDefaults 里那串数据伪造
           authorized=true 是无效的，验不过就当作没有授权，重新走服务端。 */
        var loaded: LicenseState?
        if let blob = defaults.data(forKey: licenseKey) {
            if LicenseSeal.isSealed(blob) {
                if let body = LicenseSeal.open(blob),
                   let st = try? JSONDecoder().decode(LicenseState.self, from: body) {
                    loaded = st
                } else {
                    loaded = nil          // 签名不对：这份状态不认
                }
            } else if let st = try? JSONDecoder().decode(LicenseState.self, from: blob) {
                loaded = st               // 老版本明文格式：先认下来，下面立即重写
            }
        }
        let st = loaded ?? .empty(pin: ConfigStore.makePin())
        _license = st
        if loaded != nil, let body = try? JSONEncoder().encode(st) {
            defaults.set(LicenseSeal.seal(body), forKey: licenseKey)
        }
        /* 旧版本可能把规则明文存在这里，升级后清掉 */
        defaults.removeObject(forKey: "hm.remotePayload.v1")
    }

    // MARK: - 设备码

    /// 设备码：服务端要求 8 位纯数字
    ///
    /// 由 `DeviceIdentity` 统一给出：同一台设备无论升级、覆盖安装还是卸载重装，
    /// 算出来的都是同一个码（旧版本的随机码会被原样沿用，不会让老用户掉授权）。
    static func makePin() -> String {
        DeviceIdentity.shared.pin
    }

    var pin: String {
        let p = license.pin
        return p.isEmpty ? ConfigStore.makePin() : p
    }

    // MARK: - 授权

    func save(license st: LicenseState) {
        lock.lock()
        _license = st
        lock.unlock()
        /* 被调试 / 被注入时只在内存里生效，不写盘：
           这种环境下读不到能直接复制走的授权数据 */
        guard Integrity.shared.trustedLocally else { return }
        if let body = try? JSONEncoder().encode(st) {
            defaults.set(LicenseSeal.seal(body), forKey: licenseKey)
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
        let old = license
        merged.pin = pin
        merged.code = code.isEmpty ? old.code : code
        if merged.expireAt == nil && merged.code == old.code {
            merged.expireAt = old.expireAt
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

    /// 直接用 `RuleService` 里已经解析好的那份，不再每次重新 parse
    func currentRuleSet() -> RuleSet {
        RuleService.shared.currentSet
    }

    var rulesSourceLabel: String {
        let rs = RuleService.shared
        if !rs.isLoaded { return "未加载" }
        let n = rs.setCount > 0 ? rs.setCount : rs.setNames.count
        if n >= 2 { return "云端下发 · \(n) 套规则" }
        return rs.setNames.first.map { "云端下发 · \($0)" } ?? "云端下发"
    }

    var rulesSetsLabel: String { RuleService.shared.setsText }

    var rulesVersion: String { RuleService.shared.version }

    var cloudNotice: String? { nil }

    // MARK: - 隧道参数

    /// 通过 providerConfiguration 传给扩展（不依赖 App Group，签名更省事）
    ///
    /// 这个方法会被 `start()` 在后台线程调用，内部只读内存，不做解密/解析。
    func tunnelConfiguration() -> [String: Any] {
        let rules = currentRuleSet()
        let routes: [[String: Any]] = rules.includedRoutes().map {
            ["ip": $0.0 as Any, "prefix": $0.1 as Any]
        }
        let st = license
        return [
            "pin": pin,
            "code": st.code,
            "expireAt": st.expireAt?.timeIntervalSince1970 ?? 0,
            "rulesVersion": RuleService.shared.version,
            "rulesText": currentRulesText(),
            "routes": routes,
            "dnsIP": AppConfig.dnsProxyIP,
            "clientIP": AppConfig.clientIP,
            "sinkholeIP": AppConfig.sinkholeIP,
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

/// 本地授权数据的封条
///
/// 用主密钥 + 设备码派生 HMAC，覆盖整段 JSON；改一个字节就验不过。
/// 目的不是加密（内容本来也不敏感），是让「手改 UserDefaults 变成已授权」这条路走不通。
private enum LicenseSeal {

    private static let magic = Data([0x48, 0x4D, 0x4C, 0x31])   // HML1
    private static let tagLength = 32

    private static var key: SymmetricKey {
        let material = AppConfig.secureMasterKey + "|" + ConfigStore.makePin() + "|hm-seal-v1"
        return SymmetricKey(data: Data(SHA256.hash(data: Data(material.utf8))))
    }

    static func isSealed(_ blob: Data) -> Bool {
        blob.count > magic.count + tagLength && blob.prefix(magic.count) == magic
    }

    static func seal(_ body: Data) -> Data {
        let tag = Data(HMAC<SHA256>.authenticationCode(for: body, using: key))
        return magic + body + tag
    }

    static func open(_ blob: Data) -> Data? {
        guard isSealed(blob) else { return nil }
        let body = blob.subdata(in: magic.count..<(blob.count - tagLength))
        let tag = blob.suffix(tagLength)
        let expect = Data(HMAC<SHA256>.authenticationCode(for: body, using: key))
        guard expect == Data(tag) else { return nil }
        return body
    }
}
