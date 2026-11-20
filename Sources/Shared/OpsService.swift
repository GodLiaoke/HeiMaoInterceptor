import Foundation

/// 运维控制：维护模式 + 熔断（1.2.3）
///
/// 服务端在 `/app/version` 里带回两块状态：
///   maintenance = { on: Bool, reason: String }
///   fuse        = { mode: off|all|below, build: Int, reason: String }
///
/// 客户端拿到之后的处理：
///   - 维护：盖一层维护页，下方原样显示原因；不闪退，用户可以等
///   - 熔断：直接崩（SIGSEGV + abort），并且把结论钉在本地 ——
///     下次断网启动也照样崩，绕不过去
///
/// 熔断是「防破解」的最后一道：被改过的包拿不到正常版本号，或者干脆
/// 被线上判成该熔断的版本，就在启动这一下退场。
struct OpsState {
    var maintenance = false
    var maintenanceReason = ""
    var fuseMode = "off"
    var fuseBuild = 0
    var fuseReason = ""

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

    private static let pinKey = "hm.fuse.rule.v1"
    private static let lock = NSLock()

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
        return out
    }

    // MARK: - 执行

    /// 收到线上状态后调用：钉住熔断结论，命中就当场退出
    @discardableResult
    static func enforce(_ state: OpsState) -> Bool {
        if state.fuseMode != "off" {
            pin(state)
        }
        if state.fused {
            die()
        }
        /* 版本已经追上熔断阈值：把钉子拔掉，避免升级后还被老结论卡住 */
        if state.fuseMode == "below", state.fuseBuild > 0,
           AppConfig.buildNumber >= state.fuseBuild {
            unpin()
        }
        return false
    }

    /// 启动时（还没联网）先看本地钉子
    static func enforcePinned() {
        guard let rule = pinned() else { return }
        let state = OpsState(maintenance: false, maintenanceReason: "",
                             fuseMode: rule.mode, fuseBuild: rule.build, fuseReason: rule.reason)
        if state.fused {
            die()
        }
        if rule.mode == "below", rule.build > 0, AppConfig.buildNumber >= rule.build {
            unpin()
        }
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
        lock.lock()
        let data = UserDefaults.standard.data(forKey: pinKey)
        lock.unlock()
        guard let data = data else { return nil }
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
        print("[fuse] triggered:", pinned()?.reason ?? "")
        #endif
        let bogus = UnsafeMutableRawPointer(bitPattern: 0x10)
        bogus?.storeBytes(of: 1, as: UInt8.self)
        abort()
    }
}
