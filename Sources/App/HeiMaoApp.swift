import SwiftUI

@main
struct HeiMaoApp: App {

    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        // 回到前台：先向服务端要一次真实授权结论，
                        // 卡密在后台被作废/到期，这一刻界面就会同步变过来
                        model.verifyNow()
                        model.loadAnnouncement()
                        model.pollStats()
                        model.checkUpdate()
                    }
                }
        }
    }
}
