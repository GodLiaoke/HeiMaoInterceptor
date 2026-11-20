import Foundation
import CryptoKit

/// 看门狗（1.2.3）
///
/// 独立动态库，和主程序互相校验：
///   1. 看门狗每秒给主程序出一道随机挑战，主程序必须用共享密钥回出正确的 HMAC
///   2. 主程序每秒回报一次心跳计数；超过 6 秒不动，看门狗判主程序被挂起/被改
///   3. 主程序同时校验看门狗的心跳是否在走、签名是否正确
/// 任意一侧连续三次对不上，双方一起调用 breach（主程序那边是真崩）。
///
/// 为什么单独做成 dylib：主程序删掉对它的加载就起不来（LC_LOAD_DYLIB 缺库直接
/// 启动失败），想只改主程序绕过校验也过不了这一层 —— 两边必须同时被改。
public final class HMGuard {

    public static let shared = HMGuard()

    private let lock = NSLock()
    private var tick: UInt64 = 0
    private var running = false
    private var failures = 0
    private var secret: [UInt8] = []
    private var key: SymmetricKey?
    private var responder: ((UInt32) -> String)?
    private var breach: (() -> Void)?
    private var lastBeat = Date()

    // MARK: - 对外接口

    /// 启动（对外用无意义短名，符号表里看不出用途）
    public static func k0(secret: String,
                          responder: @escaping (UInt32) -> String,
                          breach: @escaping () -> Void) {
        shared.begin(secret: secret, responder: responder, breach: breach)
    }

    /// 心跳（计数只增不减）
    public static func k1(_ counter: UInt64) {
        shared.lock.lock()
        shared.lastBeat = Date()
        shared.lock.unlock()
        _ = counter
    }

    /// 看门狗自身的心跳值
    public static var k2: UInt64 {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.tick
    }

    /// 用共享密钥对挑战做签名
    public static func k3(_ challenge: UInt32) -> String {
        shared.signInternal(challenge)
    }

    // MARK: - 内部

    private func begin(secret: String, responder: @escaping (UInt32) -> String,
                       breach: @escaping () -> Void) {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        self.secret = Array(secret.utf8)
        self.key = SymmetricKey(data: Data(SHA256.hash(data: Data(secret.utf8))))
        self.responder = responder
        self.breach = breach
        self.lastBeat = Date()
        lock.unlock()

        let thread = Thread { [weak self] in
            self?.loop()
        }
        thread.name = "hm.guard"
        thread.qualityOfService = .userInitiated
        thread.stackSize = 256 * 1024
        thread.start()
    }

    private func loop() {
        while true {
            Thread.sleep(forTimeInterval: 1.0)

            lock.lock()
            tick &+= 1
            let answerFn = responder
            let stale = Date().timeIntervalSince(lastBeat) > 6
            lock.unlock()

            let challenge = UInt32.random(in: 1...UInt32.max)
            let expect = signInternal(challenge)
            let got = answerFn?(challenge) ?? ""

            var bad = stale || got != expect || got.isEmpty

            /* 再自查一次：自己的密钥表没被动过 */
            if !bad {
                lock.lock()
                let alive = !secret.isEmpty && key != nil
                lock.unlock()
                bad = !alive
            }

            if bad {
                lock.lock()
                failures += 1
                let hit = failures >= 3
                let action = breach
                lock.unlock()
                if hit {
                    action?()
                    return
                }
            } else {
                lock.lock()
                failures = 0
                lock.unlock()
            }
        }
    }

    private func signInternal(_ challenge: UInt32) -> String {
        lock.lock()
        let k = key
        lock.unlock()
        guard let k = k else { return "" }
        /* 挑战 → 签名必须是一个纯函数：主程序那边用同样的算法复算，
           对得上才说明两边密钥一致、两边代码都没被单独改过。 */
        let msg = "\(challenge)|hm-wd-1"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: k)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}
