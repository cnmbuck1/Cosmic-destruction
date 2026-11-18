import Foundation

/// Structural component types (build sheet 2.0 §3.3).
enum BlockKind: String, CaseIterable {
    /// Primary structural element. Metallic stone, medium mass.
    case standard
    /// Long horizontal member for bridges and lintels.
    case beam
    /// Narrow vertical support: a key weak point.
    case column
    /// Larger, denser foundation/heavy block.
    case heavy
    /// Triangular prism for arches, roofs and pyramids.
    case wedge
    /// Glowing energy core. Important target; reserved for chain reactions later.
    case energy
    /// Dense armored block with a neon trim (build 4). Resists impacts and toppling.
    case reinforced
    /// Fixed shield wall (build 4). Never moves or counts; shots must arc over it.
    case barrier

    var isHeavy: Bool { self == .heavy }
    /// Barriers are static bodies: they block shots but are not destructible.
    var isStatic: Bool { self == .barrier }

    /// Density relative to the configured standard/heavy mass. Load-bearing
    /// columns are denser so stacks never sit heavy-on-light (which makes
    /// iterative physics solvers jitter).
    var densityMultiplier: Float {
        switch self {
        case .standard, .heavy: return 1
        case .beam: return 0.75
        case .column: return 2.5
        case .wedge: return 0.8
        case .energy: return 1.2
        case .reinforced: return 5
        case .barrier: return 1
        }
    }
}

/// Neon trim colors (build 4). Levels introduce them one by one; cyan is the original.
enum NeonColor: String, CaseIterable {
    case cyan, magenta, lime, amber, red, violet

    /// sRGB components 0...1.
    var rgb: SIMD3<Float> {
        switch self {
        case .cyan: return [0.2, 0.92, 1.0]
        case .magenta: return [1.0, 0.25, 0.75]
        case .lime: return [0.49, 1.0, 0.3]
        case .amber: return [1.0, 0.7, 0.18]
        case .red: return [1.0, 0.23, 0.31]
        case .violet: return [0.65, 0.4, 1.0]
        }
    }
}

/// One component in a hand-authored structure. Positions are centers in
/// meters relative to the level's `structureOrigin` (platform top = y 0).
/// For wedges, `size` is (base width, height, depth) of the triangular prism
/// and the center is the center of its bounding box.
struct BlockSpec: Equatable {
    var center: SIMD3<Float>
    var size: SIMD3<Float>
    var kind: BlockKind = .standard
    /// Target blocks count toward the objective. Non-target blocks are
    /// decorative (foundations) and are tracked separately.
    var isTarget: Bool = true
    /// Rotation around the vertical axis, in radians.
    var yaw: Float = 0
    /// Neon trim color; nil = plain metal (energy cores default to cyan).
    var neon: NeonColor? = nil

    /// Volume in m³ (wedges are half a box).
    var volume: Float {
        let box = size.x * size.y * size.z
        return kind == .wedge ? box * 0.5 : box
    }
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
    /// Fraction (0...1) of target blocks that must be structurally destroyed
    /// (displaced, tipped over, or fallen) to win.
    let victoryThreshold: Float
    /// Max shots used to earn 3, 2 and 1 stars respectively.
    let starShotThresholds: [Int]
    /// Where the structure origin sits on the platform.
    let structureOrigin: SIMD3<Float>
    let blocks: [BlockSpec]
    /// Extra camera pull-back for wide structures (meters).
    var cameraPullBack: Float = 0
    /// Starting cannon elevation, chosen so an un-aimed first shot still
    /// strikes the structure instead of sailing through an opening.
    var defaultElevation: Float = GameRules.defaultElevationDegrees

    var targetBlockCount: Int { blocks.filter(\.isTarget).count }

    /// Stars earned for completing the level with `shotsUsed` shots.
    func stars(forShotsUsed shotsUsed: Int) -> Int {
        for (index, limit) in starShotThresholds.enumerated() where shotsUsed <= limit {
            return 3 - index
        }
        return 1
    }
}
