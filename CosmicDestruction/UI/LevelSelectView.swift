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

                // Grouped by world (build 5): 10 levels per planet. Planets
                // without levels yet are listed as coming soon.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Array(WorldTheme.all.enumerated()), id: \.element.key) { w, world in
                            let first = w * WorldTheme.levelsPerWorld
                            let last = min(first + WorldTheme.levelsPerWorld, Levels.all.count)
                            WorldHeader(world: world, range: first < last ? (first + 1)...last : nil)
                            if first < last {
                                ForEach(first..<last, id: \.self) { index in
                                    let level = Levels.all[index]
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
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

private struct WorldHeader: View {
    let world: WorldTheme
    let range: ClosedRange<Int>?

    var body: some View {
        let tint = Color(red: Double(world.veins[0].x), green: Double(world.veins[0].y), blue: Double(world.veins[0].z))
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("WORLD \(world.number) · \(world.name.uppercased())")
                    .font(Theme.label(13))
                    .tracking(2.5)
                    .foregroundStyle(tint)
                Spacer()
                Text(range.map { "Levels \($0.lowerBound)–\($0.upperBound)" } ?? "Coming soon")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDim)
            }
            Rectangle().fill(tint.opacity(0.7)).frame(height: 1)
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
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
