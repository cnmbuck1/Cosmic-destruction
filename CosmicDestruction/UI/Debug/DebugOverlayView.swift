import SwiftUI

/// Developer-only overlay: live stats and physics tuning. Edits a per-session
/// copy of PhysicsTuning; production defaults in GameConfig are untouched.
/// Only reachable in DEBUG builds with the Settings > Developer toggle on.
struct DebugOverlayView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                stats
                Divider().overlay(Theme.magenta.opacity(0.4))
                ScrollView {
                    VStack(spacing: 6) {
                        slider("Orb mass", \.orbMass, 1...30, "%.1f kg")
                        slider("Launch speed", \.launchSpeed, 8...40, "%.1f m/s")
                        gravitySlider
                        slider("Block friction", \.blockFriction, 0...1.5, "%.2f")
                        slider("Block restitution", \.blockRestitution, 0...0.8, "%.2f")
                        slider("Block mass", \.blockMass, 0.2...5, "%.2f kg")
                        slider("Settle threshold", \.settleSpeedThreshold, 0.05...1.5, "%.2f m/s")
                        slider("Camera FOV", \.cameraFieldOfView, 40...90, "%.0f°")
                        HStack {
                            Button("Reset tuning") { session.resetTuning() }
                            Spacer()
                            Button("Restart level") { session.restart() }
                        }
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.cyan)
                        .padding(.top, 4)
                    }
                }
                .frame(maxHeight: 230)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.magenta.opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    private var stats: some View {
        let s = session.debugStats
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "FPS %.0f   bodies %ld   phase %@", s.fps, s.rigidBodies, s.phase))
            Text(String(format: "gravity %.1f   launch %.1f m/s   time×%.2f", s.gravity, s.launchSpeed, s.timeScale))
            Text(String(format: "yaw %.1f°   elev %.1f°", s.yaw, s.elevation))
            Text(String(format: "targets left %ld   complete %.0f%%", s.remainingTargets, s.progress * 100))
        }
        .font(Theme.mono(11))
        .foregroundStyle(Theme.magenta)
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<PhysicsTuning, Float>,
                        _ range: ClosedRange<Float>, _ format: String) -> some View {
        let binding = Binding<Float>(
            get: { session.tuning[keyPath: keyPath] },
            set: { session.tuning[keyPath: keyPath] = $0 }
        )
        return row(title, value: binding.wrappedValue, format: format) {
            Slider(value: binding, in: range)
        }
    }

    private var gravitySlider: some View {
        let binding = Binding<Float>(
            get: { session.tuning.gravityOverride ?? session.level.gravity },
            set: { session.tuning.gravityOverride = $0 }
        )
        return row("Gravity", value: binding.wrappedValue, format: "%.1f m/s²") {
            Slider(value: binding, in: -25 ... -2)
        }
    }

    private func row<S: View>(_ title: String, value: Float, format: String, @ViewBuilder slider: () -> S) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 104, alignment: .leading)
            slider()
            Text(String(format: format, value))
                .frame(width: 70, alignment: .trailing)
        }
        .font(Theme.mono(10))
        .foregroundStyle(.white)
        .tint(Theme.magenta)
    }
}
