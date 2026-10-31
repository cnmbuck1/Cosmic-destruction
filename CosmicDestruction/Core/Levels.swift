import Foundation

/// The three hand-designed prototype levels. Block positions are fully
/// deterministic; there is no procedural generation.
enum Levels {
    static let all: [LevelDefinition] = [firstImpact, twinTowers, lunarFortress]

    // Small vertical gap so blocks never start interpenetrating (which makes
    // rigid-body stacks jump at load). Blocks drop a few millimeters and rest.
    private static let gap: Float = 0.004
    private static let cube: Float = 0.9

    // MARK: Level 1 — First Impact

    /// Simple 2x2 tower, five layers high (20 blocks). The glowing middle
    /// layer marks the central weak point.
    static let firstImpact: LevelDefinition = {
        var blocks: [BlockSpec] = []
        let step = cube + gap
        for layer in 0..<5 {
            let y = gap + cube / 2 + Float(layer) * step
            let kind: BlockKind = layer == 2 ? .energy : .standard
            for x in [-0.455, 0.455] as [Float] {
                for z in [-0.455, 0.455] as [Float] {
                    blocks.append(BlockSpec(center: [x, y, z], size: [cube, cube, cube], kind: kind))
                }
            }
        }
        return LevelDefinition(
            id: 1,
            name: "First Impact",
            tagline: "Drag to aim. Release to fire.",
            difficulty: "Easy",
            gravity: -13,
            maxShots: 3,
            victoryThreshold: 0.8,
            starShotThresholds: [1, 2, 3],
            structureOrigin: [0, 0, -4.0],
            blocks: blocks
        )
    }()

    // MARK: Level 2 — Twin Towers

    /// Two 2x2x3 towers (heavy base layer) joined by a heavy bridge with a row
    /// of four blocks on top. 30 blocks.
    static let twinTowers: LevelDefinition = {
        var blocks: [BlockSpec] = []
        let step = cube + gap
        for towerX in [-1.8, 1.8] as [Float] {
            for layer in 0..<3 {
                let y = gap + cube / 2 + Float(layer) * step
                let kind: BlockKind = layer == 0 ? .heavy : .standard
                for dx in [-0.455, 0.455] as [Float] {
                    for z in [-0.455, 0.455] as [Float] {
                        blocks.append(BlockSpec(center: [towerX + dx, y, z], size: [cube, cube, cube], kind: kind))
                    }
                }
            }
        }
        let towerTop = 3 * step
        let beam = SIMD3<Float>(4.6, 0.45, cube)
        let beamY = towerTop + gap + beam.y / 2
        for z in [-0.455, 0.455] as [Float] {
            blocks.append(BlockSpec(center: [0, beamY, z], size: beam, kind: .heavy))
        }
        let topY = towerTop + gap + beam.y + gap + cube / 2
        for x in [-1.365, -0.455, 0.455, 1.365] as [Float] {
            blocks.append(BlockSpec(center: [x, topY, 0], size: [cube, cube, cube], kind: .energy))
        }
        return LevelDefinition(
            id: 2,
            name: "Twin Towers",
            tagline: "Find the weak link between them.",
            difficulty: "Moderate",
            gravity: -13,
            maxShots: 3,
            victoryThreshold: 0.8,
            starShotThresholds: [1, 2, 3],
            structureOrigin: [0, 0, -4.0],
            blocks: blocks
        )
    }()

    // MARK: Level 3 — Lunar Fortress

    /// Wide decorative foundation (12 slabs, not targets), four supporting
    /// columns (18 blocks), a heavy elevated deck (2 beams) and a glowing
    /// central keep (8 blocks). 40 blocks, 28 targets.
    static let lunarFortress: LevelDefinition = {
        var blocks: [BlockSpec] = []
        let step = cube + gap

        // Foundation: 6 x 2 heavy slabs. Decorative, so not counted as targets.
        let slab = SIMD3<Float>(1.0, 0.5, 1.0)
        for i in 0..<6 {
            let x = (Float(i) - 2.5) * 1.01
            for z in [-0.505, 0.505] as [Float] {
                blocks.append(BlockSpec(center: [x, gap + slab.y / 2, z], size: slab, kind: .heavy, isTarget: false))
            }
        }
        let foundationTop = gap + slab.y

        // Outer columns: two stacks each side, three high.
        for x in [-2.5, 2.5] as [Float] {
            for z in [-0.5, 0.5] as [Float] {
                for layer in 0..<3 {
                    let y = foundationTop + gap + cube / 2 + Float(layer) * step
                    blocks.append(BlockSpec(center: [x, y, z], size: [cube, cube, cube]))
                }
            }
        }
        // Inner columns: single stacks — the strategic weak points.
        for x in [-1.0, 1.0] as [Float] {
            for layer in 0..<3 {
                let y = foundationTop + gap + cube / 2 + Float(layer) * step
                blocks.append(BlockSpec(center: [x, y, 0], size: [cube, cube, cube]))
            }
        }
        let columnTop = foundationTop + 3 * step

        // Elevated deck: two long heavy beams.
        let beam = SIMD3<Float>(6.0, 0.45, cube)
        for z in [-0.5, 0.5] as [Float] {
            blocks.append(BlockSpec(center: [0, columnTop + gap + beam.y / 2, z], size: beam, kind: .heavy))
        }
        let deckTop = columnTop + gap + beam.y

        // Central keep: 2x2x2 energy blocks.
        for layer in 0..<2 {
            let y = deckTop + gap + cube / 2 + Float(layer) * step
            for x in [-0.455, 0.455] as [Float] {
                for z in [-0.455, 0.455] as [Float] {
                    blocks.append(BlockSpec(center: [x, y, z], size: [cube, cube, cube], kind: .energy))
                }
            }
        }

        return LevelDefinition(
            id: 3,
            name: "Lunar Fortress",
            tagline: "Low gravity. Strike the supports.",
            difficulty: "Challenging",
            gravity: -10,
            maxShots: 3,
            victoryThreshold: 0.8,
            starShotThresholds: [1, 2, 3],
            structureOrigin: [0, 0, -4.2],
            blocks: blocks
        )
    }()
}
