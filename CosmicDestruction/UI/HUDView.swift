import SwiftUI

/// Gameplay HUD: level, shots, objective progress, pause. Only the buttons
/// accept touches; everything else passes through to the aiming view.
struct HUDView: View {
    @ObservedObject var session: GameSession
    let showDebugButton: Bool

    private var hud: HUDState { session.hud }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HUDIconButton(systemName: "pause.fill") { session.pause() }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(hud.worldName) · LEVEL \(hud.levelNumber)")
                        .font(Theme.label(11))
                        .tracking(3)
                        .foregroundStyle(Theme.cyan)
                    Text(hud.levelName.uppercased())
                        .font(Theme.label(15))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .allowsHitTesting(false)

                Spacer(minLength: 4)

                if showDebugButton {
                    Button {
                        session.showDebugPanel.toggle()
                    } label: {
                        Text("DBG")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.magenta)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.panel))
                            .overlay(Circle().stroke(Theme.magenta.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                ShotsIndicator(remaining: hud.shotsRemaining, total: hud.maxShots)
                    .allowsHitTesting(false)
            }

            ObjectiveBar(progress: hud.progress, threshold: hud.threshold,
                         abyssCount: hud.abyssCount, score: hud.score,
                         presetLabel: showDebugButton ? hud.impactPreset : nil,
                         onCyclePreset: { session.cycleImpactPreset() })

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                if hud.showHint {
                    Text("DRAG TO AIM  ·  TAP FIRE")
                        .font(Theme.label(12))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.panel))
                        .overlay(Capsule().stroke(Theme.cyan.opacity(0.4), lineWidth: 1))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                FireButton(enabled: hud.canFire) { session.fireButtonPressed() }
            }
            .padding(.bottom, 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.25), value: hud.showHint)
    }
}

/// Separate FIRE control (build 5): dragging aims, this launches.
private struct FireButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("FIRE")
                .font(Theme.label(16))
                .tracking(2.5)
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(
                    Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.48, blue: 0.84),
                                                          Color(red: 0.76, green: 0.12, blue: 0.56),
                                                          Color(red: 0.35, green: 0.05, blue: 0.27)],
                                                 center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 46))
                )
                .overlay(Circle().stroke(Color(red: 1, green: 0.69, blue: 0.9), lineWidth: 2))
                .shadow(color: Theme.magenta.opacity(enabled ? 0.75 : 0), radius: 12)
        }
        .buttonStyle(FirePressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .saturation(enabled ? 1 : 0.3)
        .animation(.easeOut(duration: 0.2), value: enabled)
        .accessibilityLabel("Fire")
    }
}

private struct FirePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ShotsIndicator: View {
    let remaining: Int
    let total: Int

    var body: some View {
        // Up to 6 shots as pips; longer levels show a compact count so the
        // level name keeps its room.
        HStack(spacing: 6) {
            if total > 6 {
                Circle()
                    .fill(RadialGradient(colors: [.white, Theme.cyan], center: .center, startRadius: 0, endRadius: 9))
                    .frame(width: 12, height: 12)
                    .shadow(color: Theme.cyan.opacity(0.8), radius: 5)
                Text("\(remaining)/\(total)")
                    .font(Theme.mono(13))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(remaining)))
                    .animation(.easeOut(duration: 0.25), value: remaining)
                    .accessibilityLabel("\(remaining) of \(total) shots left")
            } else {
                ForEach(0..<total, id: \.self) { i in
                    let available = i < remaining
                    Circle()
                        .fill(available
                              ? AnyShapeStyle(RadialGradient(colors: [.white, Theme.cyan], center: .center, startRadius: 0, endRadius: 9))
                              : AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.cyan.opacity(available ? 0.9 : 0.3), lineWidth: 1))
                        .shadow(color: available ? Theme.cyan.opacity(0.8) : .clear, radius: 5)
                        .scaleEffect(available ? 1 : 0.8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: available)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Theme.cyan.opacity(0.4), lineWidth: 1))
    }
}

/// Live destruction readout: "DESTRUCTION: 65%" with a rolling number, a
/// brief pulse whenever it rises, and a bar showing the target. Below it, the
/// abyss bonus count ("INTO THE VOID"), the score and, in debug builds, the
/// impact preset switch. Only that switch accepts touches.
private struct ObjectiveBar: View {
    let progress: Float
    let threshold: Float
    let abyssCount: Int
    let score: Int
    /// Debug impact preset (A/B/C); nil hides the switch.
    let presetLabel: String?
    let onCyclePreset: () -> Void
    @State private var pulse = false
    @State private var abyssPulse = false

    private var percent: Int { Int((progress * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("DESTRUCTION: \(percent)%")
                    .font(Theme.label(15))
                    .tracking(1.5)
                    .foregroundStyle(progress >= threshold ? Theme.cyan : .white)
                    .contentTransition(.numericText(value: Double(percent)))
                    .scaleEffect(pulse ? 1.08 : 1, anchor: .leading)
                    .shadow(color: Theme.cyan.opacity(pulse ? 0.9 : 0), radius: 8)
                Spacer()
                Text("TARGET \(Int((threshold * 100).rounded()))%")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textDim)
            }
            .allowsHitTesting(false)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.purple, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, width * CGFloat(min(1, progress))))
                        .shadow(color: Theme.cyan.opacity(0.7), radius: 4)
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 12)
                        .offset(x: width * CGFloat(threshold) - 1)
                }
            }
            .frame(height: 8)
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                Text("INTO THE VOID: \(abyssCount)")
                    .foregroundStyle(Theme.purple)
                    .contentTransition(.numericText(value: Double(abyssCount)))
                    .scaleEffect(abyssPulse ? 1.15 : 1, anchor: .leading)
                    .allowsHitTesting(false)
                Text("SCORE \(score.formatted())")
                    .foregroundStyle(Theme.textDim)
                    .contentTransition(.numericText(value: Double(score)))
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
                if let presetLabel {
                    Button("IMPACT \(presetLabel)", action: onCyclePreset)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.magenta)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.magenta.opacity(0.5), lineWidth: 1))
                        .accessibilityLabel("Impact preset \(presetLabel), debug")
                }
            }
            .font(Theme.mono(10))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel).allowsHitTesting(false))
        .animation(.easeOut(duration: 0.35), value: progress)
        .animation(.easeOut(duration: 0.3), value: score)
        .onChange(of: abyssCount) { old, new in
            guard new > old else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { abyssPulse = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.easeOut(duration: 0.3)) { abyssPulse = false }
            }
        }
        .onChange(of: percent) { old, new in
            guard new > old else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { pulse = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.easeOut(duration: 0.3)) { pulse = false }
            }
        }
    }
}
