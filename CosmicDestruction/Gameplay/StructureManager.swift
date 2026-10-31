import SceneKit
import simd

/// Builds destructible structures from level data and tracks every block:
/// target removal, displacement, abyss fade-out and cleanup.
@MainActor
final class StructureManager {
    final class Block {
        let node: SCNNode
        /// Child holding the geometry, scaled during the abyss fade (scaling a
        /// physics node directly would disturb the simulation).
        let visual: SCNNode
        let spec: BlockSpec
        let startPosition: SIMD3<Float>
        var isRemoved = false
        var isDisplaced = false
        var isGone = false

        init(node: SCNNode, visual: SCNNode, spec: BlockSpec, startPosition: SIMD3<Float>) {
            self.node = node
            self.visual = visual
            self.spec = spec
            self.startPosition = startPosition
        }

        var isTarget: Bool { spec.isTarget }
    }

    private weak var parent: SCNNode?
    private(set) var blocks: [Block] = []
    private var byNode: [ObjectIdentifier: Block] = [:]
    private var stabilized = false

    // Geometry/shape caches keyed by size, so identical blocks share them.
    private var geometryCache: [String: SCNBox] = [:]
    private var shapeCache: [String: SCNPhysicsShape] = [:]

    init(parent: SCNNode) {
        self.parent = parent
    }

    // MARK: Building

    func build(level: LevelDefinition, tuning: PhysicsTuning) {
        clear()
        let origin = level.structureOrigin
        for spec in level.blocks {
            let position = origin + spec.center
            let node = SCNNode()
            node.name = "block"
            node.simdPosition = position

            let visual = SCNNode(geometry: geometry(for: spec))
            node.addChildNode(visual)

            let body = SCNPhysicsBody(type: .dynamic, shape: physicsShape(for: spec.size))
            body.categoryBitMask = PhysicsCategory.block
            body.collisionBitMask = PhysicsCategory.block | PhysicsCategory.orb | PhysicsCategory.platform
            body.contactTestBitMask = PhysicsCategory.block | PhysicsCategory.platform
            body.allowsResting = true
            node.physicsBody = body

            let block = Block(node: node, visual: visual, spec: spec, startPosition: position)
            apply(tuning: tuning, to: block)
            blocks.append(block)
            byNode[ObjectIdentifier(node)] = block
            parent?.addChildNode(node)
        }
        setStabilized(true, tuning: tuning)
    }

    private func geometry(for spec: BlockSpec) -> SCNBox {
        let key = "\(spec.size.x)x\(spec.size.y)x\(spec.size.z)-\(spec.kind.rawValue)-\(spec.isTarget)"
        if let cached = geometryCache[key] { return cached }
        let box = SCNBox(width: CGFloat(spec.size.x), height: CGFloat(spec.size.y),
                         length: CGFloat(spec.size.z), chamferRadius: 0.025)
        box.materials = [MaterialLibrary.shared.blockMaterial(kind: spec.kind, isTarget: spec.isTarget)]
        geometryCache[key] = box
        return box
    }

    private func physicsShape(for size: SIMD3<Float>) -> SCNPhysicsShape {
        let key = "\(size.x)x\(size.y)x\(size.z)"
        if let cached = shapeCache[key] { return cached }
        // Physics uses a sharp box; the visual chamfer is cosmetic only.
        let shape = SCNPhysicsShape(geometry: SCNBox(width: CGFloat(size.x), height: CGFloat(size.y),
                                                      length: CGFloat(size.z), chamferRadius: 0), options: nil)
        shapeCache[key] = shape
        return shape
    }

    // MARK: Tuning

    func apply(tuning: PhysicsTuning) {
        for block in blocks where !block.isGone { apply(tuning: tuning, to: block) }
        setStabilized(stabilized, tuning: tuning)
    }

    private func apply(tuning: PhysicsTuning, to block: Block) {
        guard let body = block.node.physicsBody else { return }
        let volume = block.spec.size.x * block.spec.size.y * block.spec.size.z
        let cubeVolume: Float = 0.9 * 0.9 * 0.9
        let multiplier = block.spec.kind == .heavy ? tuning.heavyMassMultiplier : 1
        body.mass = CGFloat(tuning.blockMass * multiplier * max(0.5, volume / cubeVolume))
        body.friction = CGFloat(tuning.blockFriction)
        body.restitution = CGFloat(tuning.blockRestitution)
        body.rollingFriction = 0.02
    }

    /// While stabilized, heavy damping keeps the stack perfectly still before
    /// the first shot. Released the moment the player fires.
    func setStabilized(_ on: Bool, tuning: PhysicsTuning) {
        stabilized = on
        for block in blocks where !block.isGone {
            guard let body = block.node.physicsBody else { continue }
            body.damping = CGFloat(on ? tuning.stabilizerDamping : tuning.blockLinearDamping)
            body.angularDamping = CGFloat(on ? tuning.stabilizerDamping : tuning.blockAngularDamping)
        }
    }

    // MARK: Per-frame

    struct UpdateResult {
        var newlyRemovedTargets = 0
        var newlyDisplacedTargets = 0
    }

    /// Updates removal, displacement, and abyss fade/cleanup.
    func update() -> UpdateResult {
        var result = UpdateResult()
        for block in blocks where !block.isGone {
            let p = block.node.presentation.simdWorldPosition

            if !block.isDisplaced, simd_distance(p, block.startPosition) > GameRules.blockDisplacedDistance {
                block.isDisplaced = true
                if block.isTarget { result.newlyDisplacedTargets += 1 }
            }

            if !block.isRemoved {
                let outOfArea = abs(p.x) > GameRules.playAreaHalfExtent || abs(p.z) > GameRules.playAreaHalfExtent
                if p.y < GameRules.removalPlaneY || outOfArea {
                    block.isRemoved = true
                    if block.isTarget { result.newlyRemovedTargets += 1 }
                }
            }

            // Abyss: keep simulating, then fade and shrink gradually well below
            // the platform so nothing pops out of existence near the edge.
            if p.y < GameRules.abyssFadeStartY {
                let t = ((GameRules.abyssFadeStartY - p.y) / (GameRules.abyssFadeStartY - GameRules.abyssCleanupY)).clamped(0, 1)
                block.node.opacity = CGFloat(1 - t)
                let s = 1 - 0.6 * t
                block.visual.simdScale = SIMD3<Float>(repeating: s)
            }
            if p.y < GameRules.abyssCleanupY || abs(p.x) > 60 || abs(p.z) > 60 {
                block.isGone = true
                block.node.removeFromParentNode()
                byNode[ObjectIdentifier(block.node)] = nil
            }
        }
        return result
    }

    // MARK: Queries

    func block(for node: SCNNode) -> Block? { byNode[ObjectIdentifier(node)] }

    var targetCount: Int { blocks.filter(\.isTarget).count }
    var removedTargetCount: Int { blocks.filter { $0.isTarget && $0.isRemoved }.count }
    var remainingTargetCount: Int { targetCount - removedTargetCount }

    /// Fraction of target blocks removed (0...1).
    var progress: Float {
        let total = targetCount
        return total == 0 ? 0 : Float(removedTargetCount) / Float(total)
    }

    var activeBodyCount: Int { blocks.filter { !$0.isGone }.count }

    /// True when no block still on (or near) the platform is moving faster
    /// than the threshold. Blocks already falling into the abyss are ignored.
    func isSettled(threshold: Float) -> Bool {
        for block in blocks where !block.isGone && !block.isRemoved {
            guard let body = block.node.physicsBody else { continue }
            if simd_length(body.velocity.asSIMD) > threshold { return false }
        }
        return true
    }

    func clear() {
        blocks.forEach { $0.node.removeFromParentNode() }
        blocks.removeAll()
        byNode.removeAll()
    }
}
