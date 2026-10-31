import SwiftUI
import SceneKit

/// Hosts the 3D view with HUD and overlays layered on top.
struct GameView: View {
    @StateObject private var session: GameSession
    @EnvironmentObject private var settings: SettingsStore
    let onExit: () -> Void

    init(levelIndex: Int, progress: ProgressStore, settings: SettingsStore, onExit: @escaping () -> Void) {
        _session = StateObject(wrappedValue: GameSession(levelIndex: levelIndex, progress: progress, settings: settings))
        self.onExit = onExit
    }

    var body: some View {
        ZStack {
            GameSceneView(session: session)
                .ignoresSafeArea()

            HUDView(session: session, showDebugButton: debugAvailable)

            if session.showDebugPanel && debugAvailable {
                DebugOverlayView(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            overlay
        }
        .animation(.easeInOut(duration: 0.25), value: session.overlay)
        .animation(.easeInOut(duration: 0.2), value: session.isPaused)
        .animation(.easeInOut(duration: 0.2), value: session.showDebugPanel)
    }

    private var debugAvailable: Bool {
        #if DEBUG
        return settings.debugOverlayEnabled
        #else
        return false
        #endif
    }

    @ViewBuilder
    private var overlay: some View {
        switch session.overlay {
        case .victory(let stars, let shotsUsed, let hasNext):
            VictoryOverlay(
                stars: stars, shotsUsed: shotsUsed, hasNextLevel: hasNext,
                onNext: { session.nextLevel() },
                onReplay: { session.restart() },
                onMenu: leaveGame
            )
            .transition(.opacity)
        case .failure(let progress):
            FailureOverlay(
                progress: progress, threshold: session.hud.threshold,
                onRetry: { session.restart() },
                onMenu: leaveGame
            )
            .transition(.opacity)
        case .none:
            if session.isPaused {
                PauseOverlay(
                    onResume: { session.resume() },
                    onRestart: { session.restart() },
                    onMenu: leaveGame
                )
                .transition(.opacity)
            }
        }
    }

    private func leaveGame() {
        session.detach()
        onExit()
    }
}

/// Wraps the SceneKit view so SwiftUI owns layout while the session owns the scene.
struct GameSceneView: UIViewRepresentable {
    let session: GameSession

    func makeUIView(context: Context) -> GameSCNView {
        let view = GameSCNView(frame: .zero, options: nil)
        session.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: GameSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: GameSCNView, coordinator: ()) {
        uiView.aimDelegate = nil
        uiView.isPlaying = false
        uiView.scene = nil
    }
}
