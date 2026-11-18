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
                        section("PROJECTILE")
                        slider("Orb mass", \.orbMass, 1...30, "%.1f kg")
                        slider("Launch speed", \.launchSpeed, 8...40, "%.1f m/s")
                        section("BLOCKS")
                        slider("Standard mass", \.standardBlockMass, 0.1...3, "%.2f kg")
                        slider("Heavy mass", \.heavyBlockMass, 0.3...6, "%.2f kg")
                        slider("Block friction", \.blockFriction, 0...1.5, "%.2f")
                        slider("Block restitution", \.blockRestitution, 0...0.8, "%.2f")
                        slider("Max block speed", \.maxBlockVelocity, 5...40, "%.0f m/s")
                        section("IMPACT")
                        Picker("Impact preset", selection: Binding(
                            get: { session.tuning.impact.id },
                            set: { session.tuning.impact = ImpactPreset.preset($0) })) {
                            ForEach(ImpactPreset.all) { preset in
                                Text("\(preset.id.rawValue) \(preset.name)").tag(preset.id)
                            }
                        }
                        .pickerStyle(.segmented)
                        slider("Velocity change", \.impact.velocityChange, 0...25, "%.1f m/s")
                        slider("Radius", \.impact.radius, 0.5...5, "%.1f m")
                        slider("Falloff exponent", \.impact.falloffExponent, 0.5...3, "%.2f")
                        slider("Forward weight", \.impact.forwardWeight, 0...1.5, "%.2f")
                        slider("Radial weight", \.impact.radialWeight, 0...1.5, "%.2f")
                        slider("Upward weight", \.impact.upwardWeight, 0...1.5, "%.2f")
                        slider("Spin", \.impact.spin, 0...15, "%.1f rad/s")
                        slider("Max per block", \.impact.maxVelocityChange, 1...30, "%.0f m/s")
                        section("SCORING")
                        slider("Displaced dist.", \.scoring.displacedDistance, 0.2...2, "%.2f m")
                        slider("Displaced tilt", \.scoring.displacedTiltDegrees, 5...80, "%.0f°")
                        slider("Settle threshold", \.settleSpeedThreshold, 0.05...1.5, "%.2f m/s")
                        section("ENVIRONMENT")
                        gravitySlider
                        slider("Abyss fade", \.abyssFadeDepth, 1...12, "%.1f m")
                        slider("Abyss cleanup", \.abyssCleanupDepth, 8...40, "%.0f m")
                        section("CAMERA")
                        slider("Elevation", \.cameraElevation, 3...14, "%.1f m")
                        slider("Distance", \.cameraDistance, 1...12, "%.1f m")
                        slider("Look height", \.cameraLookHeight, 0...4, "%.1f m")
                        slider("Look ahead", \.cameraLookAhead, -2...4, "%.1f m")
                        slider("FOV (horiz.)", \.cameraFieldOfView, 25...90, "%.0f°")
                        slider("Shake", \.cameraShakeIntensity, 0...2, "%.2f×")
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
                .frame(maxHeight: 260)
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
        let t = session.tuning
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "FPS %.0f   bodies %ld   phase %@", s.fps, s.rigidBodies, s.phase))
            Text(String(format: "gravity %.1f   launch %.1f m/s   time×%.2f", s.gravity, s.launchSpeed, s.timeScale))
            Text(String(format: "yaw %.1f°   elev %.1f°", s.yaw, s.elevation))
            Text(String(format: "targets left %ld   complete %.0f%%", s.remainingTargets, s.progress * 100))
            Text(String(format: "orb %.1f m/s   hits %ld   impacts %ld   preset %@", s.orbSpeed, s.orbImpacts,
                        s.supplementalThisShot, t.impact.id.rawValue))
            Text(String(format: "blocks %ld/%ld   moved %ld   fallen %ld   trails %ld",
                        s.activeBlocks, s.totalBlocks, s.displacedBlocks, s.fallenBlocks, s.debrisTrails))
            Text(String(format: "max v %.2f   quiet %.1fs   shot %.1fs", s.maxBlockSpeed, s.timeSinceCollision, s.shotElapsed))
            Text(String(format: "fragment %.0f×%.0f×%.1f m   abyss fade %.0f / clean %.0f m",
                        t.platformWidth, t.platformDepth, t.platformThickness, t.abyssFadeDepth, t.abyssCleanupDepth))
            Text(String(format: "camera elev %.1f  dist %.1f  fov %.0f  shake %.1f",
                        t.cameraElevation, t.cameraDistance, t.cameraFieldOfView, t.cameraShakeIntensity))
        }
        .font(Theme.mono(11))
        .foregroundStyle(Theme.magenta)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.magenta)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
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
