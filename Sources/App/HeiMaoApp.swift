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
                        model.refreshLocal()
                        model.loadAnnouncement()
                        model.pollStats()
                        model.checkUpdate()
                        // 回到前台随手心跳一次，拿到最新时效
                        if model.authorized {
                            model.refreshLicense(silent: true)
                        }
                    }
                }
        }
    }
}
