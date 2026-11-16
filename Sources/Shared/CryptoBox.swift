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

    static func hmac(_ text: String, key: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(text.utf8),
                                                  using: SymmetricKey(data: Data(key.utf8)))
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
