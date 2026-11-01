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

            if let world = session.worldBanner {
                WorldBanner(world: world)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }

            if session.showDebugPanel && debugAvailable {
                DebugOverlayView(session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            overlay
        }
        .animation(.easeInOut(duration: 0.25), value: session.overlay)
        .animation(.easeInOut(duration: 0.4), value: session.worldBanner?.key)
        .animation(.easeInOut(duration: 0.2), value: session.isPaused)
        .animation(.easeInOut(duration: 0.2), value: session.showDebugPanel)
        #if DEBUG
        .task {
            // CI smoke test hooks:
            // `-SmokeTestAutoFire` fires one shot at the default aim after 2 s.
            // `-SmokeTestTargets "x,y,z;x,y,z"` aims at each world point in turn and
            // fires as soon as the previous shot resolves, appending a summary line
            // per shot to Documents/smoke-results.txt.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-SmokeTestTargets"), i + 1 < args.count {
                let targets = args[i + 1].split(separator: ";").compactMap { item -> SIMD3<Float>? in
                    let v = item.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                    return v.count == 3 ? SIMD3<Float>(v[0], v[1], v[2]) : nil
                }
                await runSmokeTargets(targets)
                return
            }
            guard args.contains("-SmokeTestAutoFire") else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            session.debugFire()
        }
        #endif
    }

    #if DEBUG
    @MainActor
    private func runSmokeTargets(_ targets: [SIMD3<Float>]) async {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("smoke-results.txt")
        var log = "level \(session.level.id) \(session.level.name)\n"
        func write() { try? log.write(to: url, atomically: true, encoding: .utf8) }
        write()
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        for (n, target) in targets.enumerated() {
            // Wait (up to 15 s) for the previous shot to resolve.
            var waited = 0
            while !session.debugCanFire, waited < 60 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                waited += 1
            }
            guard session.debugCanFire else { break }
            let aim = session.debugAim(at: target)
            try? await Task.sleep(nanoseconds: 300_000_000)
            session.debugFire()
            log += String(format: "shot %ld target (%.2f, %.2f, %.2f) yaw %.1f el %.1f\n",
                          n + 1, target.x, target.y, target.z, aim.yaw, aim.elevation)
            write()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            waited = 0
            while !session.debugCanFire, session.overlay == .none, waited < 60 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                waited += 1
            }
            log += "  after: \(session.debugSummary)\n"
            write()
            if session.overlay != .none { break }
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        log += "final: \(session.debugSummary)\n"
        write()
    }
    #endif

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
        case .victory(let stars, let shotsUsed, let abyssCount, let score, let hasNext):
            VictoryOverlay(
                stars: stars, shotsUsed: shotsUsed, abyssCount: abyssCount, score: score, hasNextLevel: hasNext,
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

/// "WORLD 2 · MARS" title card shown when play arrives on a new planet.
private struct WorldBanner: View {
    let world: WorldTheme

    var body: some View {
        VStack(spacing: 6) {
            Text("WORLD \(world.number)")
                .font(Theme.label(12))
                .tracking(5)
                .foregroundStyle(Theme.cyan)
            Text(world.name.uppercased())
                .font(Theme.display(40))
                .tracking(5)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .neonGlow()
            Text(world.tagline)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black, radius: 4)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 230)
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
