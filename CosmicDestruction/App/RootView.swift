import SwiftUI

enum AppScreen: Equatable {
    case menu
    case levelSelect
    case settings
    case game(levelIndex: Int)
}

/// Top-level navigation. A simple state switch keeps the game screen fully
/// in control of its own layout (no navigation bars over the 3D view).
struct RootView: View {
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var settings: SettingsStore
    @State private var screen: AppScreen = .menu

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch screen {
            case .menu:
                MainMenuView(
                    onPlay: { go(.levelSelect) },
                    onSettings: { go(.settings) }
                )
                .transition(.opacity)
            case .levelSelect:
                LevelSelectView(
                    onSelect: { index in go(.game(levelIndex: index)) },
                    onBack: { go(.menu) }
                )
                .transition(.opacity)
            case .settings:
                SettingsView(onBack: { go(.menu) })
                    .transition(.opacity)
            case .game(let index):
                GameView(levelIndex: index, progress: progress, settings: settings,
                         onExit: { go(.levelSelect) })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: screen)
        .onAppear {
            AudioManager.shared.soundEnabled = settings.soundEnabled
            AudioManager.shared.hapticsEnabled = settings.hapticsEnabled
            AudioManager.shared.prepare()
        }
        .onChange(of: settings.soundEnabled) { _, enabled in
            AudioManager.shared.soundEnabled = enabled
        }
        .onChange(of: settings.hapticsEnabled) { _, enabled in
            AudioManager.shared.hapticsEnabled = enabled
        }
    }

    private func go(_ next: AppScreen) {
        AudioManager.shared.play(.menu)
        screen = next
    }
}
