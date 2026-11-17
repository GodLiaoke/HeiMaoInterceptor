import Foundation

/// 服务端授权 / 公告通道
/// 对接端点（ios.ouovo.cc）：
///   GET  /api/announcement
///   POST /api/card/redeem      兑换 / 绑定卡密
///   POST /api/session/renew    续期（只推在线校验窗口）
///   GET  /api/session/state    只读状态
final class LicenseClient {

    static let shared = LicenseClient()

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.httpAdditionalHeaders = ["Accept": "application/json",
                                     "User-Agent": "HeiMaoInterceptor/\(AppConfig.appVersion) (iOS)"]
        session = URLSession(configuration: cfg)
    }

    // MARK: - 公告

    struct Announcement {
        var title: String
        var content: String
        var updatedAt: String
    }

    func fetchAnnouncement(completion: @escaping (Announcement?) -> Void) {
        guard let url = URL(string: AppConfig.apiBase + "/announcement") else {
            completion(nil); return
        }
        session.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil); return
            }
            let title = (obj["title"] as? String) ?? ""
            var content = (obj["content"] as? String) ?? ""
            if content.isEmpty, let n = obj["notice"] as? String { content = n }
            let updated = (obj["updated_at"] as? String) ?? ""
            if title.isEmpty && content.isEmpty { completion(nil); return }
            completion(Announcement(title: title, content: content, updatedAt: updated))
        }.resume()
    }

    // MARK: - 授权

    /// 兑换卡密（首次激活 / 同设备再次兑换）
    func redeem(pin: String, code raw: String,
                completion: @escaping (Result<LicenseState, Error>) -> Void) {
        let code = CryptoBox.normaliseCode(raw)
        post(path: "/card/redeem", body: ["pin": pin, "code": code]) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let obj):
                guard (obj["ok"] as? Bool) == true else {
                    let raw = (obj["error"] as? String) ?? ""
                    completion(.failure(self.mapError(raw)))
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
        post(path: "/session/renew", body: ["pin": pin, "code": code]) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let obj):
                guard (obj["ok"] as? Bool) == true else {
                    let raw = (obj["error"] as? String) ?? ""
                    completion(.failure(self.mapError(raw)))
                    return
                }
                var st = LicenseState.empty(pin: pin)
                st.code = code
                self.apply(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    /// 只读状态（不改服务端计数）
    func status(pin: String, code: String,
                completion: @escaping (Result<LicenseState, Error>) -> Void) {
        var comps = URLComponents(string: AppConfig.apiBase + "/session/state")
        comps?.queryItems = [URLQueryItem(name: "pin", value: pin)]
        guard let url = comps?.url else {
            completion(.failure(LicenseError.network)); return
        }
        session.dataTask(with: url) { data, _, err in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(err ?? LicenseError.network)); return
            }
            var st = LicenseState.empty(pin: pin)
            st.code = code
            self.apply(obj, into: &st)
            completion(.success(st))
        }.resume()
    }

    // MARK: - 解析

    /// 统一解析：窗口（expires_in / authorized_until）与卡密到期（card_seconds_left）分开落
    private func apply(_ obj: [String: Any], into st: inout LicenseState) {
        let now = Date()
        st.lastCheck = now
        st.authorized = (obj["authorized"] as? Bool) ?? ((obj["ok"] as? Bool) ?? true)

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
    }

    private func mapError(_ raw: String) -> LicenseError {
        switch raw.lowercased() {
        case "card_format":      return .badResponse("卡密格式不对，请检查有没有输错")
        case "card_not_found":   return .badResponse("卡密不存在")
        case "card_revoked":     return .badResponse("卡密已被作废")
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

    // MARK: - 基础请求

    private func post(path: String, body: [String: Any],
                      completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: AppConfig.apiBase + path) else {
            completion(.failure(LicenseError.network)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req) { data, resp, err in
            if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 500 {
                completion(.failure(LicenseError.badResponse("服务端错误 \(code)"))); return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(err ?? LicenseError.network)); return
            }
            completion(.success(obj))
        }.resume()
    }
}
