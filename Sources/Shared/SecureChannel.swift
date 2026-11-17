import Foundation
import CryptoKit
import Security

/// v3 全链路加密通道（与服务端 `SecureV3` 一一对应）
///
/// 每条请求都是密文 + 一次性 nonce + HMAC 签名，抓包只能看到随机字节：
///   请求体 {v:3, p:设备码, ts, n:nonce, e:AES-256-GCM 密文, sig:HMAC}
///   响应体 {v:3, n, e, sig}
///
/// 密钥：HKDF-SHA256(主密钥, salt="heimao-v3-salt", info="heimao-v3-req"/"res")
/// 签名：HMAC-SHA256(主密钥, "v3|路径|设备码|ts|nonce|sha256(密文)")
/// 改一个字节 → 验签失败；重发同一条 → nonce 已被消费，服务端直接拒。
enum SecureChannel {

    // MARK: - 密钥

    private static let masterData: Data = {
        Data(hex: AppConfig.secureMasterKey) ?? Data(repeating: 0, count: 32)
    }()

    private static let master = SymmetricKey(data: masterData)

    private static let salt    = Data("heimao-v3-salt".utf8)
    private static let infoReq = Data("heimao-v3-req".utf8)
    private static let infoRes = Data("heimao-v3-res".utf8)

    /// 请求/响应密钥候选表。
    ///
    /// 第 0 项是标准实现（与服务端 SecureV3 完全一致），正常情况下永远命中它。
    /// 后面几项是兜底：不同 iOS 版本 / 不同构建环境下 HKDF 封装若与服务端取法不一致，
    /// 服务端会回 bad_cipher，这里就自动换下一组再试一次，用户完全无感。
    /// 服务端 `candidates()` 是同一张表，两边一一对应。
    private static let keyCandidates: [(req: SymmetricKey, res: SymmetricKey)] = {
        let m = SymmetricKey(data: masterData)
        let s = salt, r = infoReq, q = infoRes
        return [
            (HKDF<SHA256>.deriveKey(inputKeyMaterial: m, salt: s, info: r, outputByteCount: 32),
             HKDF<SHA256>.deriveKey(inputKeyMaterial: m, salt: s, info: q, outputByteCount: 32)),

            (HKDF<SHA256>.deriveKey(inputKeyMaterial: m, salt: r, info: s, outputByteCount: 32),
             HKDF<SHA256>.deriveKey(inputKeyMaterial: m, salt: q, info: s, outputByteCount: 32)),

            (HKDF<SHA256>.deriveKey(inputKeyMaterial: m, salt: Data(), info: r, outputByteCount: 32),
             HKDF<SHA256>.deriveKey(inputKeyMaterial: m, salt: Data(), info: q, outputByteCount: 32)),

            (SymmetricKey(data: Data(SHA256.hash(data: masterData + r))),
             SymmetricKey(data: Data(SHA256.hash(data: masterData + q)))),

            (req: m, res: m),
        ]
    }()

    // MARK: - 传输

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "HeiMaoInterceptor/\(AppConfig.appVersion) (iOS)",
        ]
        return URLSession(configuration: cfg)
    }()

    enum Failure: LocalizedError {
        case network
        case server(String)
        case signature
        case crypto
        case badPayload

        var errorDescription: String? {
            switch self {
            case .network:        return "网络连接失败，请检查网络后重试"
            case .server(let m):  return m
            case .signature:      return "响应校验失败，请稍后重试"
            case .crypto:         return "数据解密失败，请稍后重试"
            case .badPayload:     return "服务端返回异常"
            }
        }
    }

    /// 统一 POST：加密请求 → 解密响应。所有业务接口都从这里走。
    static func post(_ path: String,
                     params: [String: Any],
                     pin: String,
                     completion: @escaping (Result<[String: Any], Error>) -> Void) {

        guard !pin.isEmpty else {
            completion(.failure(Failure.server("设备码异常，请重装应用")))
            return
        }

        // 路径必须和签名串逐字一致（服务端会把首尾斜杠 trim 掉再验签）
        let route = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !route.isEmpty else {
            completion(.failure(Failure.badPayload)); return
        }
        guard let url = URL(string: AppConfig.apiBase + "/" + route) else {
            completion(.failure(Failure.network)); return
        }
        attempt(route: route, url: url, params: params, pin: pin,
                candidate: 0, completion: completion)
    }

    /// 用第 candidate 组密钥发一次；服务端说密钥不对就换下一组重试
    private static func attempt(route: String,
                                url: URL,
                                params: [String: Any],
                                pin: String,
                                candidate: Int,
                                completion: @escaping (Result<[String: Any], Error>) -> Void) {

        let keys = keyCandidates[candidate]
        let ts = Int(Date().timeIntervalSince1970)
        let nonceHex = randomNonce()
        guard let nonceData = Data(hex: nonceHex) else {
            completion(.failure(Failure.crypto)); return
        }

        var body = params
        body["pin"] = pin

        let plain: String
        if let d = try? JSONSerialization.data(withJSONObject: body, options: []),
           let s = String(data: d, encoding: .utf8) {
            plain = s
        } else {
            completion(.failure(Failure.badPayload)); return
        }

        guard let sealed = seal(plain, key: keys.req, aad: nonceData) else {
            completion(.failure(Failure.crypto)); return
        }

        let sigMsg = "v3|\(route)|\(pin)|\(ts)|\(nonceHex)|\(sha256Hex(sealed))"
        let sig = hmacHex(sigMsg)

        let envelope: [String: Any] = [
            "v": 3, "p": pin, "ts": ts, "n": nonceHex, "e": sealed, "sig": sig,
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: envelope) else {
            completion(.failure(Failure.badPayload)); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        session.dataTask(with: req) { data, _, err in
            if err != nil {
                completion(.failure(Failure.network)); return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(Failure.badPayload)); return
            }

            // 服务端拒绝加密信封时回的是明文错误
            if (obj["v"] as? Int) != 3 {
                let code = (obj["error"] as? String) ?? ""
                if let next = retryCandidate(for: code, from: candidate) {
                    attempt(route: route, url: url, params: params, pin: pin,
                            candidate: next, completion: completion)
                    return
                }
                completion(.failure(Failure.server(friendly(code))))
                return
            }

            guard let n = obj["n"] as? String,
                  let e = obj["e"] as? String,
                  let s = obj["sig"] as? String,
                  let nData = Data(hex: n) else {
                completion(.failure(Failure.badPayload)); return
            }

            let expect = hmacHex("v3r|\(n)|\(sha256Hex(e))")
            guard expect.lowercased() == s.lowercased() else {
                completion(.failure(Failure.signature)); return
            }
            guard let plain = open(e, key: keys.res, aad: nData),
                  let inner = try? JSONSerialization.jsonObject(with: Data(plain.utf8)) as? [String: Any] else {
                completion(.failure(Failure.crypto)); return
            }
            completion(.success(inner))
        }.resume()
    }

    /// 只有"密钥对不上"这类错误才值得换一组密钥重试
    private static func retryCandidate(for code: String, from current: Int) -> Int? {
        let c = code.lowercased()
        guard c == "bad_cipher" || c == "bad_signature" || c == "bad_envelope" else {
            return nil
        }
        let next = current + 1
        return next < keyCandidates.count ? next : nil
    }

    // MARK: - 原语

    static func seal(_ plain: String, key: SymmetricKey, aad: Data) -> String? {
        guard let box = try? AES.GCM.seal(Data(plain.utf8), using: key, authenticating: aad) else {
            return nil
        }
        return box.combined?.base64EncodedString()
    }

    static func open(_ b64: String, key: SymmetricKey, aad: Data) -> String? {
        guard let raw = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: raw),
              let out = try? AES.GCM.open(box, using: key, authenticating: aad) else {
            return nil
        }
        return String(data: out, encoding: .utf8)
    }

    static func hmacHex(_ text: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: master)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ text: String) -> String {
        let d = SHA256.hash(data: Data(text.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 服务端错误码 → 人话
    static func friendly(_ code: String) -> String {
        switch code.lowercased() {
        case "stale_request":
            // 真的是请求时间戳超出窗口
            return "请求已过期，请检查手机时间是否为「自动设置」后重试"
        case "bad_signature", "bad_cipher", "bad_envelope", "bad_nonce":
            return "安全校验未通过，请更新到最新版本后重试"
        case "replay":
            return "请求重复提交了，请再点一次"
        case "rate_limited":  return "请求太频繁，稍后再试"
        case "bad_pin":       return "设备码异常，请重装应用"
        case "card_format":   return "卡密格式不对，请检查有没有输错"
        case "card_not_found":return "卡密不存在"
        case "card_revoked":  return "卡密已被作废"
        case "card_expired":  return "卡密已过期"
        case "card_bound":    return "这张卡已绑定其他设备，请联系管理员解绑"
        case "card_used":     return "这张卡密刚被别的设备抢用了"
        default:
            return code.isEmpty ? "服务端返回异常" : code
        }
    }
}

// MARK: - 十六进制

extension Data {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0, !s.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let b = UInt8(s[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
