import Foundation

/// 运维控制：维护模式 + 熔断（1.2.4 重写）
///
/// 1.2.3 的问题用户一眼就看出来了：熔断结论一旦落到本地，客户端下次启动
/// **不看云端直接崩**。后台把熔断关掉，客户端还是崩 —— 等于开关失效。
///
/// 现在改成两段式：
///   1. 启动时如果本地有熔断钉子，**先不崩**，把钉子原样拿出来
///   2. 先走一条独立心跳（PulseService）问云端「现在到底还熔不熔」
///      - 云端回 off / 已经不命中 → 拔钉，正常启动（后台一关就恢复）
///      - 云端回仍然命中        → 崩
///      - 云端连不上到阈值      → 崩（断网 / 改包 / 劫持都过不去，强度不降）
///
/// 这样“后台关掉熔断后客户端依旧熔断”彻底没了，同时防破解强度只增不减。
struct OpsState {
    var maintenance = false
    var maintenanceReason = ""
    var fuseMode = "off"
    var fuseBuild = 0
    var fuseReason = ""
    var minBuild = 0

    static let none = OpsState()

    /// 当前这台设备是否命中熔断
    func hitsFuse(currentBuild: Int = AppConfig.buildNumber) -> Bool {
        switch fuseMode {
        case "all":   return true
        case "below": return fuseBuild > 0 && currentBuild < fuseBuild
        default:      return false
        }
    }

    var fused: Bool { hitsFuse() }
}

enum OpsService {

    private static let pinKey = "hm.fuse.rule.v2"
    private static let legacyKey = "hm.fuse.rule.v1"
    private static let lock = NSLock()
    /// 启动时拿到的本地钉子：在云端确认之前一直挂着
    private static var pending: Rule?

    // MARK: - 解析

    static func parse(_ obj: [String: Any]) -> OpsState {
        var out = OpsState()
        if let m = obj["maintenance"] as? [String: Any] {
            out.maintenance = (m["on"] as? Bool) ?? false
            out.maintenanceReason = (m["reason"] as? String) ?? ""
        }
        if let f = obj["fuse"] as? [String: Any] {
            let mode = (f["mode"] as? String) ?? "off"
            out.fuseMode = ["off", "all", "below"].contains(mode) ? mode : "off"
            out.fuseBuild = (f["build"] as? Int) ?? 0
            out.fuseReason = (f["reason"] as? String) ?? ""
        }
        out.minBuild = (obj["min_build"] as? Int) ?? 0
        return out
    }

    // MARK: - 启动

    /// 启动第一步：把本地钉子取出来挂着，但**不执行**。
    /// 真正的结论由 PulseService 在拿到云端回应后给出。
    static func bootstrap() {
        lock.lock()
        pending = pinnedLocked()
        let p = pending
        lock.unlock()

        /* 老版本的钉子键顺手清掉：它带的是“无脑崩”的语义，
           留着只会在升级后第一次启动把人吓一跳 */
        UserDefaults.standard.removeObject(forKey: legacyKey)

        guard let rule = p else { return }
        let state = OpsState(maintenance: false, maintenanceReason: "",
                             fuseMode: rule.mode, fuseBuild: rule.build, fuseReason: rule.reason)
        /* 版本已经追上阈值：钉子作废，不必等云端 */
        if state.fuseMode == "below", rule.build > 0, AppConfig.buildNumber >= rule.build {
            unpin()
            lock.lock(); pending = nil; lock.unlock()
        }
    }

    /// 云端结论落地：这是唯一会真正执行熔断的地方
    @discardableResult
    static func apply(_ state: OpsState) -> Bool {
        if state.fused {
            /* 服务端明确说要熔断：钉住再崩，下次启动同样先问一次 */
            pin(state)
            die()
        }

        if state.fuseMode == "off" {
            /* 后台关掉了：钉子立刻拔掉。这就是“即时解除” */
            unpin()
            lock.lock(); pending = nil; lock.unlock()
            return false
        }

        /* 仍然是 below 但当前 build 已经追上：钉子作废 */
        if state.fuseMode == "below", state.fuseBuild > 0,
           AppConfig.buildNumber >= state.fuseBuild {
            unpin()
            lock.lock(); pending = nil; lock.unlock()
            return false
        }

        /* 云端说要熔断但当前版本不命中（比如阈值高于本机）：
           把规则更新成最新的，但本机继续正常跑 */
        pin(state)
        return false
    }

    /// 到阈值还连不上：本地钉子存在就按钉子结论崩；没有钉子就当作异常环境
    static func failClosed() -> Never {
        die()
    }

    /// 启动挂着的钉子是否还要求熔断（PulseService 失败时用来判断）
    static var pendingFuse: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let rule = pending else { return false }
        let state = OpsState(maintenance: false, maintenanceReason: "",
                             fuseMode: rule.mode, fuseBuild: rule.build, fuseReason: rule.reason)
        return state.fused
    }

    // MARK: - 本地钉子

    private struct Rule: Codable {
        var mode: String
        var build: Int
        var reason: String
        var at: Int
    }

    private static func pin(_ state: OpsState) {
        let rule = Rule(mode: state.fuseMode, build: state.fuseBuild,
                        reason: state.fuseReason, at: Int(Date().timeIntervalSince1970))
        if let data = try? JSONEncoder().encode(rule) {
            lock.lock()
            UserDefaults.standard.set(data, forKey: pinKey)
            lock.unlock()
        }
    }

    private static func pinned() -> Rule? {
        lock.lock(); defer { lock.unlock() }
        return pinnedLocked()
    }

    private static func pinnedLocked() -> Rule? {
        guard let data = UserDefaults.standard.data(forKey: pinKey) else { return nil }
        return try? JSONDecoder().decode(Rule.self, from: data)
    }

    private static func unpin() {
        lock.lock()
        UserDefaults.standard.removeObject(forKey: pinKey)
        lock.unlock()
    }

    // MARK: - 崩

    /// 真崩：写非法地址 + abort 双保险
    ///
    /// 不用 exit(0) —— 那看起来像正常退出，hook 掉一个函数就能拦。
    /// 这里两条路径任意一条生效都留不下可用的进程。
    static func die() -> Never {
        #if DEBUG
        print("[fuse] triggered")
        #endif
        let bogus = UnsafeMutableRawPointer(bitPattern: 0x10)
        bogus?.storeBytes(of: 1, as: UInt8.self)
        abort()
    }
}
