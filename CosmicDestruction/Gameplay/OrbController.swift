import SceneKit
import simd

/// Creates, tracks, and cleans up projectiles. Each orb has a unique id and is
/// tracked until it resolves (stops, leaves the arena, or times out).
@MainActor
final class OrbController {
    final class Orb {
        let id = UUID()
        let node: SCNNode
        let launchTime: TimeInterval
        let launchDirection: SIMD3<Float>
        var impactCount = 0
        /// Supplemental radial impulses triggered by this orb (capped per orb).
        var supplementalCount = 0
        var lastSupplementalTime: TimeInterval = -.infinity
        /// Velocity recorded at the end of the previous frame. SceneKit reports
        /// contacts after resolving them, so this is the orb's *incoming*
        /// velocity when a new contact arrives.
        var previousVelocity: SIMD3<Float> = .zero

        init(node: SCNNode, launchTime: TimeInterval, launchDirection: SIMD3<Float>) {
            self.node = node
            self.launchTime = launchTime
            self.launchDirection = launchDirection
        }
    }

    var visual: OrbVisual = SignatureOrbVisual()
    private weak var parent: SCNNode?
    private(set) var orbs: [Orb] = []
    private var byNode: [ObjectIdentifier: Orb] = [:]

    init(parent: SCNNode) {
        self.parent = parent
    }

    var activeCount: Int { orbs.count }

    /// Launches an orb and returns it.
    @discardableResult
    func launch(from origin: SIMD3<Float>, direction: SIMD3<Float>, tuning: PhysicsTuning, time: TimeInterval) -> Orb {
        // Prevent accumulation: drop the oldest orbs beyond the cap.
        while orbs.count >= GameRules.maxActiveOrbs, let oldest = orbs.first {
            remove(oldest)
        }

        let node = SCNNode()
        node.name = "orb"
        node.simdPosition = origin
        node.addChildNode(visual.makeNode(radius: tuning.orbRadius))

        let shape = SCNPhysicsShape(geometry: SCNSphere(radius: CGFloat(tuning.orbRadius)), options: nil)
        let body = SCNPhysicsBody(type: .dynamic, shape: shape)
        body.mass = CGFloat(tuning.orbMass)
        body.restitution = CGFloat(tuning.orbRestitution)
        body.friction = CGFloat(tuning.orbFriction)
        body.rollingFriction = 0.05
        body.damping = 0.02
        body.angularDamping = 0.3
        body.categoryBitMask = PhysicsCategory.orb
        body.collisionBitMask = PhysicsCategory.block | PhysicsCategory.platform
        body.contactTestBitMask = PhysicsCategory.block | PhysicsCategory.platform
        // Fast projectile: enable CCD so it never tunnels through thin blocks.
        body.continuousCollisionDetectionThreshold = CGFloat(tuning.orbRadius)
        body.velocity = SCNVector3(simd: direction * tuning.launchSpeed)
        node.physicsBody = body

        parent?.addChildNode(node)
        let orb = Orb(node: node, launchTime: time, launchDirection: direction)
        orb.previousVelocity = direction * tuning.launchSpeed
        orbs.append(orb)
        byNode[ObjectIdentifier(node)] = orb
        return orb
    }

    func orb(for node: SCNNode) -> Orb? { byNode[ObjectIdentifier(node)] }

    /// Call once per frame after contacts are processed.
    func recordVelocities() {
        for orb in orbs {
            if let v = orb.node.physicsBody?.velocity.asSIMD { orb.previousVelocity = v }
        }
    }

    /// Removes orbs that fell into the abyss or exceeded their lifetime.
    func update(time: TimeInterval) {
        for orb in orbs {
            let y = orb.node.presentation.simdWorldPosition.y
            if y < GameRules.orbCleanupY || time - orb.launchTime > GameRules.orbMaxLifetime {
                remove(orb)
            }
        }
    }

    /// True once the orb has stopped, fallen below the platform, or is gone.
    func isResolved(_ orb: Orb?, time: TimeInterval, settleSpeed: Float) -> Bool {
        guard let orb, byNode[ObjectIdentifier(orb.node)] != nil else { return true }
        let position = orb.node.presentation.simdWorldPosition
        if position.y < GameRules.removalPlaneY { return true }
        if abs(position.x) > GameRules.playAreaHalfExtent || abs(position.z) > GameRules.playAreaHalfExtent { return true }
        let speed = simd_length(orb.node.physicsBody?.velocity.asSIMD ?? .zero)
        return time - orb.launchTime > 0.6 && speed < settleSpeed
    }

    func remove(_ orb: Orb) {
        orb.node.removeAllParticleSystems()
        orb.node.removeFromParentNode()
        byNode[ObjectIdentifier(orb.node)] = nil
        orbs.removeAll { $0 === orb }
    }

    func removeAll() {
        orbs.forEach { $0.node.removeFromParentNode() }
        orbs.removeAll()
        byNode.removeAll()
    }
}
