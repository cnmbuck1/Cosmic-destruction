import SwiftUI

struct SettingsView: View {
    let onBack: () -> Void

    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var progress: ProgressStore
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            SpaceBackdrop()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HUDIconButton(systemName: "chevron.left", action: onBack)
                    Spacer()
                }
                Text("SETTINGS")
                    .font(Theme.display(24))
                    .tracking(4)
                    .foregroundStyle(.white)
                    .neonGlow()
                    .frame(maxWidth: .infinity)

                section {
                    Toggle("Sound", isOn: $settings.soundEnabled)
                    Divider().overlay(Color.white.opacity(0.1))
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                }

                #if DEBUG
                Text("DEVELOPER")
                    .font(Theme.label(12))
                    .tracking(3)
                    .foregroundStyle(Theme.purple)
                section {
                    Toggle("Debug overlay button", isOn: $settings.debugOverlayEnabled)
                    Divider().overlay(Color.white.opacity(0.1))
                    Toggle("Slow-motion moments", isOn: $settings.slowMotionEnabled)
                }
                #endif

                Button("RESET PROGRESS") { confirmReset = true }
                    .buttonStyle(NeonButtonStyle(color: Theme.magenta, filled: false))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .tint(Theme.cyan)
        .alert("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { progress.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unlocked levels and star ratings will be cleared.")
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 12) { content() }
            .font(Theme.label(15))
            .foregroundStyle(.white)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.cyan.opacity(0.3), lineWidth: 1))
            )
    }
}
