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
    private let modeKey    = "hm.mode.v1"
    private let portBlockKey = "hm.portblock.v1"

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

    /// 被调试 / 被注入时用：不经过 save() 的「本地可信」判断，直接把落盘授权抹掉。
    /// 目的只有一个 —— 让别人从内存或磁盘上都拿不到能直接复用的授权数据。
    func purgeLocalLicense() {
        lock.lock()
        _license = LicenseState.empty(pin: ConfigStore.makePin())
        lock.unlock()
        defaults.removeObject(forKey: licenseKey)
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

    // MARK: - 拦截模式（1.2.3）

    /// 规则模式 / 全局模式。默认规则模式 —— 用户反馈的「开了就断网」
    /// 就是默认全接管造成的，新装用户从规则模式起步不会一上来就上不了网。
    var mode: InterceptMode {
        get { InterceptMode.from(defaults.string(forKey: modeKey)) }
        set { defaults.set(newValue.rawValue, forKey: modeKey) }
    }

    /// 规则包 #PORT 段是否参与拦截（1.2.7：恢复成独立用户开关，默认关闭）
    ///
    /// 1.2.4 曾把它跟模式绑死（全局开、规则关），实际用下来大家要的是自己决定。
    /// 现在恢复成独立开关：默认关，用户自己打开才按 #PORT 段拦；
    /// 打开后 [AppConfig.corePorts]（22/53/80/123/443/853/8080/8443）永远放行，
    /// 不会把授权通道一起封掉。改动要重连隧道才生效。
    var portBlocking: Bool {
        get { defaults.bool(forKey: portBlockKey) }
        set { defaults.set(newValue, forKey: portBlockKey) }
    }

    // MARK: - 隧道参数

    /// 通过 providerConfiguration 传给扩展（不依赖 App Group，签名更省事）
    ///
    /// 这个方法会被 `start()` 在后台线程调用，内部只读内存，不做解密/解析。
    func tunnelConfiguration() -> [String: Any] {
        /* 路由交给隧道自己算（默认路由 + 规则补集），这里只带规则文本。
           保留 routes 字段是为了老版本隧道路径兼容，新隧道会忽略它。 */
        let routes: [[String: Any]] = []
        let st = license
        /* 统计落盘目录：扩展按这个路径写，主程序读自己的 Documents。
           比 App Group 稳 —— 那是本 App 自己的容器，权限一定是通的。 */
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        return [
            "pin": pin,
            "code": st.code,
            "expireAt": st.expireAt?.timeIntervalSince1970 ?? 0,
            "rulesVersion": RuleService.shared.version,
            "rulesText": currentRulesText(),
            "routes": routes,
            "statsDir": docs,
            "dnsIP": AppConfig.dnsProxyIP,
            "clientIP": AppConfig.clientIP,
            "sinkholeIP": AppConfig.sinkholeIP,
            "mtu": AppConfig.mtu,
            /* 1.2.3：拦截模式与端口段开关跟着配置一起进扩展。
               切模式后重连一次即可生效，不需要重装。 */
            "mode": mode.rawValue,
            "portBlock": portBlocking
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
/// 1.2.5 起：先 AES-256-GCM 加密，再带一段 HMAC 指纹。
/// 以前只签名不加密，手里拿到 plist 用文本编辑器就能读出卡密原文 ——
/// 越狱设备、iTunes 备份、任何备份提取工具都能直接拿走。
/// 现在落到盘上的是密文：内容读不出，改一个字节也验不过。
///
/// 老版本（HML1，只签名）仍能读，读出来立刻按新格式重写，用户无感。
private enum LicenseSeal {

    private static let magicV1 = Data([0x48, 0x4D, 0x4C, 0x31])   // HML1 旧格式
    private static let magicV2 = Data([0x48, 0x4D, 0x4C, 0x32])   // HML2 加密格式
    private static let tagLength = 32

    private static var key: SymmetricKey {
        let material = AppConfig.secureMasterKey + "|" + ConfigStore.makePin() + "|hm-seal-v1"
        return SymmetricKey(data: Data(SHA256.hash(data: Data(material.utf8))))
    }

    /// 加密用的密钥：与封条密钥分开派生，避免一处泄露同时丢两样
    private static var boxKey: SymmetricKey {
        let material = AppConfig.secureMasterKey + "|" + ConfigStore.makePin() + "|hm-box-v2"
        return SymmetricKey(data: Data(SHA256.hash(data: Data(material.utf8))))
    }

    static func isSealed(_ blob: Data) -> Bool {
        guard blob.count > 8 else { return false }
        let head = blob.prefix(4)
        return head == magicV1 || head == magicV2
    }

    static func seal(_ body: Data) -> Data {
        if let box = try? AES.GCM.seal(body, using: boxKey), let combined = box.combined {
            let tag = Data(HMAC<SHA256>.authenticationCode(for: combined, using: key))
            return magicV2 + combined + tag
        }
        /* 理论上走不到这里；真出问题也不丢用户授权，退回旧的签名格式 */
        let tag = Data(HMAC<SHA256>.authenticationCode(for: body, using: key))
        return magicV1 + body + tag
    }

    static func open(_ blob: Data) -> Data? {
        guard isSealed(blob) else { return nil }
        if blob.prefix(4) == magicV2 {
            let core = blob.dropFirst(4)
            guard core.count > tagLength else { return nil }
            let combined = Data(core.dropLast(tagLength))
            let tag = Data(core.suffix(tagLength))
            let expect = Data(HMAC<SHA256>.authenticationCode(for: combined, using: key))
            guard expect == tag else { return nil }
            guard let box = try? AES.GCM.SealedBox(combined: combined),
                  let plain = try? AES.GCM.open(box, using: boxKey) else { return nil }
            return plain
        }
        /* 旧格式：验签通过就当合法，调用方会立刻按新格式重写 */
        let core = blob.dropFirst(4)
        guard core.count > tagLength else { return nil }
        let body = Data(core.dropLast(tagLength))
        let tag = Data(core.suffix(tagLength))
        let expect = Data(HMAC<SHA256>.authenticationCode(for: body, using: key))
        guard expect == tag else { return nil }
        return body
    }
}
