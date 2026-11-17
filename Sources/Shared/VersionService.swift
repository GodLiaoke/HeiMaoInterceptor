import Foundation

/// 服务端返回的版本信息
struct AppUpdateInfo {
    var version: String
    var build: Int
    var url: String
    var notes: String
    var minVersion: String
    var force: Bool
}

/// 版本检测：走 v3 加密通道调用 /app/version
final class VersionService {

    static let shared = VersionService()

    private init() {}

    /// 返回 (是否有更新, 是否强制, 最新版本信息)
    func check(current: String = AppConfig.appVersion,
               pin: String = "",
               completion: @escaping (_ update: Bool, _ force: Bool, _ info: AppUpdateInfo?) -> Void) {

        let device = pin.isEmpty ? "00000000" : pin

        SecureChannel.post(Obfs.s(25),
                           params: ["platform": "ios", "current": current,
                             "build": AppConfig.buildNumber],
                           pin: device) { result in
            guard case .success(let obj) = result else {
                completion(false, false, nil); return
            }
            let hasUpdate = (obj["update_available"] as? Bool) ?? false
            let force = (obj["force_update"] as? Bool) ?? false
            guard hasUpdate, let latest = obj["latest"] as? [String: Any] else {
                completion(false, false, nil); return
            }
            /* 本地 build 已经不低于服务端最新版就别打扰用户：
               服务端只按版本号字符串比，build 号更精确；
               后台某条记录的版本号没跟上时，也不会把新包用户锁在更新弹窗里 */
            if let latestBuild = latest["build"] as? Int,
               latestBuild > 0, latestBuild <= AppConfig.buildNumber {
                completion(false, false, nil); return
            }

            let info = AppUpdateInfo(
                version: (latest["version"] as? String) ?? "",
                build: (latest["build"] as? Int) ?? 0,
                url: (latest["url"] as? String) ?? "",
                notes: (latest["notes"] as? String) ?? "",
                minVersion: (latest["min_version"] as? String) ?? "",
                force: force
            )
            DispatchQueue.main.async {
                completion(true, force, info)
            }
        }
    }
}
