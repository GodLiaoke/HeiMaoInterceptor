import Foundation

/// 卡密授权状态（本地缓存 + 服务端校验）
///
/// 关键区分：
///   expireAt      卡密本身的到期时间（天 / 月 / 年，服务端 card_expire_at）
///   sessionUntil  本次在线校验窗口的结束时间（服务端 authorized_until，默认 600 秒）
/// 两者不能混用，否则窗口一过就会被误判成"卡密过期"。
struct LicenseState: Codable {
    var pin: String                 // 设备码（服务端识别用）
    var code: String                // 兑换过的卡密（规范化的 XXXX-XXXX-XXXX-XXXX）
    var authorized: Bool            // 服务端最近一次是否认可（仅参考，判定统一走 isUsable）
    var expireAt: Date?             // 卡密到期时间
    var sessionUntil: Date?         // 在线校验窗口结束时间
    var lastCheck: Date             // 上次成功校验时间
    var configKid: String?          // 云端规则版本
    var configExpire: Date?         // 规则包时效
    var note: String?

    /// 旧版本数据兼容：缺失 sessionUntil 时按 lastCheck + 窗口推算
    private enum CodingKeys: String, CodingKey {
        case pin, code, authorized, expireAt, sessionUntil, lastCheck, configKid, configExpire, note
    }

    init(pin: String, code: String, authorized: Bool, expireAt: Date?, sessionUntil: Date?,
         lastCheck: Date, configKid: String?, configExpire: Date?, note: String?) {
        self.pin = pin
        self.code = code
        self.authorized = authorized
        self.expireAt = expireAt
        self.sessionUntil = sessionUntil
        self.lastCheck = lastCheck
        self.configKid = configKid
        self.configExpire = configExpire
        self.note = note
    }

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
    }

    static func empty(pin: String) -> LicenseState {
        LicenseState(pin: pin, code: "", authorized: false, expireAt: nil,
                     sessionUntil: nil, lastCheck: .distantPast,
                     configKid: nil, configExpire: nil, note: nil)
    }

    /// 唯一判定口径：卡密没到期 + 窗口没过（含宽限）
    func isUsable(now: Date = Date()) -> Bool {
        guard !code.isEmpty else { return false }
        if let exp = expireAt, exp <= now { return false }
        if let s = sessionUntil {
            return now < s.addingTimeInterval(AppConfig.offlineGrace)
        }
        /* 旧数据没有窗口字段：按最后校验时间兜底 */
        return now.timeIntervalSince(lastCheck) < AppConfig.offlineGrace
    }

    /// 界面统一用的状态文案
    func statusText(now: Date = Date()) -> String {
        if code.isEmpty { return "未激活" }
        if let exp = expireAt, exp <= now { return "卡密已过期" }
        if !isUsable(now: now) { return "校验失效" }
        if let s = sessionUntil, now >= s { return "离线校验中" }
        return "已授权"
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
    case crypto
    case badPin

    var errorDescription: String? {
        switch self {
        case .network:            return "网络连接失败，请检查网络后重试"
        case .badResponse(let m): return m.isEmpty ? "服务端返回异常" : m
        case .invalidCode:        return "卡密无效或已被使用"
        case .expired:            return "卡密已过期"
        case .crypto:             return "配置包校验失败"
        case .badPin:             return "设备码异常，请重装应用"
        }
    }
}
