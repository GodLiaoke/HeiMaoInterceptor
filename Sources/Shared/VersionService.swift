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

/// 版本检测：GET /api/app/version?platform=ios&current=1.0
final class VersionService {

    static let shared = VersionService()

    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept": "application/json",
                                     "User-Agent": "HeiMaoInterceptor/\(AppConfig.appVersion) (iOS)"]
        session = URLSession(configuration: cfg)
    }

    /// 返回 (是否有更新, 是否强制, 最新版本信息)
    func check(current: String = AppConfig.appVersion,
               completion: @escaping (_ update: Bool, _ force: Bool, _ info: AppUpdateInfo?) -> Void) {

        var comps = URLComponents(string: AppConfig.apiBase + "/app/version")
        comps?.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "current", value: current)
        ]
        guard let url = comps?.url else {
            completion(false, false, nil); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        session.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, false, nil); return
            }
            let hasUpdate = (obj["update_available"] as? Bool) ?? false
            let force = (obj["force_update"] as? Bool) ?? false
            guard hasUpdate, let latest = obj["latest"] as? [String: Any] else {
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
        }.resume()
    }
}
