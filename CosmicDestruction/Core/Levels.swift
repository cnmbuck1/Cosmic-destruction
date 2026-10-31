import Foundation

/// The three hand-designed levels (build sheet 2.0 §7; Level 1 redesigned in build 3.0). Positions are fully
/// deterministic; there is no procedural generation.
///
/// Every piece is placed with a small vertical gap (`g`) so rigid bodies
/// never start interpenetrating. Pieces drop a few millimeters and rest
/// during the stabilized settling period.
enum Levels {
    static let all: [LevelDefinition] = [lunarGateway, twinSpires, orbitalCitadel]

    private static let g: Float = 0.004

    /// Tiny helper that tracks stacking heights while authoring.
    private struct Builder {
        var blocks: [BlockSpec] = []

        /// Places a piece whose bottom sits at `base`; returns its top height.
        @discardableResult
        mutating func put(_ kind: BlockKind, _ size: SIMD3<Float>, x: Float, z: Float, base: Float,
                          target: Bool = true, yaw: Float = 0) -> Float {
            let y = base + g + size.y / 2
            blocks.append(BlockSpec(center: [x, y, z], size: size, kind: kind, isTarget: target, yaw: yaw))
            return base + g + size.y
        }
    }

    // MARK: Level 1 — Lunar Gateway

    /// Build 3.0: three separate pieces (left pylon, central gate, right
    /// pylon), so one direct hit wrecks one piece and maybe part of a
    /// neighbour, never the whole site. A new player needs about 2–3 shots for
    /// the 60% target. 24 pieces (21 targets).
    static let lunarGateway: LevelDefinition = {
        var b = Builder()
        // Pylons: twin stacked columns on a heavy plinth, a capital, a cube and a point.
        for x in [-2.3, 2.3] as [Float] {
            let plinth = b.put(.heavy, [1.2, 0.4, 1.2], x: x, z: 0, base: 0, target: false)
            var top: Float = 0
            for z in [-0.3, 0.3] as [Float] {
                let lower = b.put(.column, [0.4, 0.95, 0.4], x: x, z: z, base: plinth)
                top = b.put(.column, [0.4, 0.95, 0.4], x: x, z: z, base: lower)
            }
            let cap = b.put(.standard, [1.0, 0.3, 1.0], x: x, z: 0, base: top)
            let cube = b.put(.standard, [0.6, 0.6, 0.6], x: x, z: 0, base: cap)
            b.put(.wedge, [0.7, 0.45, 0.7], x: x, z: 0, base: cube)
        }
        // Central gate: two stacked column pairs carry a lintel, an energy core and a crown.
        let gateBase = b.put(.heavy, [1.5, 0.35, 1.0], x: 0, z: 0, base: 0, target: false)
        var gateTop: Float = 0
        for x in [-0.5, 0.5] as [Float] {
            let lower = b.put(.column, [0.4, 0.9, 0.4], x: x, z: 0, base: gateBase)
            gateTop = b.put(.column, [0.4, 0.9, 0.4], x: x, z: 0, base: lower)
        }
        let lintel = b.put(.beam, [1.6, 0.4, 0.8], x: 0, z: 0, base: gateTop)
        let coreTop = b.put(.energy, [0.65, 0.65, 0.65], x: 0, z: 0, base: lintel)
        b.put(.wedge, [0.8, 0.5, 0.7], x: 0, z: 0, base: coreTop)
        return LevelDefinition(
            id: 1,
            name: "Lunar Gateway",
            tagline: "Topple the gate and both pylons.",
            difficulty: "Easy",
            gravity: -9.5,
            maxShots: 5,
            victoryThreshold: 0.6,
            starShotThresholds: [2, 3, 5],
            structureOrigin: [0, 0, -3.4],
            blocks: b.blocks,
            defaultElevation: 5
        )
    }()

    // MARK: Level 2 — Twin Spires

    /// Two asymmetrical towers joined by a bridge. The tall spire stands on
    /// slender columns; the short one is a heavy block stack. 31 pieces (29 targets).
    static let twinSpires: LevelDefinition = {
        var b = Builder()

        // Tall spire (left): column cage, two caps, spire block and point.
        let ax: Float = -2.0
        let aBase = b.put(.heavy, [1.4, 0.5, 1.4], x: ax, z: 0, base: 0, target: false)
        var aTop: Float = 0
        for dx in [-0.45, 0.45] as [Float] {
            for z in [-0.45, 0.45] as [Float] {
                aTop = b.put(.column, [0.3, 1.2, 0.3], x: ax + dx, z: z, base: aBase)
            }
        }
        let aCap1 = b.put(.standard, [1.3, 0.3, 1.3], x: ax, z: 0, base: aTop)
        var aUpper: Float = 0
        for x in [-2.45, -1.95] as [Float] {
            for z in [-0.4, 0.4] as [Float] {
                aUpper = b.put(.column, [0.3, 1.1, 0.3], x: x, z: z, base: aCap1)
            }
        }
        let aCap2 = b.put(.standard, [0.9, 0.25, 1.1], x: -2.2, z: 0, base: aUpper)
        let spire = b.put(.standard, [0.6, 0.6, 0.6], x: -2.2, z: 0, base: aCap2)
        b.put(.wedge, [0.6, 0.6, 0.6], x: -2.2, z: 0, base: spire)

        // Short tower (right): heavy 2x2x2 stack, cap, point and two studs.
        let bx: Float = 2.0
        let bBase = b.put(.heavy, [1.4, 0.5, 1.4], x: bx, z: 0, base: 0, target: false)
        var layerBase = bBase
        for _ in 0..<2 {
            var top: Float = 0
            for dx in [-0.302, 0.302] as [Float] {
                for z in [-0.302, 0.302] as [Float] {
                    top = b.put(.heavy, [0.6, 0.6, 0.6], x: bx + dx, z: z, base: layerBase)
                }
            }
            layerBase = top
        }
        let bCap = b.put(.standard, [1.3, 0.3, 1.3], x: bx, z: 0, base: layerBase)
        b.put(.wedge, [0.6, 0.5, 0.6], x: 2.2, z: 0, base: bCap)
        for z in [-0.45, 0.45] as [Float] {
            b.put(.standard, [0.35, 0.35, 0.35], x: 2.45, z: z, base: bCap)
        }

        // Bridge: two beams across the caps, carrying a core and two blocks.
        let bridgeBase = max(aCap1, bCap)
        var deck: Float = 0
        for z in [-0.27, 0.27] as [Float] {
            deck = b.put(.beam, [3.4, 0.35, 0.5], x: 0, z: z, base: bridgeBase)
        }
        b.put(.energy, [0.6, 0.6, 0.6], x: 0, z: 0, base: deck)
        for x in [-0.9, 0.9] as [Float] {
            b.put(.standard, [0.5, 0.5, 0.5], x: x, z: 0, base: deck)
        }

        return LevelDefinition(
            id: 2,
            name: "Twin Spires",
            tagline: "Find the strike that drops both.",
            difficulty: "Moderate",
            gravity: -10,
            maxShots: 5,
            victoryThreshold: 0.7,
            starShotThresholds: [2, 3, 5],
            structureOrigin: [0, 0, -3.4],
            blocks: b.blocks,
            cameraPullBack: 0.3,
            defaultElevation: 8
        )
    }()

    // MARK: Level 3 — Orbital Citadel

    /// Broad foundation, four two-piece columns carrying an elevated deck with
    /// a glowing core keep, plus four corner bastions. 37 pieces (33 targets).
    static let orbitalCitadel: LevelDefinition = {
        var b = Builder()

        // Foundation plates (decorative, heavy).
        for x in [-1.32, 1.32] as [Float] {
            for z in [-0.82, 0.82] as [Float] {
                b.put(.heavy, [2.6, 0.4, 1.6], x: x, z: z, base: 0, target: false)
            }
        }
        let floor: Float = g + 0.4

        // Four support columns, two pieces each, centered under the deck beams
        // so each beam's center of mass sits over its supports.
        var columnTop: Float = 0
        for x in [-1.6, 1.6] as [Float] {
            for z in [-0.6, 0.6] as [Float] {
                let lower = b.put(.column, [0.45, 1.0, 0.45], x: x, z: z, base: floor)
                columnTop = b.put(.column, [0.45, 1.0, 0.45], x: x, z: z, base: lower)
            }
        }

        // Elevated deck.
        var deck: Float = 0
        for z in [-0.61, 0.61] as [Float] {
            deck = b.put(.beam, [3.8, 0.3, 1.2], x: 0, z: z, base: columnTop)
        }

        // Core keep: energy core, four guard blocks with wedge caps, crown.
        let coreTop = b.put(.energy, [0.7, 0.7, 0.7], x: 0, z: 0, base: deck)
        for x in [-0.75, 0.75] as [Float] {
            for z in [-0.55, 0.55] as [Float] {
                let guardTop = b.put(.standard, [0.5, 0.5, 0.5], x: x, z: z, base: deck)
                b.put(.wedge, [0.5, 0.4, 0.5], x: x, z: z, base: guardTop, yaw: .pi / 2)
            }
        }
        let crown = b.put(.standard, [0.9, 0.2, 0.9], x: 0, z: 0, base: coreTop)
        b.put(.wedge, [0.8, 0.5, 0.8], x: 0, z: 0, base: crown)

        // Corner bastions.
        for x in [-2.3, 2.3] as [Float] {
            for z in [-1.25, 1.25] as [Float] {
                let lower = b.put(.standard, [0.55, 0.55, 0.55], x: x, z: z, base: floor)
                let upper = b.put(.standard, [0.55, 0.55, 0.55], x: x, z: z, base: lower)
                b.put(.wedge, [0.55, 0.45, 0.55], x: x, z: z, base: upper)
            }
        }

        return LevelDefinition(
            id: 3,
            name: "Orbital Citadel",
            tagline: "Low gravity. Choose: supports or core.",
            difficulty: "Challenging",
            gravity: -9,
            maxShots: 5,
            victoryThreshold: 0.7,
            starShotThresholds: [2, 3, 5],
            structureOrigin: [0, 0, -3.1],
            blocks: b.blocks,
            cameraPullBack: 0.9,
            defaultElevation: 9
        )
    }()
}
