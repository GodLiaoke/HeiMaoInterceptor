import Foundation
import CryptoKit
import Security

/// 全链路加密通道 v4 —— **只走 v4，不降级**
///
/// 抓包看到的东西：
///   请求体 = iv(12) || AES-256-GCM 密文 || tag(16)
///   响应体 = iv(12) || AES-256-GCM 密文 || tag(16)
/// 没有 JSON 信封、没有 v/n/e/sig 这类一眼能看懂的字段、没有任何自定义头。
/// 业务成功还是失败也只有解开密文才知道（HTTP 恒 200）。
///
/// 密钥（每条请求独立）：
///   请求 = HKDF-SHA512(master, salt=iv, info="hm4/req", 32B)
///   响应 = HKDF-SHA512(master, salt=请求iv, info="hm4/res", 32B)
/// AAD 绑定「路由 + 本条 iv」，同一段密文挪到别的接口直接解不开。
/// 签名 = HMAC-SHA512(master, "h4|路由|设备码|ts|ivhex|sha256(参数规范串)")
///
/// 1.2.0 起**不再提供 v3 / 明文降级**：
/// 通道任何一环对不上就直接报错让用户升级，绝不退回可被抓包的旧协议。
enum SecureChannel {

    // MARK: - 密钥

    private static let masterData: Data = {
        Data(hex: AppConfig.secureMasterKey) ?? Data(repeating: 0, count: 32)
    }()

    private static let master = SymmetricKey(data: masterData)

    // MARK: - 传输

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = [
            "Accept": "application/octet-stream",
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
        case v4Unavailable

        var errorDescription: String? {
            switch self {
            case .network:        return "网络连接失败，请检查网络后重试"
            case .server(let m):  return m
            case .signature:      return "响应校验失败，请稍后重试"
            case .crypto:         return "数据解密失败，请稍后重试"
            case .badPayload:     return "服务端返回异常"
            case .v4Unavailable:  return "安全通道校验失败，请更新到最新版本"
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

        /* CRC 链第 0 环：走通道之前先自检，链断了 code 会变成 crc 并上报 */
        _ = Integrity.shared.arm(0)

        // 路径必须和签名串逐字一致（服务端会把首尾斜杠 trim 掉再验签）
        let route = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !route.isEmpty else {
            completion(.failure(Failure.badPayload)); return
        }
        guard let url = URL(string: AppConfig.apiBase + "/" + route) else {
            completion(.failure(Failure.network)); return
        }

        attemptV4(route: route, url: url, params: params, pin: pin) { result in
            switch result {
            case .success(let obj):
                completion(.success(obj))
            case .failure(let err):
                /* 不降级：通道对不上就如实报错，绝不退回 v3 / 明文 */
                if let f = err as? Failure, case .v4Unavailable = f {
                    completion(.failure(Failure.server("安全通道校验失败，请更新到最新版本后重试")))
                } else {
                    completion(.failure(err))
                }
            }
        }
    }

    // MARK: - v4 裸密文通道

    /// 与 PHP 侧 canonical() 逐字一致：key 字典序，k=v 用 0x1F 连接
    static func canonical(_ params: [String: Any]) -> String {
        let keys = params.keys.sorted()
        let pairs: [String] = keys.map { k in
            let v = params[k]
            let text: String
            if let b = v as? Bool {
                text = b ? "1" : "0"
            } else if let str = v as? String {
                text = str
            } else if let i = v as? Int {
                text = String(i)
            } else if let d = v as? Double {
                text = (d == d.rounded()) ? String(Int(d)) : String(d)
            } else if let n = v as? NSNumber {
                text = n.stringValue
            } else {
                text = "\(v ?? "")"
            }
            return k + "=" + text
        }
        return pairs.joined(separator: "\u{1F}")
    }

    static func hmacSha512Hex(_ text: String) -> String {
        let mac = HMAC<SHA512>.authenticationCode(for: Data(text.utf8), using: master)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private static func sealBlob(_ plain: String, key: SymmetricKey, iv: Data, aad: Data) -> Data? {
        guard let nonce = try? AES.GCM.Nonce(data: iv),
              let box = try? AES.GCM.seal(Data(plain.utf8), using: key,
                                          nonce: nonce, authenticating: aad) else {
            return nil
        }
        var out = iv
        out.append(box.ciphertext)
        out.append(box.tag)
        return out
    }

    private static func openBlob(_ raw: Data, key: SymmetricKey, aad: Data) -> String? {
        guard raw.count >= 29 else { return nil }
        let iv = raw.prefix(12)
        let tag = raw.suffix(16)
        let ct = raw.dropFirst(12).dropLast(16)
        guard let nonce = try? AES.GCM.Nonce(data: Data(iv)),
              let box = try? AES.GCM.SealedBox(nonce: nonce,
                                               ciphertext: Data(ct),
                                               tag: Data(tag)),
              let out = try? AES.GCM.open(box, using: key, authenticating: aad) else {
            return nil
        }
        return String(data: out, encoding: .utf8)
    }

    private static func attemptV4(route: String,
                                  url: URL,
                                  params: [String: Any],
                                  pin: String,
                                  completion: @escaping (Result<[String: Any], Error>) -> Void) {

        var body = params
        body["pin"] = pin
        body["dev"] = DeviceIdentity.shared.dev
        body["dvi"] = DeviceIdentity.shared.source

        let ts = Int(Date().timeIntervalSince1970)
        var iv = Data(count: 12)
        let rc = iv.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 12, base)
        }
        guard rc == errSecSuccess else { completion(.failure(Failure.crypto)); return }

        let ivHex = iv.hexString
        let canon = canonical(body)
        let msg = AppConfig.v4SigTag + route + "|" + pin + "|" + String(ts) + "|"
                + ivHex + "|" + sha256Hex(canon)
        let sig = hmacSha512Hex(msg)

        let envelope: [String: Any] = [
            "r": route, "p": pin, "t": ts, "n": ivHex, "s": sig, "d": body,
        ]
        guard let plainData = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              let plain = String(data: plainData, encoding: .utf8) else {
            completion(.failure(Failure.badPayload)); return
        }

        let key = HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: masterData),
                                         salt: iv,
                                         info: Data(AppConfig.v4InfoReq.utf8),
                                         outputByteCount: 32)
        let aad = Data((AppConfig.v4AadReq + route + "|" + ivHex).utf8)
        guard let blob = sealBlob(plain, key: key, iv: iv, aad: aad) else {
            completion(.failure(Failure.crypto)); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = blob

        session.dataTask(with: req) { data, _, err in
            if err != nil {
                completion(.failure(Failure.network)); return
            }
            guard let data = data, data.count >= 29 else {
                completion(.failure(Failure.v4Unavailable)); return
            }
            /* 服务端回了明文（JSON）说明这条通道没建立起来 —— 不降级，直接失败 */
            if data.first == 0x7B {
                completion(.failure(Failure.v4Unavailable)); return
            }
            let resIv = data.prefix(12)
            let resKey = HKDF<SHA512>.deriveKey(inputKeyMaterial: SymmetricKey(data: masterData),
                                               salt: Data(resIv),
                                               info: Data(AppConfig.v4InfoRes.utf8),
                                               outputByteCount: 32)
            let resAad = Data((AppConfig.v4AadRes + ivHex).utf8)
            guard let text = openBlob(data, key: resKey, aad: resAad),
                  let objData = text.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: objData)) as? [String: Any] else {
                completion(.failure(Failure.v4Unavailable)); return
            }
            completion(.success(obj))
        }.resume()
    }

    // MARK: - 原语

    static func sha256Hex(_ text: String) -> String {
        let d = SHA256.hash(data: Data(text.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    /// 服务端错误码 → 人话
    static func friendly(_ code: String) -> String {
        switch code.lowercased() {
        case "stale_request":
            return "请求已过期，请检查手机时间是否为「自动设置」后重试"
        case "bad_signature", "bad_cipher", "bad_envelope", "bad_nonce", "bad_v4":
            return "安全校验未通过，请更新到最新版本后重试"
        case "replay":
            return "请求重复提交了，请再点一次"
        case "rate_limited":  return "请求太频繁，稍后再试"
        case "bad_pin":       return "设备码异常，请重装应用"
        case "card_format":   return "卡密格式不对，请检查有没有输错"
        case "card_not_found":return "卡密不存在"
        case "card_revoked":  return "卡密已被封禁"
        case "kicked":        return "设备已被强制下线"
        case "card_expired":  return "卡密已过期"
        case "card_bound":    return "这张卡已绑定其他设备，请联系管理员解绑"
        case "card_used":     return "这张卡密刚被别的设备抢用了"
        case "secure_channel_required":
            return "客户端版本过旧，请更新到最新版本"
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
