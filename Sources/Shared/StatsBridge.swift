import Foundation

/// 扩展 → 主程序的统计桥
///
/// 为什么需要它：`sendProviderMessage` 是唯一官方通道，但它没有重传，
/// 扩展忙、会话刚建立、系统切换网络的那几秒都可能丢回包。
/// 丢了以后 App 侧只能拿到空字典，表现就是「拦截明明在生效，面板全是 0」。
///
/// 所以扩展每 2 秒把快照落一份盘，App 拿不到回包就直接读这份。
///
/// 落盘为什么是「全部候选路径各写一份」而不是「写成功一个就走」：
/// 扩展和主程序是两个进程、两套沙盒。App Group 容器只有真的拿到 group
/// entitlement 时才共享，TrollStore 伪签名场景下经常拿得到一个路径却写不进去；
/// 以前第一个路径写失败就退到 UserDefaults(suiteName:)，那个域在两个进程里
/// 各是一份，等于写了个只有自己看得见的文件 —— App 侧永远是 0。
/// 现在所有候选都写，App 读的时候取 bridgeAt 最新的那一份。
enum StatsBridge {

    private static let groupID = "group.com.heimao.interceptor"
    private static let fileName = "hm-stats.json"
    private static let defaultsKey = "hm.stats.bridge"
    /// 巨魔 / 平台应用环境：主程序和扩展都能读写的公共缓存目录
    private static let sharedDir = "/var/mobile/Library/Caches/com.heimao.interceptor"

    /// 主程序在启动隧道时把自己的 Documents 路径塞进 providerConfiguration，
    /// 扩展照着写进来。这是最可靠的一条：App 自己的容器一定可写，
    /// 平台应用环境下扩展也能写进去，不依赖 App Group 有没有真的建好。
    private static var extraDir: String?

    static func setExtraDir(_ path: String?) {
        guard let p = path, !p.isEmpty else { return }
        extraDir = p
    }

    // MARK: - 写

    static func write(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        /* 每个候选路径都写一遍，不因为第一个成功就收手：
           App 和扩展对「哪个目录可写」的判断可能不一样。 */
        for url in writeTargets() {
            try? data.write(to: url, options: .atomic)
        }

        if let d = UserDefaults(suiteName: groupID) {
            d.set(data, forKey: defaultsKey)
            /* 1.2.2：去掉 synchronize()。iOS 8 之后它就不再是「立即落盘」的意思，
               每次都等一次跨进程同步纯属白烧扩展的 CPU 时间；
               App 侧的主通道是本机直连，这份只是兜底。 */
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: - 读

    static func read() -> [String: Any] {
        var best: [String: Any] = [:]
        var bestAt = Int.min

        for url in readTargets() {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let at = (obj["bridgeAt"] as? Int) ?? 0
            if at > bestAt {
                bestAt = at
                best = obj
            }
        }
        if !best.isEmpty { return best }

        for d in [UserDefaults(suiteName: groupID), UserDefaults.standard] {
            guard let d = d,
                  let data = d.data(forKey: defaultsKey),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let at = (obj["bridgeAt"] as? Int) ?? 0
            if at > bestAt {
                bestAt = at
                best = obj
            }
        }
        return best
    }

    /// 扩展是否还活着（快照在有效期内写过）
    ///
    /// 1.2.2：落盘从 2 秒降到 10 秒、空闲时 30 秒保温写一次，
    /// 所以这里的窗口同步放宽到 40 秒，否则会把活着的扩展误判成「上次快照」。
    static func isFresh(_ payload: [String: Any]) -> Bool {
        guard let at = payload["bridgeAt"] as? Int else { return false }
        return abs(Int(Date().timeIntervalSince1970) - at) <= 40
    }

    /// 快照距今多少秒（给界面显示「扩展多久没写盘了」）
    static func age(_ payload: [String: Any]) -> Int? {
        guard let at = payload["bridgeAt"] as? Int, at > 0 else { return nil }
        return abs(Int(Date().timeIntervalSince1970) - at)
    }

    // MARK: - 候选路径

    private static func writeTargets() -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        /* 主程序指定的目录放第一位：这条最不会被沙盒挡住 */
        if let dir = extraDir {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            out.append(URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(fileName))
        }
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            let dir = g.appendingPathComponent("Library/Caches", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            out.append(dir.appendingPathComponent(fileName))
        }
        for dir in [sharedDir, NSTemporaryDirectory()] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            out.append(URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(fileName))
        }
        return out
    }

    private static func readTargets() -> [URL] {
        var out: [URL] = []
        /* 主程序读自己的 Documents：扩展按这个路径写，两边必然对得上 */
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            out.append(docs.appendingPathComponent(fileName))
        }
        if let g = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            out.append(g.appendingPathComponent("Library/Caches", isDirectory: true)
                .appendingPathComponent(fileName))
        }
        out.append(URL(fileURLWithPath: sharedDir, isDirectory: true).appendingPathComponent(fileName))
        return out
    }
}
