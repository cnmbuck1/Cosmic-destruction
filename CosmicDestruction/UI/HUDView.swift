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
                    Text("LEVEL \(hud.levelNumber)")
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

            ObjectiveBar(progress: hud.progress, threshold: hud.threshold)
                .allowsHitTesting(false)

            Spacer()

            if hud.showHint {
                Text("DRAG TO AIM  ·  RELEASE TO FIRE")
                    .font(Theme.label(12))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.panel))
                    .overlay(Capsule().stroke(Theme.cyan.opacity(0.4), lineWidth: 1))
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.25), value: hud.showHint)
    }
}

private struct ShotsIndicator: View {
    let remaining: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                let available = i < remaining
                Circle()
                    .fill(available
                          ? AnyShapeStyle(RadialGradient(colors: [.white, Theme.cyan], center: .center, startRadius: 0, endRadius: 9))
                          : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Theme.cyan.opacity(available ? 0.9 : 0.3), lineWidth: 1))
                    .shadow(color: available ? Theme.cyan.opacity(0.8) : .clear, radius: 5)
                    .scaleEffect(available ? 1 : 0.8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: available)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Capsule().fill(Theme.panel))
        .overlay(Capsule().stroke(Theme.cyan.opacity(0.4), lineWidth: 1))
    }
}

private struct ObjectiveBar: View {
    let progress: Float
    let threshold: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("DESTRUCTION")
                    .font(Theme.label(10))
                    .tracking(2)
                    .foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(Int((progress * 100).rounded()))% / \(Int((threshold * 100).rounded()))%")
                    .font(Theme.mono(11))
                    .foregroundStyle(progress >= threshold ? Theme.cyan : .white)
            }
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
            .animation(.easeOut(duration: 0.3), value: progress)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
    }
}
