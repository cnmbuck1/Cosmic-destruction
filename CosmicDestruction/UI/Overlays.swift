import SwiftUI

/// Shared frosted panel for overlays.
private struct OverlayPanel<Content: View>: View {
    var accent: Color = Theme.cyan
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 20) { content() }
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(accent.opacity(0.6), lineWidth: 1.5))
                        .shadow(color: accent.opacity(0.35), radius: 30)
                )
                .padding(.horizontal, 24)
        }
    }
}

struct VictoryOverlay: View {
    let stars: Int
    let shotsUsed: Int
    let hasNextLevel: Bool
    let onNext: () -> Void
    let onReplay: () -> Void
    let onMenu: () -> Void

    @State private var revealed = 0
    @State private var titleIn = false

    var body: some View {
        OverlayPanel {
            Text("LEVEL COMPLETE")
                .font(Theme.display(24))
                .tracking(3)
                .foregroundStyle(.white)
                .neonGlow(Theme.cyan, radius: 14)
                .scaleEffect(titleIn ? 1 : 1.4)
                .opacity(titleIn ? 1 : 0)

            StarRow(stars: stars, size: 40, revealed: revealed)
                .padding(.vertical, 6)

            Text("SHOTS USED: \(shotsUsed)")
                .font(Theme.mono(14))
                .foregroundStyle(Theme.textDim)

            VStack(spacing: 12) {
                if hasNextLevel {
                    Button("NEXT LEVEL", action: onNext)
                        .buttonStyle(NeonButtonStyle())
                } else {
                    Text("All prototype levels cleared!")
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.cyan)
                }
                Button("REPLAY", action: onReplay)
                    .buttonStyle(NeonButtonStyle(color: Theme.purple, filled: !hasNextLevel))
                Button("LEVELS", action: onMenu)
                    .font(Theme.label(13))
                    .tracking(2)
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 4)
            }
        }
        .task {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { titleIn = true }
            for i in 1...3 {
                try? await Task.sleep(nanoseconds: 220_000_000)
                revealed = i
            }
        }
    }
}

struct FailureOverlay: View {
    let progress: Float
    let threshold: Float
    let onRetry: () -> Void
    let onMenu: () -> Void

    private var message: String {
        let gap = threshold - progress
        if gap <= 0.1 { return "So close! One more try." }
        if gap <= 0.3 { return "Good damage. Look for the weak point." }
        return "Try a different angle on the supports."
    }

    var body: some View {
        OverlayPanel(accent: Theme.purple) {
            Text("LEVEL FAILED")
                .font(Theme.display(24))
                .tracking(3)
                .foregroundStyle(.white)
                .neonGlow(Theme.purple, radius: 12)

            VStack(spacing: 6) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(Theme.display(44))
                    .foregroundStyle(Theme.cyan)
                    .neonGlow()
                Text("TARGET DESTRUCTION (NEED \(Int((threshold * 100).rounded()))%)")
                    .font(Theme.label(10))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textDim)
            }

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button("RETRY", action: onRetry)
                    .buttonStyle(NeonButtonStyle())
                Button("LEVELS", action: onMenu)
                    .font(Theme.label(13))
                    .tracking(2)
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 4)
            }
        }
    }
}

struct PauseOverlay: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onMenu: () -> Void

    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        OverlayPanel {
            Text("PAUSED")
                .font(Theme.display(26))
                .tracking(4)
                .foregroundStyle(.white)
                .neonGlow()

            VStack(spacing: 12) {
                Button("RESUME", action: onResume)
                    .buttonStyle(NeonButtonStyle())
                Button("RESTART", action: onRestart)
                    .buttonStyle(NeonButtonStyle(color: Theme.purple, filled: false))
                Button("LEVELS", action: onMenu)
                    .buttonStyle(NeonButtonStyle(color: Theme.textDim, filled: false))
            }

            HStack(spacing: 24) {
                Toggle(isOn: $settings.soundEnabled) {
                    Image(systemName: settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                Toggle(isOn: $settings.hapticsEnabled) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                }
            }
            .toggleStyle(.button)
            .tint(Theme.cyan)
        }
    }
}
