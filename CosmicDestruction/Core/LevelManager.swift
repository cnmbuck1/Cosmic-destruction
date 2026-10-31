import Foundation

/// Loads level configurations and answers questions about level order.
struct LevelManager {
    let levels: [LevelDefinition]

    init(levels: [LevelDefinition] = Levels.all) {
        self.levels = levels
    }

    var count: Int { levels.count }

    func level(at index: Int) -> LevelDefinition? {
        levels.indices.contains(index) ? levels[index] : nil
    }

    func hasLevel(after index: Int) -> Bool {
        levels.indices.contains(index + 1)
    }
}
