import Foundation

/// 服务端给出的授权判定结果（唯一权威）
///
/// 之前的问题：界面只看本地缓存时间，卡密在后台被作废之后
/// App 仍然显示「已授权」，但隧道一联网校验就失败、VPN 起不来。
/// 现在授权状态以服务端为准，本地缓存只负责「断网时别立刻掉线」。
enum LicenseVerdict: String, Codable {
    case ok                 = "ok"                 // 授权有效
    case noCard             = "no_card"            // 没绑卡密
    case cardNotFound       = "card_not_found"     // 卡密被删了
    case cardRevoked        = "card_revoked"       // 被后台作废
    case cardExpired        = "card_expired"       // 卡密到期
    case windowExpired      = "window_expired"     // 在线校验窗口过期（断网太久）
    case kicked             = "kicked"             // 后台强制下线
    case unknown            = "unknown"            // 还没校验过（老数据）

    /// 这几种属于「彻底不能用了」，不享受任何离线宽限
    var isHardFailure: Bool {
        switch self {
        case .cardRevoked, .cardExpired, .cardNotFound, .noCard, .kicked: return true
        default: return false
        }
    }

    var isBlocking: Bool { self != .ok }
}

/// 卡密授权状态（本地缓存 + 服务端校验）
///
/// 关键区分：
///   expireAt      卡密本身的到期时间（天 / 月 / 年，服务端 card_expire_at）
///   sessionUntil  本次在线校验窗口的结束时间（服务端 authorized_until，默认 600 秒）
/// 两者不能混用，否则窗口一过就会被误判成"卡密过期"。
struct LicenseState: Codable {
    var pin: String                 // 设备码（服务端识别用）
    var code: String                // 兑换过的卡密（规范化的 XXXX-XXXX-XXXX-XXXX）
    var authorized: Bool            // 服务端最近一次是否认可
    var expireAt: Date?             // 卡密到期时间
    var sessionUntil: Date?         // 在线校验窗口结束时间
    var lastCheck: Date             // 上次成功校验时间
    var configKid: String?          // 云端规则版本
    var configExpire: Date?         // 规则包时效
    var note: String?
    var verdict: LicenseVerdict     // 服务端判定结果
    var verifiedAt: Date?           // 上次拿到服务端明确结论的时间
    var tier: String                // 卡密版本：free / beta / pro / max
    var banReason: String?          // 被封禁的原因（后台填写，客户端展示）
    var kicked: Bool                // 是否被管理员强制下线
    var kickReason: String?         // 下线原因

    enum CodingKeys: String, CodingKey {
        case pin, code, authorized, expireAt, sessionUntil, lastCheck,
             configKid, configExpire, note, verdict, verifiedAt,
             tier, banReason, kicked, kickReason
    }

    init(pin: String, code: String, authorized: Bool, expireAt: Date?, sessionUntil: Date?,
         lastCheck: Date, configKid: String?, configExpire: Date?, note: String?,
         verdict: LicenseVerdict = .unknown, verifiedAt: Date? = nil,
         tier: String = "pro", banReason: String? = nil,
         kicked: Bool = false, kickReason: String? = nil) {
        self.pin = pin
        self.code = code
        self.authorized = authorized
        self.expireAt = expireAt
        self.sessionUntil = sessionUntil
        self.lastCheck = lastCheck
        self.configKid = configKid
        self.configExpire = configExpire
        self.note = note
        self.verdict = verdict
        self.verifiedAt = verifiedAt
        self.tier = tier
        self.banReason = banReason
        self.kicked = kicked
        self.kickReason = kickReason
    }

    /// 老版本数据兼容：缺 verdict 一律当 unknown（下次启动会被强制校验）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pin = try c.decode(String.self, forKey: .pin)
        code = try c.decode(String.self, forKey: .code)
        authorized = (try? c.decode(Bool.self, forKey: .authorized)) ?? false
        expireAt = try? c.decodeIfPresent(Date.self, forKey: .expireAt)
        sessionUntil = try? c.decodeIfPresent(Date.self, forKey: .sessionUntil)
        lastCheck = (try? c.decode(Date.self, forKey: .lastCheck)) ?? .distantPast
        configKid = try? c.decodeIfPresent(String.self, forKey: .configKid)
        configExpire = try? c.decodeIfPresent(Date.self, forKey: .configExpire)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        verdict = (try? c.decode(LicenseVerdict.self, forKey: .verdict)) ?? .unknown
        verifiedAt = try? c.decodeIfPresent(Date.self, forKey: .verifiedAt)
        tier = (try? c.decode(String.self, forKey: .tier)) ?? "pro"
        banReason = try? c.decodeIfPresent(String.self, forKey: .banReason)
        kicked = (try? c.decode(Bool.self, forKey: .kicked)) ?? false
        kickReason = try? c.decodeIfPresent(String.self, forKey: .kickReason)
    }

    static func empty(pin: String) -> LicenseState {
        LicenseState(pin: pin, code: "", authorized: false, expireAt: nil,
                     sessionUntil: nil, lastCheck: .distantPast,
                     configKid: nil, configExpire: nil, note: nil,
                     verdict: .noCard, verifiedAt: nil)
    }

    /// 唯一判定口径
    /// - 服务端明确判死（作废/到期/不存在）→ 立刻不可用，不给宽限
    /// - 服务端说 ok → 再看卡密到期时间
    /// - 断网（window_expired / unknown）→ 窗口 + 宽限内仍可用
    func isUsable(now: Date = Date()) -> Bool {
        guard !code.isEmpty else { return false }
        if let exp = expireAt, exp <= now { return false }

        switch verdict {
        case .ok:
            if let s = sessionUntil {
                return now < s.addingTimeInterval(AppConfig.offlineGrace)
            }
            return now.timeIntervalSince(lastCheck) < AppConfig.offlineGrace

        case .cardRevoked, .cardExpired, .cardNotFound, .noCard, .kicked:
            return false

        case .windowExpired, .unknown:
            /* 断网/刚升级：窗口 + 宽限内先保持，等下一次校验定论 */
            if let s = sessionUntil {
                return now < s.addingTimeInterval(AppConfig.offlineGrace)
            }
            return now.timeIntervalSince(lastCheck) < AppConfig.offlineGrace
        }
    }

    /// 只有服务端明确判死才值得当场停隧道
    ///
    /// 1.2.2 新增：以前只要 `isUsable()` 为 false 就 stop 隧道 —— 而窗口过期
    /// （长时间后台、刚切网）也算 false，于是「回到前台网络还没恢复」这一下
    /// 就把正在跑的防护掐了。现在分开：这里 true 才停，其余只提示、等下一次校验。
    var isHardInvalid: Bool {
        if code.isEmpty { return true }
        if let exp = expireAt, exp <= Date() { return true }
        return verdict.isHardFailure
    }

    /// 界面统一用的状态文案
    func statusText(now: Date = Date()) -> String {
        if code.isEmpty { return "未激活" }
        switch verdict {
        case .cardRevoked:   return "卡密已封禁"
        case .cardExpired:   return "卡密已过期"
        case .cardNotFound:  return "卡密不存在"
        case .kicked:        return "已被强制下线"
        case .noCard:        return "未绑定卡密"
        case .ok:
            if let exp = expireAt, exp <= now { return "卡密已过期" }
            if let s = sessionUntil, now >= s { return "离线校验中" }
            return "已授权"
        case .windowExpired: return "待重新校验"
        case .unknown:       return isUsable(now: now) ? "已授权" : "待校验"
        }
    }

    /// 出问题时的完整说明（主界面横幅用）
    var blockReason: String? {
        guard !isUsable() else { return nil }
        if code.isEmpty { return "还没有激活卡密，开启防护前请先输入卡密" }
        switch verdict {
        case .cardRevoked:
            if let r = banReason, !r.isEmpty {
                return "这张卡密已被封禁：\(r)。防护已停止，如有疑问请联系管理员"
            }
            return "这张卡密已被封禁，防护已停止。如需继续使用请联系管理员或换一张卡"
        case .kicked:
            if let r = kickReason, !r.isEmpty {
                return "当前设备已被管理员强制下线：\(r)。VPN 已断开、规则已清空"
            }
            return "当前设备已被管理员强制下线。VPN 已断开、规则已清空"
        case .cardExpired:   return "卡密已到期，防护已停止。续费后点「刷新状态」即可恢复"
        case .cardNotFound:  return "这张卡密已不存在，请重新激活"
        case .noCard:        return "当前设备没有绑定卡密"
        case .windowExpired: return "太久没有校验，请连接网络后点「刷新状态」"
        case .unknown:       return "授权状态待确认，请连接网络后点「刷新状态」"
        case .ok:            return "授权已失效"
        }
    }

    var expireText: String {
        guard let exp = expireAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: exp)
    }

    /// 剩余时间（按天/小时）
    var remainText: String {
        guard let exp = expireAt else { return "—" }
        let s = Int(exp.timeIntervalSinceNow)
        if s <= 0 { return "已到期" }
        let day = s / 86400
        if day >= 1 { return "\(day) 天 \((s % 86400) / 3600) 小时" }
        if s >= 3600 { return "\(s / 3600) 小时 \((s % 3600) / 60) 分" }
        return "\(s / 60) 分钟"
    }

    var sessionText: String {
        guard let s = sessionUntil else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: s)
    }

    /// 卡密版本（界面徽章）：FREE / BETA / PRO / MAX
    var tierLabel: String {
        let t = tier.lowercased()
        switch t {
        case "free": return "FREE"
        case "beta": return "BETA"
        case "max":  return "MAX"
        default:     return "PRO"
        }
    }

    var maskedCode: String {
        guard code.count > 8 else { return code.isEmpty ? "—" : code }
        return String(code.prefix(4)) + "-****-****-" + String(code.suffix(4))
    }
}

/// 服务端返回的加密配置包（旧协议，保留结构兼容）
/// 形如：{"kid":"cfg-20261117","exp":1794851086,"alg":"A256GCM","iv":"base64","ct":"base64"}
struct RemoteConfigEnvelope: Codable {
    var kid: String
    var exp: Int
    var alg: String
    var iv: String
    var ct: String
}

/// 解密后的配置内容（旧协议）
struct RemoteConfigPayload: Codable {
    var version: Int
    var rules: String
    var ruleURL: String?
    var notice: String?
    var minBuild: Int?
}

enum LicenseError: LocalizedError {
    case network
    case badResponse(String)
    case invalidCode
    case expired
    case revoked
    case crypto
    case badPin

    var errorDescription: String? {
        switch self {
        case .network:            return "网络连接失败，请检查网络后重试"
        case .badResponse(let m): return m.isEmpty ? "服务端返回异常" : m
        case .invalidCode:        return "卡密无效或已被使用"
        case .expired:            return "卡密已过期"
        case .revoked:            return "卡密已被作废"
        case .crypto:             return "配置包校验失败"
        case .badPin:             return "设备码异常，请重装应用"
        }
    }
}
