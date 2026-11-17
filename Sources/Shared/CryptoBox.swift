import Foundation
import CryptoKit

/// 云端配置包解密 + 签名工具
/// 设计目标：规则与「解密密钥」都不进安装包，
/// 只有卡密校验通过、服务端下发信封后，本地才能用「卡密 + 设备码」派生密钥解开。
enum CryptoBox {

    /// key = SHA256(configSalt | pin | code | kid)
    /// 服务端按同公式生成，客户端不保存任何明文密钥。
    static func deriveKey(pin: String, code: String, kid: String) -> SymmetricKey {
        let material = "\(AppConfig.configSalt)|\(pin)|\(code.uppercased())|\(kid)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return SymmetricKey(data: Data(digest))
    }

    /// AES-256-GCM 解密
    static func open(envelope: RemoteConfigEnvelope, pin: String, code: String) throws -> Data {
        guard let ivData = Data(base64Encoded: envelope.iv),
              let ctData = Data(base64Encoded: envelope.ct) else {
            throw LicenseError.crypto
        }
        let key = deriveKey(pin: pin, code: code, kid: envelope.kid)
        do {
            let nonce = try AES.GCM.Nonce(data: ivData)
            let box = try AES.GCM.SealedBox(nonce: nonce,
                                            ciphertext: Data(ctData.dropLast(16)),
                                            tag: Data(ctData.suffix(16)))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw LicenseError.crypto
        }
    }

    static func decodePayload(_ data: Data) throws -> RemoteConfigPayload {
        do {
            return try JSONDecoder().decode(RemoteConfigPayload.self, from: data)
        } catch {
            throw LicenseError.crypto
        }
    }

    /// 规则文本指纹，UI 显示 / 防篡改对比
    static func fingerprint(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(12).uppercased()
    }


    // MARK: - 云端规则包（AES-256-GCM / HKDF-SHA256）

    /// 规范化卡密：去符号 → 大写 → 四位一组（必须与服务端一致）
    static func normaliseCode(_ raw: String) -> String {
        let upper = raw.uppercased().filter { ch in
            (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9")
        }
        guard upper.count == 16 else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        var parts: [String] = []
        var idx = upper.startIndex
        for _ in 0..<4 {
            let end = upper.index(idx, offsetBy: 4)
            parts.append(String(upper[idx..<end]))
            idx = end
        }
        return parts.joined(separator: "-")
    }

    /// 规则密钥：SHA256(pin|卡密|当日桶|规则版本) → HKDF-SHA256
    static func deriveRuleKey(pin: String, code: String, bucket: String, version: String) -> SymmetricKey {
        let material = "\(pin)|\(code)|\(bucket)|\(version)"
        let ikm = SHA256.hash(data: Data(material.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(ikm)),
            salt: Data(AppConfig.rulesSalt.utf8),
            info: Data(AppConfig.rulesInfo.utf8),
            outputByteCount: 32
        )
    }

    /// 规则包结构：HMR1 + nonce(12) + 密文 + tag(16)
    static func openRulePack(_ blob: Data, key: SymmetricKey) throws -> Data {
        guard blob.count > 32, blob.prefix(4) == Data("HMR1".utf8) else {
            throw LicenseError.crypto
        }
        do {
            let box = try AES.GCM.SealedBox(combined: blob.subdata(in: 4..<blob.count))
            return try AES.GCM.open(box, using: key)
        } catch {
            throw LicenseError.crypto
        }
    }

    static func hmac(_ text: String, key: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(text.utf8),
                                                  using: SymmetricKey(data: Data(key.utf8)))
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
