import SwiftUI

@main
struct HeiMaoApp: App {

    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        /* 1.2.5：拒绝调试器附加；万一已经被挂上，先把本地授权清掉再退出，
           不让任何人从内存里把卡密和密钥 dump 走 */
        Hardening.install()
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        Hardening.enforce { ConfigStore.shared.purgeLocalLicense() }
                        // 回到前台：先向服务端要一次真实授权结论，
                        // 卡密在后台被作废/到期，这一刻界面就会同步变过来
                        model.applicationWillEnterForeground()
                        model.verifyNow()
                        model.loadAnnouncement()
                        model.pollStats()
                        model.checkUpdate()
                    case .background:
                        model.applicationDidEnterBackground()
                    default:
                        break
                    }
                }
        }
    }
}
