import Foundation

/// 服务端授权/公告通道
/// 对接端点（ios.ouovo.cc）：
///   GET  /api/announcement
///   GET  /api/pin/status?pin=
///   POST /api/pin/beat       {pin}
///   POST /api/card/redeem    {pin, code}
final class LicenseClient {

    static let shared = LicenseClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 20
        cfg.httpAdditionalHeaders = ["Accept": "application/json",
                                     "User-Agent": "HeiMaoInterceptor/1.0 (iOS)"]
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

    /// 兑换卡密（首次激活）
    func redeem(pin: String, code: String,
                completion: @escaping (Result<LicenseState, Error>) -> Void) {
        post(path: "/card/redeem", body: ["pin": pin, "code": code]) { result in
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
                st.code = code.uppercased()
                st.authorized = true
                st.lastCheck = Date()
                if let exp = obj["expire_at"] as? Double {
                    st.expireAt = Date(timeIntervalSince1970: exp)
                } else if let insec = obj["expires_in"] as? Double {
                    st.expireAt = Date().addingTimeInterval(insec)
                }
                self.applyEnvelope(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    /// 心跳 / 状态查询
    func status(pin: String, code: String,
                completion: @escaping (Result<LicenseState, Error>) -> Void) {
        var url = AppConfig.apiBase + "/pin/status?pin=" + (pin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pin)
        if !code.isEmpty {
            url += "&code=" + (code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)
        }
        guard let u = URL(string: url) else {
            completion(.failure(LicenseError.network)); return
        }
        session.dataTask(with: u) { data, _, err in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(err ?? LicenseError.network)); return
            }
            var st = LicenseState.empty(pin: pin)
            st.code = code
            st.authorized = (obj["authorized"] as? Bool) ?? false
            st.lastCheck = Date()
            if let exp = obj["expire_at"] as? Double {
                st.expireAt = Date(timeIntervalSince1970: exp)
            } else if let insec = obj["expires_in"] as? Double, insec > 0 {
                st.expireAt = Date().addingTimeInterval(insec)
            }
            if let note = obj["note"] as? String { st.note = note }
            self.applyEnvelope(obj, into: &st)
            completion(.success(st))
        }.resume()
    }

    /// 心跳（保活 + 拉最新配置）
    func beat(pin: String, code: String,
              completion: @escaping (Result<LicenseState, Error>) -> Void) {
        post(path: "/pin/beat", body: ["pin": pin, "code": code]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let obj):
                var st = LicenseState.empty(pin: pin)
                st.code = code
                st.authorized = (obj["authorized"] as? Bool) ?? false
                st.lastCheck = Date()
                if let exp = obj["expire_at"] as? Double {
                    st.expireAt = Date(timeIntervalSince1970: exp)
                } else if let insec = obj["expires_in"] as? Double, insec > 0 {
                    st.expireAt = Date().addingTimeInterval(insec)
                }
                self.applyEnvelope(obj, into: &st)
                completion(.success(st))
            }
        }
    }

    // MARK: - 云端配置包

    /// 若响应里带 cfg（加密信封），立刻解密并落地
    private func applyEnvelope(_ obj: [String: Any], into st: inout LicenseState) {
        guard let cfg = obj["cfg"],
              let data = try? JSONSerialization.data(withJSONObject: cfg),
              let env = try? decoder.decode(RemoteConfigEnvelope.self, from: data) else { return }
        guard let plain = try? CryptoBox.open(envelope: env, pin: st.pin, code: st.code),
              let payload = try? CryptoBox.decodePayload(plain) else { return }
        st.configKid = env.kid
        st.configExpire = Date(timeIntervalSince1970: TimeInterval(env.exp))
        ConfigStore.shared.saveRemotePayload(payload)
    }

    private func mapError(_ raw: String) -> LicenseError {
        let s = raw.lowercased()
        if s.contains("expire") || s.contains("过期") { return .expired }
        if s.contains("pin") { return .badPin }
        if s.contains("rate") { return .badResponse("请求太频繁，稍后再试") }
        if s.contains("not_found") || s.contains("used") || s.contains("invalid") {
            return .invalidCode
        }
        return .badResponse(raw.isEmpty ? "卡密验证失败" : raw)
    }

    // MARK: - 基础 POST

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
            if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
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
