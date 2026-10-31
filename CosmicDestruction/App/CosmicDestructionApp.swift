import SwiftUI

@main
struct CosmicDestructionApp: App {
    @StateObject private var progress = ProgressStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(progress)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
