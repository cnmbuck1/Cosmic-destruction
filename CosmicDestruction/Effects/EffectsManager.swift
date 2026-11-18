import SceneKit
import UIKit
import simd

/// Impact flashes, particles, shockwaves, muzzle flash, camera shake and
/// cinematic slow motion. Particle counts and concurrent effects are capped so
/// the physical collapse stays the main attraction.
@MainActor
final class EffectsManager {
    private let sceneManager: SceneManager
    private var root: SCNNode { sceneManager.effectsRoot }

    /// Master switch for slow motion (exposed in developer settings).
    var slowMotionEnabled = true
    /// Multiplier on every camera shake (debug-tunable).
    var shakeIntensity: Float = 1

    // Pools of reusable flash / shockwave nodes.
    private var flashPool: [SCNNode] = []
    private var shockPool: [SCNNode] = []
    /// Flat rings that expand along the ground at the impact point.
    private var groundRingPool: [SCNNode] = []
    private var groundRingIndex = 0
    private var flashIndex = 0
    private var shockIndex = 0

    private let sparkTemplate: SCNParticleSystem
    private let dustTemplate: SCNParticleSystem
    private let trailTemplate: SCNParticleSystem
    /// Blocks currently carrying a debris trail.
    private var trailed: [StructureManager.Block] = []

    // Impact light envelope.
    private var impactLightLevel: Float = 0

    // Camera shake.
    private var shakeRemaining: Float = 0
    private var shakeDuration: Float = 0
    private var shakeAmplitude: Float = 0

    // Slow motion: real-time remaining at reduced speed, then a smooth ramp back.
    private(set) var isSlowMotionActive = false
    private var slowRemaining: Float = 0
    private var rampRemaining: Float = 0
    private let rampDuration: Float = 0.25
    private var slowScale: Float = 1

    // Throttling so dozens of block contacts don't spam effects.
    private var lastDustTime: TimeInterval = 0
    private var dustThisFrame = 0

    init(sceneManager: SceneManager) {
        self.sceneManager = sceneManager
        // Initialize every stored property before touching the pools.
        sparkTemplate = Self.makeBurst(color: Palette.cyan, size: 0.09, speed: 4.5, life: 0.45, gravity: true)
        dustTemplate = Self.makeBurst(color: UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1),
                                      size: 0.16, speed: 1.4, life: 0.6, gravity: false)
        trailTemplate = Self.makeTrail()
        let lib = MaterialLibrary.shared

        let flashGeo = SCNPlane(width: 1, height: 1)
        flashGeo.materials = [lib.flash]
        let shockGeo = SCNPlane(width: 1, height: 1)
        shockGeo.materials = [lib.shockwave]
        for _ in 0..<5 {
            let flash = SCNNode(geometry: flashGeo)
            flash.constraints = [SCNBillboardConstraint()]
            flash.opacity = 0
            flash.castsShadow = false
            flash.renderingOrder = 20
            flashPool.append(flash)
            let shock = SCNNode(geometry: shockGeo)
            shock.constraints = [SCNBillboardConstraint()]
            shock.opacity = 0
            shock.castsShadow = false
            shock.renderingOrder = 21
            shockPool.append(shock)
        }
        let ringGeo = SCNPlane(width: 1, height: 1)
        ringGeo.materials = [lib.shockwave]
        for _ in 0..<3 {
            let holder = SCNNode()
            // holder (yaw + uniform growth) → stretch (ellipse along the shot) → ring.
            let stretch = SCNNode()
            stretch.name = "stretch"
            stretch.simdScale = SIMD3<Float>(1.5, 1, 0.75)
            let ring = SCNNode(geometry: ringGeo)
            ring.eulerAngles.x = -.pi / 2
            ring.castsShadow = false
            ring.renderingOrder = 21
            stretch.addChildNode(ring)
            holder.addChildNode(stretch)
            holder.opacity = 0
            groundRingPool.append(holder)
        }

    }

    /// Re-attaches pooled nodes after the level root is cleared.
    func reset() {
        trailed.removeAll()
        for node in flashPool + shockPool + groundRingPool {
            node.removeAllActions()
            node.opacity = 0
            if node.parent == nil { root.addChildNode(node) }
        }
        impactLightLevel = 0
        sceneManager.impactLight.light?.intensity = 0
        shakeRemaining = 0
        endSlowMotionImmediately()
    }

    // MARK: Impacts

    /// Energy flash + sparks + shockwave + light highlight, scaled by intensity (0...1).
    func impact(at point: SIMD3<Float>, intensity: Float) {
        let k = intensity.clamped(0.15, 1)
        flash(at: point, size: 0.8 + 1.6 * k, duration: 0.18 + 0.1 * Double(k))
        shockwave(at: point, size: 1.2 + 3.2 * k)
        burst(sparkTemplate, at: point, count: 10 + 26 * k)
        sceneManager.impactLight.simdPosition = point + SIMD3<Float>(0, 0.4, 0)
        impactLightLevel = max(impactLightLevel, 1400 * k)
    }

    /// Expanding cyan shockwave ring flat along the impact height (§10).
    /// Brief directional shockwave (build 3.0 §6): an ellipse stretched along
    /// the orb's travel and pushed slightly ahead of the hit, so it reads as
    /// energy carried through the structure rather than a round explosion.
    func groundShockwave(at point: SIMD3<Float>, radius: Float, direction: SIMD3<Float>) {
        let node = groundRingPool[groundRingIndex % groundRingPool.count]
        groundRingIndex += 1
        if node.parent == nil { root.addChildNode(node) }
        node.removeAllActions()
        var flat = SIMD2<Float>(direction.x, direction.z)
        flat = simd_length(flat) > 0.001 ? simd_normalize(flat) : SIMD2<Float>(0, -1)
        let ahead = flat * radius * 0.25
        node.simdPosition = SIMD3<Float>(point.x + ahead.x, max(point.y - 0.2, 0.05), point.z + ahead.y)
        node.simdOrientation = simd_quatf(angle: atan2(-flat.y, flat.x), axis: SIMD3<Float>(0, 1, 0))
        node.simdScale = SIMD3<Float>(repeating: 0.3)
        node.opacity = 1
        let grow = SCNAction.scale(to: CGFloat(radius * 2.4), duration: 0.5)
        grow.timingMode = .easeOut
        let fade = SCNAction.sequence([.wait(duration: 0.15), .fadeOut(duration: 0.4)])
        node.runAction(.group([grow, fade]))
    }

    /// Adds short glowing trails to fast-moving debris (capped), and removes
    /// them once the piece slows down or leaves.
    func updateDebrisTrails(blocks: [StructureManager.Block]) {
        trailed.removeAll { block in
            let speed = simd_length(block.node.physicsBody?.velocity.asSIMD ?? .zero)
            guard block.isGone || speed < GameRules.debrisTrailSpeed * 0.5 else { return false }
            block.node.removeAllParticleSystems()
            block.hasTrail = false
            return true
        }
        guard trailed.count < GameRules.maxDebrisTrails else { return }
        for block in blocks where !block.hasTrail && !block.isGone {
            guard let body = block.node.physicsBody,
                  simd_length(body.velocity.asSIMD) > GameRules.debrisTrailSpeed,
                  let system = trailTemplate.copy() as? SCNParticleSystem else { continue }
            block.node.addParticleSystem(system)
            block.hasTrail = true
            trailed.append(block)
            if trailed.count >= GameRules.maxDebrisTrails { break }
        }
    }

    var activeTrailCount: Int { trailed.count }

    private static func makeTrail() -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.loops = true
        ps.birthRate = 70
        ps.particleLifeSpan = 0.35
        ps.particleSize = 0.12
        ps.particleSizeVariation = 0.05
        ps.particleColor = UIColor(red: 0.45, green: 0.6, blue: 1.0, alpha: 0.8)
        ps.particleImage = MaterialLibrary.shared.glowImage
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.particleVelocity = 0.2
        ps.spreadingAngle = 180
        ps.emittingDirection = SCNVector3(x: 0, y: 1, z: 0)
        ps.sortingMode = .none
        let fade = CAKeyframeAnimation()
        fade.values = [0.8, 0.0]
        fade.keyTimes = [0, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return ps
    }

    /// Small dust/energy puff for block-on-block or block-on-ground hits.
    func dust(at point: SIMD3<Float>, intensity: Float, time: TimeInterval) {
        guard dustThisFrame < 2, time - lastDustTime > 0.05 else { return }
        dustThisFrame += 1
        lastDustTime = time
        burst(dustTemplate, at: point, count: 6 + 12 * intensity.clamped(0, 1))
    }

    /// Strong white-cyan flash and light pulse for the first, major orb impact.
    func strongFlash(at point: SIMD3<Float>, size: Float) {
        flash(at: point, size: size, duration: 0.26)
        sceneManager.impactLight.simdPosition = point + SIMD3<Float>(0, 0.4, 0)
        impactLightLevel = max(impactLightLevel, 2400)
    }

    func muzzleFlash(at point: SIMD3<Float>) {
        flash(at: point, size: 1.6, duration: 0.14)
        burst(sparkTemplate, at: point, count: 14)
        sceneManager.impactLight.simdPosition = point
        impactLightLevel = max(impactLightLevel, 900)
    }

    private func flash(at point: SIMD3<Float>, size: Float, duration: Double) {
        let node = flashPool[flashIndex % flashPool.count]
        flashIndex += 1
        if node.parent == nil { root.addChildNode(node) }
        node.removeAllActions()
        node.simdPosition = point
        node.simdScale = SIMD3<Float>(repeating: size * 0.4)
        node.opacity = 1
        let grow = SCNAction.scale(to: CGFloat(size), duration: duration)
        grow.timingMode = .easeOut
        node.runAction(.group([grow, .fadeOut(duration: duration)]))
    }

    private func shockwave(at point: SIMD3<Float>, size: Float) {
        let node = shockPool[shockIndex % shockPool.count]
        shockIndex += 1
        if node.parent == nil { root.addChildNode(node) }
        node.removeAllActions()
        node.simdPosition = point
        node.simdScale = SIMD3<Float>(repeating: 0.2)
        node.opacity = 0.9
        let grow = SCNAction.scale(to: CGFloat(size), duration: 0.35)
        grow.timingMode = .easeOut
        node.runAction(.group([grow, .fadeOut(duration: 0.35)]))
    }

    private func burst(_ template: SCNParticleSystem, at point: SIMD3<Float>, count: Float) {
        guard let system = template.copy() as? SCNParticleSystem else { return }
        // birthRate × emissionDuration = particle count.
        system.birthRate = CGFloat(count / Float(system.emissionDuration))
        sceneManager.scene.addParticleSystem(system, transform: SCNMatrix4MakeTranslation(point.x, point.y, point.z))
    }

    private static func makeBurst(color: UIColor, size: CGFloat, speed: CGFloat, life: CGFloat, gravity: Bool) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.loops = false
        ps.emissionDuration = 0.04
        ps.birthRate = 500
        ps.particleLifeSpan = life
        ps.particleLifeSpanVariation = life * 0.4
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.5
        ps.particleColor = color
        ps.particleImage = MaterialLibrary.shared.glowImage
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.birthDirection = .random
        ps.particleVelocity = speed
        ps.particleVelocityVariation = speed * 0.6
        ps.spreadingAngle = 180
        ps.isAffectedByGravity = gravity
        ps.dampingFactor = 1.5
        ps.sortingMode = .none
        let fade = CAKeyframeAnimation()
        fade.values = [1.0, 0.0]
        fade.keyTimes = [0, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return ps
    }

    // MARK: Camera shake

    func shake(amplitude rawAmplitude: Float, duration: Float) {
        let amplitude = rawAmplitude * shakeIntensity
        guard amplitude > 0.0001, amplitude >= shakeAmplitude * (shakeRemaining / max(shakeDuration, 0.001)) else { return }
        shakeAmplitude = amplitude
        shakeDuration = duration
        shakeRemaining = duration
    }

    // MARK: Slow motion

    /// Briefly slows the physics simulation for a cinematic beat, then eases back.
    func triggerSlowMotion(scale: Float = GameRules.slowMotionScale, duration: TimeInterval = GameRules.slowMotionDuration) {
        guard slowMotionEnabled, !isSlowMotionActive else { return }
        isSlowMotionActive = true
        slowScale = scale
        slowRemaining = Float(duration)
        rampRemaining = rampDuration
        sceneManager.scene.physicsWorld.speed = CGFloat(scale)
    }

    func endSlowMotionImmediately() {
        isSlowMotionActive = false
        slowRemaining = 0
        rampRemaining = 0
        sceneManager.scene.physicsWorld.speed = 1
    }

    /// Current simulation speed multiplier (1 = normal).
    var timeScale: Float { Float(sceneManager.scene.physicsWorld.speed) }

    // MARK: Per-frame

    func update(dt: Float) {
        dustThisFrame = 0

        // Impact light decay.
        if impactLightLevel > 0 {
            impactLightLevel = max(0, impactLightLevel - dt * 6000)
            sceneManager.impactLight.light?.intensity = CGFloat(impactLightLevel)
        }

        // Shake: random offset with linear falloff.
        if shakeRemaining > 0 {
            shakeRemaining = max(0, shakeRemaining - dt)
            let falloff = shakeRemaining / max(shakeDuration, 0.001)
            let a = shakeAmplitude * falloff
            sceneManager.shakeNode.simdPosition = SIMD3<Float>(Float.random(in: -a...a), Float.random(in: -a...a), 0)
            if shakeRemaining == 0 {
                shakeAmplitude = 0
                sceneManager.shakeNode.simdPosition = .zero
            }
        }

        // Slow motion envelope (real time).
        if isSlowMotionActive {
            if slowRemaining > 0 {
                slowRemaining -= dt
            } else if rampRemaining > 0 {
                rampRemaining -= dt
                let t = 1 - max(0, rampRemaining) / rampDuration
                let eased = t * t * (3 - 2 * t)
                sceneManager.scene.physicsWorld.speed = CGFloat(slowScale + (1 - slowScale) * eased)
            } else {
                endSlowMotionImmediately()
            }
        }
    }
}
