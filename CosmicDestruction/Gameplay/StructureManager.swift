import SceneKit
import UIKit
import simd

/// Builds destructible structures from level data and tracks every block:
/// target removal, displacement, velocity safety clamps, the supplemental
/// radial impulse, and abyss fade-out/cleanup (via AbyssCleanupManager).
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
        var hasTrail = false

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
        return max(0.12, density * spec.volume / referenceVolume)
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

    // MARK: Destruction impulses (§4.4)

    /// Supplemental radial impulse around an impact point. Pushes nearby
    /// blocks away from the impact with quadratic distance falloff, leaning
    /// along the shot direction and slightly upward. Impulses scale with block
    /// mass (so light pieces don't rocket away) and are clamped.
    /// Returns how many blocks were pushed.
    @discardableResult
    func applyRadialImpulse(at center: SIMD3<Float>, shotDirection: SIMD3<Float>, tuning: PhysicsTuning) -> Int {
        let radius = max(0.1, tuning.radialImpulseRadius)
        var forward = SIMD3<Float>(shotDirection.x, 0, shotDirection.z)
        forward = simd_length(forward) > 0.001 ? simd_normalize(forward) : SIMD3<Float>(0, 0, -1)
        var pushed = 0
        for block in blocks where !block.isGone && !block.isRemoved {
            guard let body = block.node.physicsBody else { continue }
            let p = block.node.presentation.simdWorldPosition
            let offset = p - center
            let distance = simd_length(offset)
            guard distance < radius else { continue }
            let falloff = (1 - distance / radius) * (1 - distance / radius)

            var radial = SIMD3<Float>(offset.x, 0, offset.z)
            radial = simd_length(radial) > 0.001 ? simd_normalize(radial) : forward
            let bias = tuning.forwardBias.clamped(0, 1)
            var horizontal = radial * (1 - bias) + forward * bias
            horizontal = simd_length(horizontal) > 0.001 ? simd_normalize(horizontal) : forward
            let up = tuning.verticalImpulseComponent.clamped(0, 1)
            let direction = simd_normalize(horizontal * (1 - up) + SIMD3<Float>(0, up, 0))

            let mass = Float(body.mass)
            let magnitude = min(tuning.radialImpulseStrength * falloff * mass, tuning.maxSupplementalImpulse)
            guard magnitude > 0.01 else { continue }
            body.applyForce(SCNVector3(simd: direction * magnitude), asImpulse: true)
            // A small spin makes debris tumble instead of sliding.
            body.applyTorque(SCNVector4(x: direction.z, y: 0, z: -direction.x, w: magnitude * 0.08), asImpulse: true)
            pushed += 1
        }
        return pushed
    }

    /// Extra push on the directly struck block, along the orb's travel.
    func applyDirectHit(on block: Block, direction: SIMD3<Float>, contactImpulse: Float, tuning: PhysicsTuning) {
        guard let body = block.node.physicsBody, tuning.orbImpulseMultiplier > 1 else { return }
        let extra = min((tuning.orbImpulseMultiplier - 1) * contactImpulse, tuning.maxSupplementalImpulse)
        guard extra > 0.01, simd_length(direction) > 0.001 else { return }
        body.applyForce(SCNVector3(simd: simd_normalize(direction) * extra), asImpulse: true)
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
    var remainingTargetCount: Int { targetCount - removedTargetCount }
    var displacedCount: Int { blocks.filter(\.isDisplaced).count }
    var fallenCount: Int { blocks.filter(\.isRemoved).count }

    /// Fraction of target blocks removed (0...1).
    var progress: Float {
        let total = targetCount
        return total == 0 ? 0 : Float(removedTargetCount) / Float(total)
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
