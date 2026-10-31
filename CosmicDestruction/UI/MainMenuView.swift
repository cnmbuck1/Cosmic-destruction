import SwiftUI

struct MainMenuView: View {
    let onPlay: () -> Void
    let onSettings: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            SpaceBackdrop()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                MenuOrb(size: 140)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 6) {
                    Text("COSMIC")
                        .font(Theme.display(40))
                        .tracking(6)
                    Text("DESTRUCTION")
                        .font(Theme.display(30))
                        .tracking(5)
                }
                .foregroundStyle(
                    LinearGradient(colors: [.white, Theme.cyan], startPoint: .top, endPoint: .bottom)
                )
                .neonGlow(Theme.cyan, radius: 14)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

                Text("Cnmbuck Studios")
                    .font(Theme.label(13))
                    .tracking(4)
                    .foregroundStyle(Theme.purple)
                    .neonGlow(Theme.purple, radius: 6)
                    .padding(.top, 14)

                Spacer()

                VStack(spacing: 16) {
                    Button("PLAY", action: onPlay)
                        .buttonStyle(NeonButtonStyle())
                    Button("SETTINGS", action: onSettings)
                        .buttonStyle(NeonButtonStyle(color: Theme.purple, filled: false))
                }
                .padding(.horizontal, 40)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 30)

                Spacer(minLength: 50)
            }
            .padding(.horizontal, 16)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { appeared = true }
        }
    }
}
