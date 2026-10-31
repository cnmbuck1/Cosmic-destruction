import SceneKit
import UIKit
import simd

/// Builds destructible structures from level data and tracks every block:
/// structural displacement, abyss removal, velocity safety clamps, the
/// high-energy impact, and abyss fade-out/cleanup (via AbyssCleanupManager).
@MainActor
final class StructureManager {
    final class Block {
        let node: SCNNode
        /// Child holding the geometry, scaled during the abyss fade (scaling a
        /// physics node directly would disturb the simulation).
        let visual: SCNNode
        let spec: BlockSpec
        let startPosition: SIMD3<Float>
        /// The block's up axis when placed, for the tilt test.
        let startUp: SIMD3<Float>
        var isRemoved = false
        var isDisplaced = false
        var isGone = false
        var hasTrail = false

        init(node: SCNNode, visual: SCNNode, spec: BlockSpec, startPosition: SIMD3<Float>) {
            self.node = node
            self.visual = visual
            self.spec = spec
            self.startPosition = startPosition
            startUp = node.simdOrientation.act(SIMD3<Float>(0, 1, 0))
        }

        var isTarget: Bool { spec.isTarget }
    }

    private weak var parent: SCNNode?
    private(set) var blocks: [Block] = []
    private var byNode: [ObjectIdentifier: Block] = [:]
    private var stabilized = false
    private var cleanup = AbyssCleanupManager(config: DestructionPhysicsConfig())

    // Geometry/shape caches keyed by kind and size, so identical blocks share them.
    private var geometryCache: [String: SCNGeometry] = [:]
    private var shapeCache: [String: SCNPhysicsShape] = [:]

    /// Reference volume for the configured block masses: a 0.8 m cube.
    static let referenceVolume: Float = 0.8 * 0.8 * 0.8

    init(parent: SCNNode) {
        self.parent = parent
    }

    // MARK: Building

    func build(level: LevelDefinition, tuning: PhysicsTuning) {
        clear()
        cleanup = AbyssCleanupManager(config: tuning)
        let origin = level.structureOrigin
        for spec in level.blocks {
            let position = origin + spec.center
            let node = SCNNode()
            node.name = "block"
            node.simdPosition = position
            if spec.yaw != 0 {
                node.simdOrientation = simd_quatf(angle: spec.yaw, axis: SIMD3<Float>(0, 1, 0))
            }

            let visual = SCNNode(geometry: geometry(for: spec))
            node.addChildNode(visual)

            let body = SCNPhysicsBody(type: .dynamic, shape: physicsShape(for: spec))
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

    private func key(for spec: BlockSpec) -> String {
        "\(spec.kind.rawValue)-\(spec.size.x)x\(spec.size.y)x\(spec.size.z)"
    }

    private func geometry(for spec: BlockSpec) -> SCNGeometry {
        let key = key(for: spec) + "-\(spec.isTarget)"
        if let cached = geometryCache[key] { return cached }
        let geometry: SCNGeometry
        switch spec.kind {
        case .wedge:
            geometry = Self.wedgeGeometry(size: spec.size)
        default:
            let chamfer: CGFloat = spec.kind == .column ? 0.02 : 0.03
            geometry = SCNBox(width: CGFloat(spec.size.x), height: CGFloat(spec.size.y),
                              length: CGFloat(spec.size.z), chamferRadius: chamfer)
        }
        geometry.materials = [MaterialLibrary.shared.blockMaterial(kind: spec.kind, isTarget: spec.isTarget)]
        geometryCache[key] = geometry
        return geometry
    }

    /// Triangular prism: a triangle in the XY plane (base width × height),
    /// extruded along Z (depth), centered on its bounding box.
    static func wedgeGeometry(size: SIMD3<Float>, chamfer: CGFloat = 0.02) -> SCNShape {
        let w = CGFloat(size.x), h = CGFloat(size.y)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -w / 2, y: -h / 2))
        path.addLine(to: CGPoint(x: w / 2, y: -h / 2))
        path.addLine(to: CGPoint(x: 0, y: h / 2))
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: CGFloat(size.z))
        shape.chamferRadius = chamfer
        return shape
    }

    private func physicsShape(for spec: BlockSpec) -> SCNPhysicsShape {
        let key = key(for: spec)
        if let cached = shapeCache[key] { return cached }
        let shape: SCNPhysicsShape
        switch spec.kind {
        case .wedge:
            shape = SCNPhysicsShape(geometry: Self.wedgeGeometry(size: spec.size, chamfer: 0), options: [
                SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.convexHull,
            ])
        default:
            // Physics uses a sharp box; the visual chamfer is cosmetic only.
            shape = SCNPhysicsShape(geometry: SCNBox(width: CGFloat(spec.size.x), height: CGFloat(spec.size.y),
                                                     length: CGFloat(spec.size.z), chamferRadius: 0), options: nil)
        }
        shapeCache[key] = shape
        return shape
    }

    // MARK: Tuning

    func apply(tuning: PhysicsTuning) {
        cleanup = AbyssCleanupManager(config: tuning)
        for block in blocks where !block.isGone { apply(tuning: tuning, to: block) }
        setStabilized(stabilized, tuning: tuning)
    }

    static func mass(for spec: BlockSpec, tuning: PhysicsTuning) -> Float {
        let density = spec.kind.isHeavy ? tuning.heavyBlockMass : tuning.standardBlockMass
        return max(0.12, density * spec.kind.densityMultiplier * spec.volume / referenceVolume)
    }

    private func apply(tuning: PhysicsTuning, to block: Block) {
        guard let body = block.node.physicsBody else { return }
        body.mass = CGFloat(Self.mass(for: block.spec, tuning: tuning))
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

    // MARK: High-energy impact (build 3.0 §3)

    /// Applies the tunable high-energy impact around an orb hit. Each block
    /// within the preset radius gets a velocity change along the orb's
    /// *incoming* direction plus horizontal radial scatter and upward lift,
    /// scaled by distance falloff and the hit's energy (0.3...1.2, where 1 is a
    /// full-speed first hit). The struck block counts as distance 0. Heavier
    /// blocks resist a little. Blocks also get tumble about the axis
    /// perpendicular to their push. Returns how many blocks were pushed.
    @discardableResult
    func applyImpact(at center: SIMD3<Float>, incomingDirection: SIMD3<Float>, energy: Float,
                     struck: Block?, preset: ImpactPreset) -> Int {
        let radius = max(0.1, preset.radius)
        var forward = incomingDirection
        forward.y = max(forward.y, -0.2)
        forward = simd_length(forward) > 0.001 ? simd_normalize(forward) : SIMD3<Float>(0, 0, -1)
        var pushed = 0
        for block in blocks where !block.isGone && !block.isRemoved {
            guard let body = block.node.physicsBody else { continue }
            let p = block.node.presentation.simdWorldPosition
            let offset = p - center
            let distance = block === struck ? 0 : simd_length(offset)
            guard distance < radius else { continue }
            let falloff = powf(1 - distance / radius, preset.falloffExponent)

            var radial = SIMD3<Float>(offset.x, 0, offset.z)
            if simd_length(radial) < 0.001 { radial = SIMD3<Float>(forward.x, 0, forward.z) }
            radial = simd_length(radial) > 0.001 ? simd_normalize(radial) : SIMD3<Float>(0, 0, -1)
            var direction = forward * preset.forwardWeight + radial * preset.radialWeight
            direction.y += preset.upwardWeight
            direction = simd_normalize(direction)

            let mass = Float(body.mass)
            let resist = powf(0.55 / max(mass, 0.01), 0.2).clamped(0.6, 1.15)
            let dv = min(preset.velocityChange * energy * falloff * resist, preset.maxVelocityChange)
            guard dv >= 0.2 else { continue }
            // An impulse of mass × dv gives exactly dv and wakes a resting body.
            body.applyForce(SCNVector3(simd: direction * (dv * mass)), asImpulse: true)

            // Tumble about the axis perpendicular to the push.
            var axis = SIMD3<Float>(direction.z, 0, -direction.x)
            axis = simd_length(axis) > 0.01 ? simd_normalize(axis) : SIMD3<Float>(1, 0, 0)
            let w = preset.spin * falloff * energy * Float.random(in: 0.6...1.4)
            let current = body.angularVelocity
            let currentVector = SIMD3<Float>(current.x, current.y, current.z) * current.w
            let spin = currentVector + SIMD3<Float>(axis.x * w, Float.random(in: -0.25...0.25) * w, axis.z * w)
            let speed = simd_length(spin)
            if speed > 0.001 {
                let n = spin / speed
                body.angularVelocity = SCNVector4(x: n.x, y: n.y, z: n.z, w: speed)
            }
            pushed += 1
        }
        return pushed
    }

    // MARK: Per-frame

    struct UpdateResult {
        var newlyRemovedTargets = 0
        var newlyDisplacedTargets = 0
    }

    /// Updates removal, displacement, velocity clamps, and abyss fade/cleanup.
    func update(tuning: PhysicsTuning) -> UpdateResult {
        var result = UpdateResult()
        let maxSpeed = tuning.maxBlockVelocity
        for block in blocks where !block.isGone {
            let p = block.node.presentation.simdWorldPosition

            // Safety clamp: never let a block exceed the configured speed.
            if let body = block.node.physicsBody {
                let v = body.velocity.asSIMD
                let speed = simd_length(v)
                if speed > maxSpeed {
                    body.velocity = SCNVector3(simd: v * (maxSpeed / speed))
                }
            }

            // Structural destruction (build 3.0 §5): moved well away from its
            // slot, or tipped over. Small nudges don't count.
            if !block.isDisplaced {
                let up = block.node.presentation.simdWorldOrientation.act(SIMD3<Float>(0, 1, 0))
                let tilt = acosf(simd_dot(up, block.startUp).clamped(-1, 1)) * 180 / .pi
                if simd_distance(p, block.startPosition) > tuning.scoring.displacedDistance
                    || tilt > tuning.scoring.displacedTiltDegrees {
                    block.isDisplaced = true
                    if block.isTarget { result.newlyDisplacedTargets += 1 }
                }
            }

            if !block.isRemoved {
                let outOfArea = abs(p.x) > GameRules.playAreaHalfExtent || abs(p.z) > GameRules.playAreaHalfExtent
                if p.y < GameRules.removalPlaneY || outOfArea {
                    block.isRemoved = true
                    if block.isTarget { result.newlyRemovedTargets += 1 }
                }
            }

            switch cleanup.verdict(for: p) {
            case .keep:
                break
            case .fade(let t):
                block.node.opacity = CGFloat(1 - t)
                block.visual.simdScale = SIMD3<Float>(repeating: 1 - 0.6 * t)
            case .remove:
                block.isGone = true
                block.node.removeAllParticleSystems()
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
    var remainingTargetCount: Int { targetCount - destroyedTargetCount }
    var displacedCount: Int { blocks.filter(\.isDisplaced).count }
    var fallenCount: Int { blocks.filter(\.isRemoved).count }
    /// Targets structurally destroyed: displaced, tipped over, or fallen.
    var destroyedTargetCount: Int { blocks.filter { $0.isTarget && ($0.isDisplaced || $0.isRemoved) }.count }
    /// Targets launched off the island into the abyss (scored separately as a bonus).
    var abyssTargetCount: Int { removedTargetCount }

    /// Objective progress (build 3.0 §5): fraction of targets structurally
    /// destroyed (0...1), not just the ones that fell off.
    var progress: Float {
        let total = targetCount
        return total == 0 ? 0 : Float(destroyedTargetCount) / Float(total)
    }

    /// Running score: displaced targets plus the abyss bonus.
    func score(scoring: ScoringConfig) -> Int {
        destroyedTargetCount * scoring.pointsPerDisplaced + abyssTargetCount * scoring.pointsPerAbyss
    }

    var activeBodyCount: Int { blocks.filter { !$0.isGone }.count }

    /// Blocks still in the scene, for effects such as debris trails.
    var activeBlocks: [Block] { blocks.filter { !$0.isGone } }

    /// Fastest speed among blocks still on (or near) the platform.
    func maxSpeedOnPlatform() -> Float {
        var fastest: Float = 0
        for block in blocks where !block.isGone && !block.isRemoved {
            guard let body = block.node.physicsBody else { continue }
            fastest = max(fastest, simd_length(body.velocity.asSIMD))
        }
        return fastest
    }

    /// True when no block still on (or near) the platform is moving faster
    /// than the threshold. Blocks already falling into the abyss are ignored.
    func isSettled(threshold: Float) -> Bool {
        maxSpeedOnPlatform() <= threshold
    }

    func clear() {
        blocks.forEach { $0.node.removeFromParentNode() }
        blocks.removeAll()
        byNode.removeAll()
    }
}
