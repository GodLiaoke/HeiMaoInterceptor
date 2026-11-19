import Foundation
import Darwin
import MachO

/// 运行环境自检
///
/// 只做「发现异常 + 如实上报」，不拦用户使用：
/// 自签 / 巨魔重签本来就会改写二进制，任何对签名字节的硬校验都会误伤正常用户，
/// 这里查的是三类真正代表篡改的迹象：
///   1. 进程里多出不属于系统和本 App 的镜像（注入的 dylib）
///   2. 被调试器附着（有人在动态分析）
///   3. 包结构被改（bundle id / 版本号 / 隧道扩展被动过）
///
/// 结论通过 `code` 带给服务端做风控参考；本地只用于决定「这份授权要不要落地」。
final class Integrity {

    static let shared = Integrity()

    private(set) var injected: [String] = []
    private(set) var debugged = false
    private(set) var bundleAltered = false

    /* 1.2.0：CRC 链校验状态。crc 异常只上报、不拦用户（自签/重签环境本来就改包） */
    private var chainBroken = false
    private var sealChecked = false
    private var stagesSeen = Set<Int>()
    private let chainLock = NSLock()

    private var evaluated = false
    private let lock = NSLock()

    private init() {}

    /// ok / inj / dbg / bed
    var code: String {
        evaluate()
        lock.lock(); defer { lock.unlock() }
        if !injected.isEmpty { return "inj" }
        if debugged { return "dbg" }
        if !sealChecked { _ = sealFoldCheck() }
        if chainBroken { return "crc" }
        if bundleAltered { return "bed" }
        return "ok"
    }

    /// 本地是否值得信任
    ///
    /// 只看调试器：被动态附加时不把授权写盘，避免被直接 dump。
    /// 注入的库只上报不降级 —— 巨魔用户常装插件，不能因此让人家每次冷启动都要重新联网。
    var trustedLocally: Bool {
        evaluate()
        _ = arm(9)
        lock.lock(); defer { lock.unlock() }
        chainLock.lock(); defer { chainLock.unlock() }
        return !debugged && !chainBroken
    }

    func evaluate() {
        lock.lock()
        if evaluated { lock.unlock(); return }
        lock.unlock()

        let images = foreignImages()
        let traced = isTraced()
        let intact = bundleIntact()

        lock.lock()
        injected = images
        debugged = traced
        bundleAltered = !intact
        evaluated = true
        lock.unlock()
    }

    // MARK: - CRC 环环校验（1.2.0）
    //
    // 构建期把每个源文件的 CRC32 写进 IntegritySeal，运行时按层校验：
    //   arm(stage) -> checkA() -> checkB() -> checkC()
    // 每一层都依赖下一层的返回值，任意一层被改动/跳过，链就断。
    // 结果只用于上报和「本地是否值得信任」，不改用户能不能用。

    /// 逐字节 CRC32（与构建脚本 Tools/gen_crc.py 完全一致）
    @inline(never)
    private func crc32(_ seed: UInt32, _ bytes: [UInt32]) -> UInt32 {
        var c = seed ^ 0xFFFF_FFFF
        for v in bytes {
            var x = v
            var i = 0
            while i < 4 {
                c ^= (x & 0xFF)
                var k = 0
                while k < 8 {
                    c = (c & 1) == 1 ? ((c >> 1) ^ 0xEDB8_8320) : (c >> 1)
                    k += 1
                }
                x >>= 8
                i += 1
            }
        }
        return c ^ 0xFFFF_FFFF
    }

    @inline(never)
    private func sealFold() -> UInt32 {
        var acc: UInt32 = 0x811C_9DC5
        for (i, v) in IntegritySeal.parts.enumerated() {
            acc = crc32(acc &+ UInt32(truncatingIfNeeded: i &* 2654435761), [v])
        }
        return acc
    }

    @inline(never)
    private func tokenOk(_ index: Int) -> Bool {
        let parts = IntegritySeal.parts
        guard !parts.isEmpty else { return false }
        let v = parts[index % parts.count]
        let mix = (v &* 2654435761) ^ UInt32(truncatingIfNeeded: index)
        return (mix & 0xFFFF) == IntegritySeal.tokens[index % IntegritySeal.tokens.count]
    }

    @inline(never)
    private func checkC() -> Bool {
        return IntegritySeal.parts.count == IntegritySeal.count && tokenOk(0) && tokenOk(1)
    }

    @inline(never)
    private func checkB(_ a: Bool) -> Bool {
        return a && checkC() && tokenOk(2)
    }

    @inline(never)
    private func checkA() -> Bool {
        return sealFold() == IntegritySeal.digest
    }

    /// 关键函数入口调用这个：任何一环对不上，链就断
    @discardableResult
    @inline(never)
    func arm(_ stage: Int) -> Bool {
        chainLock.lock(); defer { chainLock.unlock() }
        let ok = checkB(checkA())
        if !ok { chainBroken = true }
        stagesSeen.insert(stage)
        sealChecked = true
        return ok
    }

    @inline(never)
    private func sealFoldCheck() -> Bool {
        let ok = checkB(checkA())
        chainLock.lock()
        chainBroken = chainBroken || !ok
        sealChecked = true
        chainLock.unlock()
        return ok
    }

    /// 链完整度（诊断上报用）
    var chain: String {
        chainLock.lock(); defer { chainLock.unlock() }
        if chainBroken { return "crc" }
        return stagesSeen.count >= 3 ? "ok" : "p\(stagesSeen.count)"
    }

    // MARK: - 注入

    private func foreignImages() -> [String] {
        var list: [String] = []
        let own = Bundle.main.bundlePath
        let total = _dyld_image_count()
        var i: UInt32 = 0
        while i < total {
            defer { i += 1 }
            guard let raw = _dyld_get_image_name(i) else { continue }
            let path = String(cString: raw)
            if path.isEmpty { continue }
            if path.hasPrefix("/System/") { continue }
            if path.hasPrefix("/usr/lib/") { continue }
            if path.hasPrefix(own) { continue }
            list.append((path as NSString).lastPathComponent)
        }
        return list
    }

    // MARK: - 调试

    private func isTraced() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - 包结构

    private func bundleIntact() -> Bool {
        let bundle = Bundle.main
        guard bundle.bundleIdentifier == AppConfig.appBundleID else { return false }

        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard short == AppConfig.appVersion,
              build == String(AppConfig.buildNumber) else { return false }

        /* 隧道扩展被删掉 / 换掉，App 会装得上但一开就失败，
           这种改包在授权这一层就先记下来 */
        let appex = bundle.bundleURL
            .appendingPathComponent("PlugIns")
            .appendingPathComponent("HeiMaoTunnel.appex")
        guard FileManager.default.fileExists(atPath: appex.path) else { return false }

        return true
    }
}
