import Foundation
import CryptoKit

/// 云端规则：凭卡密鉴权下载，AES-256-GCM 解密后只放在内存
///
/// 不落盘：规则明文只存在于本进程内存，退出即消失。
/// 密钥：SHA256(pin|卡密|当日桶|规则版本) → HKDF-SHA256，服务端每天 UTC 0 点轮换。
final class RuleService {

    static let shared = RuleService()

    private let session: URLSession

    /// 规则明文（仅内存）
    private(set) var text: String?
    private(set) var version: String = ""
    private(set) var loadedAt: Date?
    private(set) var counts: (ips: Int, domains: Int) = (0, 0)

    private var loading = false

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 45
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "application/json",
                                     "User-Agent": "HeiMaoInterceptor/\(AppConfig.appVersion) (iOS)"]
        session = URLSession(configuration: cfg)
    }

    var isLoaded: Bool { text != nil }

    func clear() {
        text = nil
        version = ""
        loadedAt = nil
        counts = (0, 0)
    }

    /// 拉取规则。已经加载过且非强制时直接返回内存里的那份。
    func load(pin: String, code: String, force: Bool = false,
              completion: @escaping (Result<String, Error>) -> Void) {

        let norm = CryptoBox.normaliseCode(code)
        guard !pin.isEmpty, !norm.isEmpty else {
            completion(.failure(LicenseError.invalidCode)); return
        }
        if !force, let cached = text {
            completion(.success(cached)); return
        }
        if loading {
            completion(.failure(LicenseError.badResponse("规则正在下载，稍等一下"))); return
        }
        loading = true

        post("/rules/manifest", body: ["pin": pin, "code": norm]) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let err):
                self.loading = false
                completion(.failure(err))

            case .success(let data):
                guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.loading = false
                    completion(.failure(LicenseError.badResponse("服务器返回异常")))
                    return
                }
                guard (obj["ok"] as? Bool) == true,
                      let version = obj["version"] as? String,
                      let bucket = obj["bucket"] as? String else {
                    self.loading = false
                    let raw = (obj["error"] as? String) ?? ""
                    completion(.failure(LicenseError.badResponse(self.mapError(raw))))
                    return
                }
                let wantSha = (obj["sha256"] as? String)?.lowercased() ?? ""

                self.post("/rules/download",
                          body: ["pin": pin, "code": norm, "version": version]) { r2 in

                    guard case .success(let blob) = r2 else {
                        self.loading = false
                        if case .failure(let e) = r2 { completion(.failure(e)) }
                        return
                    }

                    let key = CryptoBox.deriveRuleKey(pin: pin, code: norm,
                                                      bucket: bucket, version: version)
                    guard let plain = try? CryptoBox.openRulePack(blob, key: key),
                          let str = String(data: plain, encoding: .utf8) else {
                        self.loading = false
                        completion(.failure(LicenseError.crypto))
                        return
                    }

                    if !wantSha.isEmpty {
                        let got = SHA256.hash(data: plain)
                            .map { String(format: "%02x", $0) }.joined()
                        guard got == wantSha else {
                            self.loading = false
                            completion(.failure(LicenseError.crypto))
                            return
                        }
                    }

                    let set = RuleSet.parse(text: str)
                    guard !set.isEmpty else {
                        self.loading = false
                        completion(.failure(LicenseError.badResponse("云端规则为空")))
                        return
                    }

                    self.text = str
                    self.version = version
                    self.loadedAt = Date()
                    self.counts = (set.ipRanges.count, set.domains.count)
                    self.loading = false

                    DispatchQueue.main.async {
                        completion(.success(str))
                    }
                }
            }
        }
    }

    // MARK: - 网络

    private func post(_ path: String, body: [String: Any],
                      completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: AppConfig.apiBase + path) else {
            completion(.failure(LicenseError.network)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: req) { data, resp, err in
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                if let data = data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let raw = obj["error"] as? String {
                    completion(.failure(LicenseError.badResponse(self.mapError(raw))))
                } else {
                    completion(.failure(LicenseError.badResponse("服务端错误 \(http.statusCode)")))
                }
                return
            }
            guard let data = data else {
                completion(.failure(err ?? LicenseError.network)); return
            }
            completion(.success(data))
        }.resume()
    }

    private func mapError(_ raw: String) -> String {
        switch raw {
        case "card_expired":  return "卡密已到期，请续费后再下载规则"
        case "card_revoked":  return "卡密已被作废"
        case "card_not_found": return "卡密不存在"
        case "card_bound":    return "这张卡已绑定其他设备，请联系管理员解绑"
        case "card_format":   return "卡密格式不对"
        case "no_rules":      return "云端暂无可用规则"
        case "rate_limited":  return "请求太频繁，稍后再试"
        case "bad_pin":       return "设备码异常，请重装应用"
        case "":              return "规则下载失败，请重试"
        default:              return "规则下载失败：\(raw)"
        }
    }
}
