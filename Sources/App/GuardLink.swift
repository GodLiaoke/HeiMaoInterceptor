import Foundation
import CryptoKit
import HMKit

/// 主程序侧的看门狗链路（1.2.4）
///
/// 与内嵌的 HMKit 形成闭环：
///   - 主程序每秒报心跳；停 6 秒，看门狗判主程序被挂起/被改
///   - 主程序每秒向看门狗要一次挑战签名，用同一算法复算；连续三次对不上就崩
///   - 看门狗那边会读主程序 Mach-O 的 `__TEXT` 段做 SHA-256，
///     和构建期写死的值比对 —— 改一个字节的代码它就知道了
///   - 主程序这边反过来校验：框架是否真的加载、握手是否在走、
///     看门狗对代码段的结论是不是 ok
///
/// 只改一边不成立：
///   删掉框架 → 缺 LC_LOAD_DYLIB，起不来（同时这里会判死）
///   只 patch 主程序 → 看门狗的代码段校验过不了
///   只 patch 框架 → 握手密钥与签名算法对不上
enum GuardLink {

    private static let lock = NSLock()
    private static var started = false
    private static var counter: UInt64 = 0
    private static var key: SymmetricKey?
    private static var lastGuardBeat: UInt64 = 0
    private static var lastGuardMoveAt = Date()
    private static var sawGuardBeat = false
    /// 看门狗报告的「主程序代码段是否完好」
    private static var sealOK = false
    /// 卡密是否已通过看门狗的二次校验
    private static var cardOK = false

    /// 共享密钥：主密钥 + 包名拼出来的，不进明文常量表
    private static var secret: String {
        AppConfig.secureMasterKey + "|wd2|" + AppConfig.appBundleID + "|" + AppConfig.tunnelBundleID
    }

    static func start(breach: @escaping () -> Void) {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        let s = secret

        /* 框架不在 / 结构不对：直接按篡改处理，不等 dyld 去报缺库 */
        guard KitSeal.intact() else {
            started = false
            lock.unlock()
            breach()
            return
        }
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

    /// 授权状态刷新后调用：把卡密交给看门狗，让它用自己的实现再验一遍。
    /// 返回 false 表示这串卡密连格式都过不了，或框架那边的二次校验没通过。
    @discardableResult
    static func verifyCard(_ code: String, pin: String) -> Bool {
        guard started else { return false }
        guard !code.isEmpty else {
            lock.lock(); cardOK = false; lock.unlock()
            return false
        }
        let ok = HMGuard.k4(card: code, pin: pin)
        lock.lock(); cardOK = ok; lock.unlock()
        return ok
    }

    /// 诊断：看门狗对主程序代码段的结论
    static var codeSealOK: Bool {
        lock.lock(); defer { lock.unlock() }
        return sealOK
    }

    static var cardVerified: Bool {
        lock.lock(); defer { lock.unlock() }
        return cardOK
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
            let seal = HMGuard.k5

            lock.lock()
            if beat != lastGuardBeat {
                lastGuardBeat = beat
                lastGuardMoveAt = Date()
                sawGuardBeat = true
            }
            let stalled = sawGuardBeat && Date().timeIntervalSince(lastGuardMoveAt) > 8
            sealOK = seal
            lock.unlock()

            if got.isEmpty || got != expect || stalled || !seal {
                fails += 1
            } else {
                fails = 0
            }

            if fails >= 3 {
                /* 握手断了 / 代码段被换 / 看门狗停摆：直接退场 */
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
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(challenge)|hm-wd-2".utf8), using: k)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
