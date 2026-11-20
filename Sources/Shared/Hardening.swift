import Foundation
import Darwin

/// 运行环境加固（1.2.5）
///
/// 审计里最要命的一条是「发布包带着 get-task-allow=true」：任何人拿 debugserver
/// 挂上进程就能读到内存里解密后的卡密、密钥和授权判定，卡密校验等于没做。
///
/// 1.2.5 起做两层：
///   1. 包里不再带 get-task-allow（构建期硬校验，见 CI）
///   2. 进程启动即 `PT_DENY_ATTACH`，让调试器 attach 直接失败；
///      再叠一层 `P_TRACED` 复查，万一被其它方式挂上，先把本地授权清掉再退出
///
/// 不碰 `platform-application`：巨魔安装必须带，而且它不影响调试面。
enum Hardening {

    private static let lock = NSLock()
    private static var hardened = false

    /// PT_DENY_ATTACH：此后再有调试器 attach 会直接被系统拒绝
    private static let ptDenyAttach: Int32 = 31

    /// 启动即调用：拒绝调试器附加。重复调用无副作用。
    static func install() {
        lock.lock()
        if hardened { lock.unlock(); return }
        hardened = true
        lock.unlock()

        /* 用 dlsym 取符号再调，避开各 SDK 里 ptrace 参数签名的差异 */
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") else { return }
        typealias PtraceFn = @convention(c) (Int32, Int32, UnsafeMutableRawPointer?, Int32) -> Int32
        let fn = unsafeBitCast(sym, to: PtraceFn.self)
        _ = fn(ptDenyAttach, 0, nil, 0)
    }

    /// 当前是否被调试器附着
    static var traced: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let r = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard r == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// 被调试时：清掉本地授权（内存 + 落盘），随即退出。
    ///
    /// 只清授权、不删别的数据，卸掉调试器重开就能正常用。
    static func enforce(wipe: () -> Void) {
        guard traced else { return }
        wipe()
        /* 给写盘一点时间再退出；不用 abort，避免留下可定位的崩溃栈 */
        usleep(120_000)
        exit(0)
    }
}
