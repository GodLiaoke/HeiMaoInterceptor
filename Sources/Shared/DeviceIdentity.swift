import Foundation
import CryptoKit
import Security
import Darwin

/// 设备身份（稳定 + 唯一）
///
/// 目标：同一台设备，无论升级、覆盖安装、卸载重装，算出来的设备码永远一样。
///
/// 取源优先级（越靠前越可靠）：
///   1. 钥匙串里已经存下来的设备标识（iOS 卸载 App 不会清钥匙串）
///   2. 老版本留在 UserDefaults 里的设备码 —— 升级用户保持不变，卡密不失效
///   3. MobileGestalt 的真实设备唯一标识（侧载 / 巨魔环境可取，重装与抹机都不变）
///   4. 随机 128 位 + 硬件锚（型号 / 内存 / CPU / 磁盘容量）派生，作为最后兜底
///
/// 设备码（pin）= SHA256(设备标识|hm-pin-v2) 取 8 位十进制，服务端只要 8 位数字。
/// 设备指纹（dev）= SHA256(设备标识|hm-dev-v2) 前 32 位十六进制，
/// 给服务端做「同一台设备换了设备码」的换机校验，不会拿来当卡密。
final class DeviceIdentity {

    static let shared = DeviceIdentity()

    private let keychainService = "com.heimao.interceptor.identity"
    private let kKey  = "device.key.v2"
    private let kPin  = "device.pin.v2"
    private let udKey = "hm.deviceKey.v2"
    private let udPin = "hm.pin.v2"
    private let udLegacyPin = "hm.pin.v1"

    /// 服务端认的 8 位数字设备码
    private(set) var pin: String = ""
    /// 长指纹，随每次请求带给服务端
    private(set) var dev: String = ""
    /// 内部设备标识（不直接外发）
    private(set) var deviceKey: String = ""
    /// 这个设备码是从哪里来的，只用于日志排查
    private(set) var source: String = "unknown"

    private init() {
        bootstrap()
    }

    // MARK: - 初始化

    private func bootstrap() {
        let savedPin = keychainGet(kPin)
        let savedKey = keychainGet(kKey)

        /* 钥匙串完整：直接复用，绝不再算第二遍 */
        if let p = savedPin, isValidPin(p),
           let k = savedKey, !k.isEmpty, !k.hasPrefix("legacy:") {
            pin = p
            deviceKey = k
            dev = Self.devHash(k)
            source = "keychain"
            mirrorToDefaults()
            return
        }

        /* 老版本升级：UserDefaults 里已有设备码 —— 保留它，别让老用户卡密失效 */
        if let legacy = UserDefaults.standard.string(forKey: udLegacyPin), isValidPin(legacy) {
            let key = "legacy:" + legacy
            pin = legacy
            deviceKey = key
            dev = Self.devHash(key)
            source = "legacy"
            keychainSet(kKey, key)
            keychainSet(kPin, legacy)
            mirrorToDefaults()
            return
        }

        /* 已经算过一次（钥匙串不可用时靠这里兜底） */
        if let k = UserDefaults.standard.string(forKey: udKey), !k.isEmpty,
           let p = UserDefaults.standard.string(forKey: udPin), isValidPin(p) {
            pin = p
            deviceKey = k
            dev = Self.devHash(k)
            source = "defaults"
            keychainSet(kKey, k)
            keychainSet(kPin, p)
            return
        }

        /* 全新安装：用真实设备标识（拿不到就随机 + 硬件锚） */
        let key: String
        if let udid = Self.mobileGestalt("UniqueDeviceID"), udid.count >= 8 {
            key = "udid:" + udid.lowercased()
            source = "udid"
        } else {
            key = "rand:" + UUID().uuidString.lowercased() + "|" + Self.hardwareAnchor()
            source = "random"
        }
        deviceKey = key
        pin = Self.pin(from: key)
        dev = Self.devHash(key)
        keychainSet(kKey, key)
        keychainSet(kPin, pin)
        mirrorToDefaults()
    }

    private func mirrorToDefaults() {
        UserDefaults.standard.set(pin, forKey: udPin)
        UserDefaults.standard.set(deviceKey, forKey: udKey)
    }

    // MARK: - 派生

    static func pin(from key: String) -> String {
        let digest = SHA256.hash(data: Data(("hm-pin-v2|" + key).utf8))
        var n: UInt64 = 0
        for b in digest.prefix(8) {
            n = (n << 8) | UInt64(b)
        }
        return String(format: "%08llu", n % 100_000_000)
    }

    static func devHash(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(("hm-dev-v2|" + key).utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func isValidPin(_ p: String) -> Bool {
        p.count == AppConfig.pinLength && p.allSatisfy { $0.isNumber }
    }

    // MARK: - 设备信息

    /// MobileGestalt 的真实设备唯一标识
    /// 侧载 / 巨魔环境可用；App Store 环境拿不到时返回 nil，自动走下一级兜底
    static func mobileGestalt(_ key: String) -> String? {
        guard let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "MGCopyAnswer") else { return nil }
        typealias Func = @convention(c) (CFString) -> Unmanaged<CFString>?
        let fn = unsafeBitCast(sym, to: Func.self)
        guard let raw = fn(key as CFString) else { return nil }
        let value = raw.takeRetainedValue() as String
        return value.isEmpty ? nil : value
    }

    /// 硬件锚：同一台设备重装后不变；同型号同配置的机器会相同，
    /// 所以只在拿不到真实唯一标识时用，且必须配合钥匙串保证唯一。
    static func hardwareAnchor() -> String {
        var parts: [String] = []
        parts.append(sysctlString("hw.machine") ?? "unknown")
        parts.append(sysctlString("hw.model") ?? "unknown")
        parts.append(String(ProcessInfo.processInfo.physicalMemory))
        parts.append(String(ProcessInfo.processInfo.processorCount))

        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let size = attrs[.systemSize] as? NSNumber {
            parts.append(String(size.int64Value))
        }

        let material = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    // MARK: - 钥匙串

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    private func keychainGet(_ account: String) -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8),
              !s.isEmpty else {
            return nil
        }
        return s
    }

    private func keychainSet(_ account: String, _ value: String) {
        let q = baseQuery(account)
        SecItemDelete(q as CFDictionary)

        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false

        let st = SecItemAdd(add as CFDictionary, nil)
        if st != errSecSuccess {
            /* 伪签名环境偶尔拿不到钥匙串权限：不崩，退回 UserDefaults */
            source += "+kc\(st)"
        }
    }
}
