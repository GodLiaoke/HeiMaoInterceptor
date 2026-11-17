import Foundation
import CryptoKit

/// 云端规则：凭卡密鉴权下载，AES-256-GCM 解密后只放在内存
///
/// 两层加密：
///   1. 传输层走 v3 加密通道（SecureChannel），抓包只有密文
///   2. 规则包本身再用「设备码 + 卡密 + 当日桶 + 版本」派生的密钥加密
///
/// 线程约定：
///   - 下载完成后的「解密 → 校验 sha256 → 解析规则」全部在 WorkQueue 上跑
///   - 解析结果缓存成 `parsed`，界面和隧道读缓存，不重复 parse
///   - 只有回调碰界面时才切回主线程
final class RuleService {

    static let shared = RuleService()

    /// 规则明文（仅内存）
    private(set) var text: String?
    private(set) var version: String = ""
    private(set) var loadedAt: Date?
    private(set) var counts: (ips: Int, domains: Int) = (0, 0)

    /// 解析结果缓存：界面、隧道、统计都读这一份
    private(set) var parsed: RuleSet?

    /// 解析结果的代号，用来判断缓存是否还新鲜
    private var parsedFingerprint: String = ""

    private var loading = false

    private init() {}

    var isLoaded: Bool { text != nil }

    /// 已解析的规则（没加载时返回空集合，调用方自己判 isEmpty）
    var currentSet: RuleSet { parsed ?? RuleSet() }

    func clear() {
        text = nil
        version = ""
        loadedAt = nil
        counts = (0, 0)
        parsed = nil
        parsedFingerprint = ""
    }

    /// 把一段规则文本喂进来并解析（内存态，不落盘）
    /// - Parameter force: 覆盖已有缓存。热更新时用 true。
    @discardableResult
    func adopt(text str: String, version v: String) -> RuleSet {
        let set = RuleSet.parse(text: str)
        text = str
        version = v
        loadedAt = Date()
        counts = (set.summary.ips, set.domains.count)
        parsed = set
        parsedFingerprint = v
        return set
    }

    /// 拉取规则。已经加载过且非强制时直接返回内存里的那份。
    ///
    /// 注意：`completion` 一定在主线程回调，但里面拿到的字符串
    /// 已经在后台解密校验过，调用方不需要再做重活。
    func load(pin: String, code: String, force: Bool = false,
              completion: @escaping (Result<String, Error>) -> Void) {

        WorkQueue.async { [weak self] in
            guard let self = self else { return }

            let norm = CryptoBox.normaliseCode(code)
            guard !pin.isEmpty, !norm.isEmpty else {
                WorkQueue.main { completion(.failure(LicenseError.invalidCode)) }
                return
            }
            if !force, let cached = self.text {
                WorkQueue.main { completion(.success(cached)) }
                return
            }
            if self.loading {
                WorkQueue.main {
                    completion(.failure(LicenseError.badResponse("规则正在下载，稍等一下")))
                }
                return
            }
            self.loading = true

            self.download(pin: pin, code: norm, completion: completion)
        }
    }

    /// 真正的两段下载 + 后台解密
    private func download(pin: String, code: String,
                          completion: @escaping (Result<String, Error>) -> Void) {

        SecureChannel.post("/rules/manifest",
                           params: ["code": code], pin: pin) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let err):
                WorkQueue.async {
                    self.loading = false
                    WorkQueue.main { completion(.failure(self.translate(err))) }
                }

            case .success(let obj):
                guard (obj["ok"] as? Bool) == true,
                      let version = obj["version"] as? String,
                      let bucket = obj["bucket"] as? String else {
                    let raw = (obj["error"] as? String) ?? ""
                    WorkQueue.async {
                        self.loading = false
                        WorkQueue.main {
                            completion(.failure(LicenseError.badResponse(self.mapError(raw))))
                        }
                    }
                    return
                }
                let wantSha = (obj["sha256"] as? String)?.lowercased() ?? ""

                SecureChannel.post("/rules/download",
                                   params: ["code": code, "version": version],
                                   pin: pin) { r2 in
                    switch r2 {
                    case .failure(let e):
                        WorkQueue.async {
                            self.loading = false
                            WorkQueue.main { completion(.failure(self.translate(e))) }
                        }

                    case .success(let obj2):
                        guard (obj2["ok"] as? Bool) == true,
                              let blobB64 = obj2["blob"] as? String,
                              let blob = Data(base64Encoded: blobB64) else {
                            let raw = (obj2["error"] as? String) ?? ""
                            WorkQueue.async {
                                self.loading = false
                                WorkQueue.main {
                                    completion(.failure(LicenseError.badResponse(self.mapError(raw))))
                                }
                            }
                            return
                        }

                        /* 解密 + 校验 + 解析全在后台队列，主线程一点都不碰 */
                        WorkQueue.async {
                            let key = CryptoBox.deriveRuleKey(pin: pin, code: code,
                                                              bucket: bucket, version: version)
                            guard let plain = try? CryptoBox.openRulePack(blob, key: key),
                                  let str = String(data: plain, encoding: .utf8) else {
                                self.loading = false
                                WorkQueue.main { completion(.failure(LicenseError.crypto)) }
                                return
                            }

                            if !wantSha.isEmpty {
                                let got = SHA256.hash(data: plain)
                                    .map { String(format: "%02x", $0) }.joined()
                                guard got == wantSha else {
                                    self.loading = false
                                    WorkQueue.main { completion(.failure(LicenseError.crypto)) }
                                    return
                                }
                            }

                            let set = self.adopt(text: str, version: version)
                            guard !set.isEmpty else {
                                self.loading = false
                                WorkQueue.main {
                                    completion(.failure(LicenseError.badResponse("云端规则为空")))
                                }
                                return
                            }

                            self.loading = false
                            WorkQueue.main { completion(.success(str)) }
                        }
                    }
                }
            }
        }
    }

    /// 加密通道的错误 → 业务文案
    private func translate(_ err: Error) -> Error {
        if let sec = err as? SecureChannel.Failure {
            switch sec {
            case .network:
                return LicenseError.network
            case .server(let m):
                return LicenseError.badResponse(mapError(m).isEmpty ? m : mapError(m))
            case .signature, .crypto:
                return LicenseError.crypto
            case .badPayload:
                return LicenseError.badResponse("服务器返回异常")
            }
        }
        return err
    }

    private func mapError(_ raw: String) -> String {
        switch raw {
        case "card_expired":   return "卡密已到期，请续费后再下载规则"
        case "card_revoked":   return "卡密已被作废"
        case "card_not_found": return "卡密不存在"
        case "card_bound":     return "这张卡已绑定其他设备，请联系管理员解绑"
        case "card_format":    return "卡密格式不对"
        case "no_rules":       return "云端暂无可用规则"
        case "rate_limited":   return "请求太频繁，稍后再试"
        case "bad_pin":        return "设备码异常，请重装应用"
        case "":               return "规则下载失败，请重试"
        default:               return SecureChannel.friendly(raw)
        }
    }
}
