import Foundation
import CryptoKit
import HMKit

/// 主程序侧的看门狗链路（1.2.3）
///
/// 和内置的动态库互相盯着：
///   - 主程序每秒报心跳；停 6 秒，看门狗判主程序被挂起/被改
///   - 主程序每秒向看门狗要一次挑战签名，用同一算法复算；连续三次对不上就崩
///   - 看门狗自己的心跳不走，主程序同样判它被拔掉
///
/// 这样只改一边都不成立：删掉 dylib 主程序起不来（缺 LC_LOAD_DYLIB），
/// 只 patch 主程序里的校验，看门狗那边还在要应答。
enum GuardLink {

    private static let lock = NSLock()
    private static var started = false
    private static var counter: UInt64 = 0
    private static var key: SymmetricKey?
    private static var lastGuardBeat: UInt64 = 0
    private static var lastGuardMoveAt = Date()
    /// 是否见过看门狗心跳。没见到过就不按「停摆」判死 ——
    /// 真被拔掉的情况主程序根本起不来（缺 LC_LOAD_DYLIB），不需要靠误判兜底。
    private static var sawGuardBeat = false

    /// 共享密钥：主密钥 + 包名拼出来的，不进明文常量表
    private static var secret: String {
        AppConfig.secureMasterKey + "|wd1|" + AppConfig.appBundleID + "|" + AppConfig.tunnelBundleID
    }

    static func start(breach: @escaping () -> Void) {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        let s = secret
        key = SymmetricKey(data: Data(SHA256.hash(data: Data(s.utf8))))
        lastGuardBeat = 0
        lastGuardMoveAt = Date()
        lock.unlock()

        HMGuard.k0(secret: s,
                   responder: { challenge in sign(challenge) },
                   breach: breach)

        lastGuardBeat = HMGuard.k2

        let thread = Thread { loop(breach) }
        thread.name = "hm.link"
        thread.qualityOfService = .userInitiated
        thread.stackSize = 128 * 1024
        thread.start()
    }

    // MARK: - 内部

    private static func loop(_ breach: @escaping () -> Void) {
        var fails = 0
        while true {
            Thread.sleep(forTimeInterval: 1.0)

            lock.lock()
            counter &+= 1
            let c = counter
            let k = key
            lock.unlock()

            HMGuard.k1(c)

            let challenge = UInt32.random(in: 1...UInt32.max)
            let expect = sign(challenge, key: k)
            let got = HMGuard.k3(challenge)
            let beat = HMGuard.k2

            lock.lock()
            if beat != lastGuardBeat {
                lastGuardBeat = beat
                lastGuardMoveAt = Date()
                sawGuardBeat = true
            }
            let stalled = sawGuardBeat && Date().timeIntervalSince(lastGuardMoveAt) > 6
            lock.unlock()

            if got.isEmpty || got != expect || stalled {
                fails += 1
            } else {
                fails = 0
            }

            if fails >= 3 {
                breach()
                return
            }
        }
    }

    /// 与 dylib 内 `signInternal` 逐字一致（挑战 + 固定标签，用派生密钥做 HMAC-SHA256）
    private static func sign(_ challenge: UInt32, key: SymmetricKey? = nil) -> String {
        lock.lock()
        let k = key ?? self.key
        lock.unlock()
        guard let k = k else { return "" }
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(challenge)|hm-wd-1".utf8), using: k)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
