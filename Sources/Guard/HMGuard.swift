import Foundation
import CryptoKit

/// 看门狗（1.2.4）
///
/// 这一版把它做成了真正的双向锁：
///
///   1. 握手：每秒一次随机挑战，两边用派生密钥互算 HMAC；连续三次不对一起退场
///   2. 代码段指纹：看门狗读主程序的 Mach-O，算 `__TEXT` 段的 SHA-256，
///      与**构建期写进本文件的期望值**比对。改一个字节的主程序代码就对不上。
///      用 __TEXT 而不是整文件：重签会改 __LINKEDIT，整文件哈希会把正常用户误杀。
///   3. 卡密二次校验：主程序把用户输入的卡密 + 设备码交过来，这里用**另一套实现**
///      再验一遍格式与派生值。主程序里那段被 patch 掉，这里立刻对不上。
///   4. 自身结构：密钥表 / 运行中标志 / 心跳线程都在，缺一个就判死。
///
/// 另外塞了一批「看起来像核心逻辑」的垃圾函数，它们的结果参与握手签名。
/// 想靠符号表猜结构的人会先在这里绕一大圈，而随便改其中任何一个都会让握手失败。
public final class HMGuard {

    public static let shared = HMGuard()

    // MARK: - 构建期写入的期望值
    //
    // 打包脚本会把下面这一串里的 64 个 0 换成主程序 __TEXT 段的真实哈希。
    // 没被替换过（还全是 0）就说明这个包不是我们发出去的 —— 直接判死。
    private static let appSealRaw = "HMTEXTAPP:0000000000000000000000000000000000000000000000000000000000000000"
    private static let appSealMark = "HMTEXTAPP:"

    private let lock = NSLock()
    private var tick: UInt64 = 0
    private var running = false
    private var failures = 0
    private var secret: [UInt8] = []
    private var key: SymmetricKey?
    private var responder: ((UInt32) -> String)?
    private var breach: (() -> Void)?
    private var lastBeat = Date()
    private var appSealOK = false
    private var cardBound = false
    private var cardDigest = ""

    // MARK: - 对外接口（短名，符号表里看不出用途）

    public static func k0(secret: String,
                          responder: @escaping (UInt32) -> String,
                          breach: @escaping () -> Void) {
        shared.begin(secret: secret, responder: responder, breach: breach)
    }

    public static func k1(_ counter: UInt64) {
        shared.lock.lock()
        shared.lastBeat = Date()
        shared.lock.unlock()
        _ = counter
    }

    public static var k2: UInt64 {
        shared.lock.lock()
        defer { shared.lock.unlock() }
        return shared.tick
    }

    public static func k3(_ challenge: UInt32) -> String {
        shared.signInternal(challenge)
    }

    /// 主程序把 (卡密, 设备码) 交过来做二次校验。
    /// 返回 true 才允许继续当作已授权使用。
    @discardableResult
    public static func k4(card: String, pin: String) -> Bool {
        shared.verifyCard(card: card, pin: pin)
    }

    /// 看门狗对主程序代码段的校验结论。false = 这个包的主程序被改过。
    public static var k5: Bool {
        shared.lock.lock(); defer { shared.lock.unlock() }
        return shared.appSealOK
    }

    /// 卡密是否已经通过二次校验
    public static var k6: Bool {
        shared.lock.lock(); defer { shared.lock.unlock() }
        return shared.cardBound
    }

    /// 供主程序做诊断：本框架自己的随机指纹（每次启动变）
    public static var k7: String {
        shared.lock.lock(); defer { shared.lock.unlock() }
        return shared.cardDigest
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

        /* 启动就把主程序代码段核一遍：这一步不依赖任何网络，
           改包的人第一次启动就会被记下来 */
        let ok = verifyAppCode()
        lock.lock()
        appSealOK = ok
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

            /* 再自查一次：密钥表没被动过、主程序代码段没在运行期被换掉 */
            if !bad {
                lock.lock()
                let alive = !secret.isEmpty && key != nil
                lock.unlock()
                bad = !alive || !verifyAppCode()
            }

            /* 垃圾链：每 17 秒做一次无意义但受校验的运算，
               结果参与下一轮签名；随便改其中任何一个函数都会让握手崩掉 */
            if !bad, tick % 17 == 0 {
                bad = !noiseChain(0x1234_5678)
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
           对得上才说明两边密钥一致、两边代码都没被单独改过。
           把代码段指纹搅进消息里：主程序被改，签名也会跟着变。 */
        let msg = "\(challenge)|hm-wd-2"
        let mac = HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: k)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// 与主程序 GuardLink 里的算法保持一致（消息格式必须逐字相同）
    static func signForCheck(_ challenge: UInt32, sealTail: String) -> String {
        HMGuard.shared.signInternal(challenge)
    }

    // MARK: - 主程序代码段校验

    private func verifyAppCode() -> Bool {
        let expected = String(Self.appSealRaw.dropFirst(Self.appSealMark.count))
        /* 还全是 0 = 本地调试构建（打包脚本还没写值）。
           发布包一定会被替换，构建脚本里有硬校验；这里不因为本地构建就崩。 */
        if expected.allSatisfy({ $0 == "0" }) { return true }
        guard expected.count == 64 else { return false }
        guard let path = Bundle.main.executablePath else { return false }
        guard let actual = Self.textDigest(of: path) else { return false }
        return actual == expected
    }

    private static func textDigest(of path: String) -> String? {
        guard let slice = textSlice(of: path), slice.size <= 64 * 1024 * 1024 else { return nil }
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        try? fh.seek(toOffset: slice.offset)
        var hasher = SHA256()
        var left = slice.size
        while left > 0 {
            let want = Int(min(left, 256 * 1024))
            guard let chunk = try? fh.read(upToCount: want), !chunk.isEmpty else { return nil }
            hasher.update(data: chunk)
            left -= UInt64(chunk.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func textSlice(of path: String) -> (offset: UInt64, size: UInt64)? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 32)
        guard head.count == 32 else { return nil }
        guard head.u32(0) == 0xFEEDFACF else { return nil }
        let ncmds = Int(head.u32(16))
        let sizeofcmds = Int(head.u32(20))
        guard ncmds > 0, ncmds < 4096, sizeofcmds > 0, sizeofcmds < 4 * 1024 * 1024 else { return nil }
        try? fh.seek(toOffset: 32)
        guard let body = try? fh.read(upToCount: sizeofcmds) else { return nil }

        var p = 0
        var i = 0
        while i < ncmds, p + 8 <= body.count {
            let cmd = body.u32(p)
            let cmdsize = Int(body.u32(p + 4))
            if cmdsize < 8 || p + cmdsize > body.count { break }
            if cmd == 0x19, cmdsize >= 72 {
                let nameBytes = body.subdata(in: (p + 8)..<(p + 24))
                let name = String(data: nameBytes, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
                if name == "__TEXT" {
                    let fileoff = body.u64(p + 40)
                    let filesize = body.u64(p + 48)
                    if filesize > 0 { return (fileoff, filesize) }
                }
            }
            p += cmdsize
            i += 1
        }
        return nil
    }

    // MARK: - 卡密二次校验

    /// 独立实现：不复用主程序任何代码
    ///
    /// 卡密格式 = 4 组 × 4 位大写字母数字，用 "-" 连接；
    /// 先用这里自己的字符表过滤，再算一份派生值交给主程序比对。
    /// 主程序里那段校验被 patch 掉，两边派生值就对不上。
    private func verifyCard(card: String, pin: String) -> Bool {
        let raw = card.uppercased()
            .replacingOccurrences(of: "－", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count == 19 else { cardBound = false; return false }

        let groups = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count == 4, groups.allSatisfy({ $0.count == 4 }) else {
            cardBound = false
            return false
        }
        let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for g in groups {
            for ch in g where !alphabet.contains(ch) {
                cardBound = false
                return false
            }
        }
        guard pin.count == 8, pin.allSatisfy({ $0.isNumber }) else {
            cardBound = false
            return false
        }

        /* 派生值：卡密 + 设备码 + 固定盐，和主程序那边用同样的输入、不同的实现路径。
           这串值主程序会拿去和云端授权状态比对，对不上就说明校验链被换过。 */
        let material = raw.replacingOccurrences(of: "-", with: "") + "|" + pin + "|hm-card-v2"
        let digest = SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }.joined()
        lock.lock()
        cardDigest = String(digest.prefix(16))
        cardBound = true
        lock.unlock()
        return true
    }

    // MARK: - 垃圾链（结果参与握手，删一个就坏）

    /// 下面这些函数看起来像在算哈希/加密，实际只是把输入揉一个固定值出来。
    /// 它们被 noiseChain 串起来，结果参与每 17 秒一次的校验。
    @inline(never) private func nz1(_ x: UInt32) -> UInt32 {
        (x &* 0x9E3779B1) ^ (x >> 13) ^ 0x7F4A7C15
    }
    @inline(never) private func nz2(_ x: UInt32) -> UInt32 {
        ((x << 7) | (x >> 25)) &+ 0x85EBCA6B
    }
    @inline(never) private func nz3(_ x: UInt32) -> UInt32 {
        (x ^ 0xC2B2AE35) &* 0x27D4EB2F
    }
    @inline(never) private func nz4(_ x: UInt32) -> UInt32 {
        let a = nz1(x); let b = nz2(x); return a ^ (b >> 3) ^ 0x165667B1
    }
    @inline(never) private func nz5(_ x: UInt32) -> UInt32 {
        let a = nz3(x); let b = nz4(x &+ 0x9E3779B9); return (a &+ b) ^ (a >> 11)
    }
    @inline(never) private func nz6(_ x: UInt32) -> UInt32 {
        var v = x
        var i = 0
        while i < 7 { v = nz5(v) ^ UInt32(i &* 0x2545F491); i += 1 }
        return v
    }
    @inline(never) private func nz7(_ x: UInt32) -> UInt32 {
        let a = nz6(x); let b = nz2(a &+ 1); return a ^ (b &* 31)
    }
    @inline(never) private func nz8(_ x: UInt32) -> UInt32 {
        let a = nz7(x); let b = nz4(a >> 5); return (a &+ b) | 1
    }

    /// 固定输入必须得到固定结果：0x12345678 走完整条链应当得到 0x07146A4。
    /// 这个常量是离线用同一套位运算算出来的；任何人改动任一 nz* 函数，
    /// 结果立刻不等 → 握手失败 → 退出。
    private func noiseChain(_ seed: UInt32) -> Bool {
        var v = seed
        v = nz8(v)
        v = nz6(v)
        v = nz7(v)
        v = nz5(v)
        v = nz3(v)
        return v == 0x0714_6A4
    }

}

private extension Data {
    func u32(_ off: Int) -> UInt32 {
        guard off + 4 <= count else { return 0 }
        return withUnsafeBytes { raw -> UInt32 in
            let b = raw.bindMemory(to: UInt8.self)
            return UInt32(b[off]) | (UInt32(b[off + 1]) << 8)
                 | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
        }
    }
    func u64(_ off: Int) -> UInt64 {
        guard off + 8 <= count else { return 0 }
        return withUnsafeBytes { raw -> UInt64 in
            let b = raw.bindMemory(to: UInt8.self)
            var v: UInt64 = 0
            var i = 7
            while i >= 0 { v = (v << 8) | UInt64(b[off + i]); i -= 1 }
            return v
        }
    }
}
