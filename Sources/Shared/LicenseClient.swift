import Foundation

/// 服务端授权 / 公告通道（全部走 v3 加密）
/// 对接端点（ios.ouovo.cc）：
///   GET  /api/announcement   → 走加密 POST
///   POST /api/card/redeem    兑换 / 绑定卡密
///   POST /api/session/renew  续期（只推在线校验窗口）
///   POST /api/auth/check     强校验（App 启动 / 回前台 / 开 VPN 前必调）
///   POST /api/session/state  只读状态
final class LicenseClient {

    static let shared = LicenseClient()

    init() {}

    // MARK: - 公告

    struct Announcement {
        var title: String
        var content: String
        var updatedAt: String
    }

    func fetchAnnouncement(pin: String = "",
                           completion: @escaping (Announcement?) -> Void) {
        SecureChannel.post("/announcement", params: [:], pin: pin.isEmpty ? "00000000" : pin) { result in
            guard case .success(let obj) = result else {
                completion(nil); return
            }
            let title = (obj["title"] as? String) ?? ""
            var content = (obj["content"] as? String) ?? ""
            if content.isEmpty, let n = obj["notice"] as? String { content = n }
            let updated = (obj["updated_at"] as? String) ?? ""
            if title.isEmpty && content.isEmpty { completion(nil); return }
            completion(Announcement(title: title, content: content, updatedAt: updated))
        }
    }

    // MARK: - 授权

    /// 兑换卡密（首次激活 / 同设备再次兑换）
    func redeem(pin: String, code raw: String,
                completion: @escaping (Result<LicenseState, Error>) -> Void) {
        let code = CryptoBox.normaliseCode(raw)
        SecureChannel.post("/card/redeem", params: ["code": code], pin: pin) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let obj):
                guard (obj["ok"] as? Bool) == true else {
                    completion(.failure(self.mapError((obj["error"] as? String) ?? "")))
                    return
                }
                var st = LicenseState.empty(pin: pin)
                st.code = code
                self.apply(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    /// 续期：只推在线校验窗口，不改变卡密本身有效期
    func beat(pin: String, code: String,
              completion: @escaping (Result<LicenseState, Error>) -> Void) {
        SecureChannel.post("/session/renew", params: ["code": code], pin: pin) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let obj):
                guard (obj["ok"] as? Bool) == true else {
                    let err = (obj["error"] as? String) ?? ""
                    completion(.failure(self.mapError(err)))
                    return
                }
                var st = LicenseState.empty(pin: pin)
                st.code = code
                self.apply(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    /// 强校验：每次真的问服务端「这张卡现在还能不能用于是」
    /// 卡密被作废 / 到期 / 被删，都会在这里如实返回对应 reason
    func check(pin: String,
               completion: @escaping (Result<LicenseState, Error>) -> Void) {
        SecureChannel.post("/auth/check", params: [:], pin: pin) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let obj):
                var st = LicenseState.empty(pin: pin)
                st.code = ConfigStore.shared.license.code
                self.apply(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    /// 只读状态（不改服务端计数）
    func status(pin: String, code: String,
                completion: @escaping (Result<LicenseState, Error>) -> Void) {
        SecureChannel.post("/session/state", params: [:], pin: pin) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let obj):
                var st = LicenseState.empty(pin: pin)
                st.code = code
                self.apply(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    // MARK: - 解析

    /// 统一解析：窗口（expires_in / authorized_until）与卡密到期（card_seconds_left）分开落
    private func apply(_ obj: [String: Any], into st: inout LicenseState) {
        let now = Date()

        let reason = (obj["reason"] as? String) ?? ""
        let authorized = (obj["authorized"] as? Bool) ?? false

        /* 服务端明确给出 reason 就以它为准；没有 reason 的老响应按 authorized 反推 */
        if let v = LicenseVerdict(rawValue: reason) {
            st.verdict = v
        } else {
            st.verdict = authorized ? .ok : .unknown
        }

        st.authorized = authorized
        st.verifiedAt = now
        if authorized { st.lastCheck = now }

        if let left = num(obj["expires_in"]) {
            st.sessionUntil = now.addingTimeInterval(max(0, left))
        } else if let until = num(obj["authorized_until"]), until > 0 {
            st.sessionUntil = Date(timeIntervalSince1970: until)
        } else if let exp = num(obj["expire_at"]), exp > 0 {
            st.sessionUntil = Date(timeIntervalSince1970: exp)
        }

        if let cardLeft = num(obj["card_seconds_left"]) {
            st.expireAt = now.addingTimeInterval(max(0, cardLeft))
        } else if let ce = num(obj["card_expire_at"]), ce > 0 {
            st.expireAt = Date(timeIntervalSince1970: ce)
        }

        /* 卡密彻底失效：清掉窗口，避免任何地方再把它当有效 */
        if st.verdict.isHardFailure {
            st.sessionUntil = Date(timeIntervalSince1970: 0)
            st.authorized = false
        }
    }

    private func mapError(_ raw: String) -> LicenseError {
        switch raw.lowercased() {
        case "card_format":      return .badResponse("卡密格式不对，请检查有没有输错")
        case "card_not_found":   return .badResponse("卡密不存在")
        case "card_revoked":     return .revoked
        case "card_expired":     return .expired
        case "card_bound":       return .badResponse("这张卡已绑定其他设备，请联系管理员解绑")
        case "card_used":        return .badResponse("这张卡密刚被别的设备抢用了")
        case "rate_limited":     return .badResponse("请求太频繁，稍后再试")
        case "bad_pin":          return .badPin
        default: break
        }
        let s = raw.lowercased()
        if s.contains("expire") || s.contains("过期") { return .expired }
        if s.contains("pin") { return .badPin }
        if s.contains("not_found") || s.contains("used") || s.contains("invalid") {
            return .invalidCode
        }
        return .badResponse(raw.isEmpty ? "卡密验证失败" : raw)
    }

    /// JSON 数字可能是 Int / Double / 字符串，统一成 Double
    private func num(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return nil
    }
}
