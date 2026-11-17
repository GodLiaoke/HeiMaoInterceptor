import Foundation

/// 扩展 → 主程序的统计桥
///
/// 为什么需要它：`sendProviderMessage` 是唯一官方通道，但它没有重传，
/// 扩展忙、会话刚建立、系统切换网络的那几秒都可能丢回包。
/// 丢了以后 App 侧只能拿到空字典，表现就是「拦截明明在生效，面板全是 0」。
///
/// 所以扩展每 2 秒把快照落一份盘，App 拿不到回包就直接读这份。
/// 落盘位置按优先级：
///   1. App Group 共享容器（标准做法）
///   2. /var/mobile/Library/Caches（巨魔 / 平台应用环境，双方都能写）
///   3. UserDefaults(suiteName:)（前两条都不可写时的兜底）
enum StatsBridge {

    private static let groupID = "group.com.heimao.interceptor"
    private static let fileName = "hm-stats.json"
    private static let defaultsKey = "hm.stats.bridge"
    private static let fallbackDir = "/var/mobile/Library/Caches/com.heimao.interceptor"

    static func write(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        if let url = fileURL(create: true, mustExist: false) {
            do {
                try data.write(to: url, options: .atomic)
                return
            } catch {
                /* 写不进去就继续走后面的兜底 */
            }
        }
        if let d = UserDefaults(suiteName: groupID) {
            d.set(data, forKey: defaultsKey)
            d.synchronize()
            return
        }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func read() -> [String: Any] {
        if let url = fileURL(create: false, mustExist: true),
           let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if let d = UserDefaults(suiteName: groupID),
           let data = d.data(forKey: defaultsKey),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return [:]
    }

    /// 扩展是否还活着（快照 10 秒内写过）
    static func isFresh(_ payload: [String: Any]) -> Bool {
        guard let at = payload["bridgeAt"] as? Int else { return false }
        return abs(Int(Date().timeIntervalSince1970) - at) <= 10
    }

    private static func fileURL(create: Bool, mustExist: Bool) -> URL? {
        let fm = FileManager.default
        var dirs: [URL] = []
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            dirs.append(g.appendingPathComponent("Library/Caches", isDirectory: true))
        }
        dirs.append(URL(fileURLWithPath: fallbackDir, isDirectory: true))

        for dir in dirs {
            if create {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let url = dir.appendingPathComponent(fileName)
            if !mustExist || fm.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
