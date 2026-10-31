import Foundation

/// Physical/visual archetype of a block.
enum BlockKind: String, CaseIterable {
    /// Metallic stone, medium weight.
    case standard
    /// Darker, heavier, harder to displace.
    case heavy
    /// Glowing accents. Behaves like a standard block for now; reserved for
    /// future special mechanics (e.g. chain reactions).
    case energy
}

/// One block in a hand-authored structure. Positions are block centers in
/// meters, relative to the structure origin (platform top surface, at the
/// level's `structureOrigin`).
struct BlockSpec: Equatable {
    var center: SIMD3<Float>
    var size: SIMD3<Float>
    var kind: BlockKind = .standard
    /// Target blocks count toward the objective. Non-target blocks are
    /// decorative (e.g. foundations) and are tracked separately.
    var isTarget: Bool = true
}

/// Engine-agnostic description of a level.
struct LevelDefinition: Identifiable, Equatable {
    let id: Int
    let name: String
    let tagline: String
    let difficulty: String
    /// Vertical gravity in m/s² (negative = down).
    let gravity: Float
    let maxShots: Int
    /// Fraction (0...1) of target blocks that must be removed.
    let victoryThreshold: Float
    /// Max shots used to earn 3, 2 and 1 stars respectively.
    let starShotThresholds: [Int]
    /// Where the structure origin sits on the platform.
    let structureOrigin: SIMD3<Float>
    let blocks: [BlockSpec]

    var targetBlockCount: Int { blocks.filter(\.isTarget).count }

    /// Stars earned for completing the level with `shotsUsed` shots.
    func stars(forShotsUsed shotsUsed: Int) -> Int {
        for (index, limit) in starShotThresholds.enumerated() where shotsUsed <= limit {
            return 3 - index
        }
        return 1
    }
}
