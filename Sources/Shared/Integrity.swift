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

    private var evaluated = false
    private let lock = NSLock()

    private init() {}

    /// ok / inj / dbg / bed
    var code: String {
        evaluate()
        lock.lock(); defer { lock.unlock() }
        if !injected.isEmpty { return "inj" }
        if debugged { return "dbg" }
        if bundleAltered { return "bed" }
        return "ok"
    }

    /// 本地是否值得信任
    ///
    /// 只看调试器：被动态附加时不把授权写盘，避免被直接 dump。
    /// 注入的库只上报不降级 —— 巨魔用户常装插件，不能因此让人家每次冷启动都要重新联网。
    var trustedLocally: Bool {
        evaluate()
        lock.lock(); defer { lock.unlock() }
        return !debugged
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
