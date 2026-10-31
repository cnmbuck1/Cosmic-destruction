import SwiftUI

struct LevelSelectView: View {
    let onSelect: (Int) -> Void
    let onBack: () -> Void

    @EnvironmentObject private var progress: ProgressStore

    var body: some View {
        ZStack {
            SpaceBackdrop()
            VStack(spacing: 18) {
                HStack {
                    HUDIconButton(systemName: "chevron.left", action: onBack)
                    Spacer()
                }
                Text("SELECT LEVEL")
                    .font(Theme.display(24))
                    .tracking(4)
                    .foregroundStyle(.white)
                    .neonGlow()
                    .padding(.bottom, 8)

                ForEach(Array(Levels.all.enumerated()), id: \.element.id) { index, level in
                    let unlocked = progress.isUnlocked(index: index)
                    Button {
                        if unlocked { onSelect(index) }
                    } label: {
                        LevelCard(level: level, index: index, unlocked: unlocked,
                                  stars: progress.stars(forLevelID: level.id))
                    }
                    .buttonStyle(.plain)
                    .disabled(!unlocked)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

private struct LevelCard: View {
    let level: LevelDefinition
    let index: Int
    let unlocked: Bool
    let stars: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(index + 1)")
                .font(Theme.display(30))
                .foregroundStyle(unlocked ? Theme.cyan : Theme.textDim)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(level.name.uppercased())
                    .font(Theme.label(16))
                    .tracking(2)
                    .foregroundStyle(unlocked ? .white : Theme.textDim)
                Text("\(level.difficulty) · \(level.targetBlockCount) targets · \(level.maxShots) shots")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if unlocked {
                StarRow(stars: stars, size: 14)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(unlocked ? Theme.cyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .opacity(unlocked ? 1 : 0.6)
    }
}
