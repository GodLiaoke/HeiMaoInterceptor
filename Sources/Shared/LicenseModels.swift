import Foundation

/// 卡密授权状态（本地缓存 + 服务端校验）
struct LicenseState: Codable {
    var pin: String                 // 设备码（服务端识别用）
    var code: String                // 兑换过的卡密
    var authorized: Bool
    var expireAt: Date?             // 服务端给的到期时间
    var lastCheck: Date             // 上次成功校验时间
    var configKid: String?          // 云端配置包版本
    var configExpire: Date?         // 配置包时效
    var note: String?

    static func empty(pin: String) -> LicenseState {
        LicenseState(pin: pin, code: "", authorized: false, expireAt: nil,
                     lastCheck: .distantPast, configKid: nil, configExpire: nil, note: nil)
    }

    /// 本地判定：有期限看期限，离线走宽限
    func isUsable(now: Date = Date()) -> Bool {
        guard authorized else { return false }
        if let exp = expireAt, exp <= now { return false }
        if now.timeIntervalSince(lastCheck) > AppConfig.offlineGrace { return false }
        return true
    }

    var expireText: String {
        guard let exp = expireAt else { return "未激活" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: exp)
    }
}

/// 服务端返回的加密配置包
/// 形如：{"kid":"cfg-20261117","exp":1794851086,"alg":"A256GCM","iv":"base64","ct":"base64"}
struct RemoteConfigEnvelope: Codable {
    var kid: String
    var exp: Int
    var alg: String
    var iv: String
    var ct: String
}

/// 解密后的配置内容
struct RemoteConfigPayload: Codable {
    var version: Int
    var rules: String            // 完整规则文本（与内置格式一致）
    var ruleURL: String?         // 备用：远程规则地址
    var notice: String?          // 云端公告
    var minBuild: Int?           // 最低客户端 build
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
