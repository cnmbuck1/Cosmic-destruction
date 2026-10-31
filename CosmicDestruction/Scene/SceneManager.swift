import SceneKit
import UIKit
import simd

/// Creates and owns the 3D environment: space backdrop, lighting, platform,
/// fixed camera rig, and the containers gameplay systems add nodes into.
@MainActor
final class SceneManager {
    let scene = SCNScene()

    /// Container for level-specific content (structure, orbs). Cleared per level.
    let levelRoot = SCNNode()
    /// Container for transient effects.
    let effectsRoot = SCNNode()

    let cameraRig = SCNNode()
    /// Child of the rig used only for shake offsets, so shake never drifts the camera.
    let shakeNode = SCNNode()
    let cameraNode = SCNNode()
    private let camera = SCNCamera()

    /// Light reused for impact highlights.
    let impactLight = SCNNode()

    /// Energy pattern under the structure; moved to each level's origin.
    let energyCircle = PlatformBuilder.makeEnergyCircle()

    // Camera framing (§10). The look target can drift a little toward the
    // action for a restrained cinematic follow, then eases back.
    private var baseLookTarget = SIMD3<Float>(0, 1.0, -4.5)
    private var followTarget: SIMD3<Float>?
    private var followWeight: Float = 0
    private var currentLook = SIMD3<Float>(0, 1.0, -4.5)

    init() {
        scene.physicsWorld.timeStep = 1.0 / 120.0
        buildBackground()
        buildLighting()
        buildCamera()
        scene.rootNode.addChildNode(PlatformBuilder.makePlatform(config: DestructionPhysicsConfig()))
        scene.rootNode.addChildNode(energyCircle)
        levelRoot.name = "levelRoot"
        effectsRoot.name = "effectsRoot"
        scene.rootNode.addChildNode(levelRoot)
        scene.rootNode.addChildNode(effectsRoot)
    }

    // MARK: Configuration

    func setGravity(_ g: Float) {
        scene.physicsWorld.gravity = SCNVector3(x: 0, y: g, z: 0)
    }

    var gravity: Float { Float(scene.physicsWorld.gravity.y) }

    func setFieldOfView(_ degrees: Float) {
        camera.fieldOfView = CGFloat(degrees)
    }

    /// Frames the level (build 3.0 §2): the camera sits close behind and above
    /// the cannon and looks at a point just in front of the structure, so the
    /// structure fills about a third of the screen height while the island's
    /// side edges and the void around it stay in view.
    func frame(level: LevelDefinition, config: DestructionPhysicsConfig) {
        let origin = level.structureOrigin
        energyCircle.simdPosition = SIMD3<Float>(origin.x, 0.012, origin.z)
        let pull = level.cameraPullBack
        let cannon = GameRules.cannonPosition
        cameraRig.simdPosition = SIMD3<Float>(0, config.cameraElevation + pull * 0.6,
                                              cannon.z + config.cameraDistance + pull)
        baseLookTarget = SIMD3<Float>(origin.x, config.cameraLookHeight, origin.z + config.cameraLookAhead)
        currentLook = baseLookTarget
        followTarget = nil
        followWeight = 0
        cameraRig.simdLook(at: currentLook)
        setFieldOfView(config.cameraFieldOfView)
    }

    /// Restrained cinematic follow: leans the view up to 18% toward a point.
    func follow(_ point: SIMD3<Float>?) {
        if let point { followTarget = point }
        followWeight = point == nil ? 0 : 0.18
    }

    func updateCamera(dt: Float) {
        var goal = baseLookTarget
        if let target = followTarget, followWeight > 0 {
            var clamped = target
            clamped.y = clamped.y.clamped(-1, 4)
            goal += (clamped - baseLookTarget) * followWeight
        }
        let k = 1 - exp(-dt * 2.5)
        let next = currentLook + (goal - currentLook) * k
        if simd_distance(next, currentLook) > 0.0001 {
            currentLook = next
            cameraRig.simdLook(at: currentLook)
        }
    }

    /// Removes all level content (structure blocks, orbs, transient effects).
    func clearLevel() {
        levelRoot.childNodes.forEach { $0.removeFromParentNode() }
        effectsRoot.childNodes.forEach { $0.removeFromParentNode() }
        scene.removeAllParticleSystems()
        shakeNode.position = SCNVector3(x: 0, y: 0, z: 0)
    }

    // MARK: Background

    private func buildBackground() {
        let lib = MaterialLibrary.shared
        scene.background.contents = lib.spaceBackground
        // Use the same backdrop as a dim environment map for PBR reflections.
        scene.lightingEnvironment.contents = lib.spaceBackground
        scene.lightingEnvironment.intensity = 0.8

        // Distant ringed planet, unlit so it never competes with the arena lighting.
        let planet = SCNSphere(radius: 16)
        planet.segmentCount = 48
        let planetMat = SCNMaterial()
        planetMat.lightingModel = .constant
        planetMat.diffuse.contents = ProceduralTextures.planetBands()
        planetMat.multiply.contents = UIColor(white: 0.55, alpha: 1)
        planet.materials = [planetMat]
        let planetNode = SCNNode(geometry: planet)
        planetNode.position = SCNVector3(x: -70, y: 34, z: -150)
        planetNode.eulerAngles = SCNVector3(x: 0.3, y: 0, z: 0.35)
        planetNode.castsShadow = false

        let ring = SCNTube(innerRadius: 21, outerRadius: 29, height: 0.05)
        ring.radialSegmentCount = 64
        let ringMat = MaterialLibrary.glow(Palette.purple.withAlphaComponent(0.35), additive: true)
        ring.materials = [ringMat]
        let ringNode = SCNNode(geometry: ring)
        ringNode.eulerAngles.x = 0.25
        planetNode.addChildNode(ringNode)
        planetNode.runAction(.repeatForever(.rotateBy(x: 0, y: 0.2, z: 0, duration: 30)))
        scene.rootNode.addChildNode(planetNode)

        // A faint violet glow deep below the fragment gives the void depth.
        let glow = SCNPlane(width: 60, height: 60)
        let glowMat = MaterialLibrary.glow(MaterialLibrary.shared.glowImage)
        glowMat.multiply.contents = UIColor(red: 0.1, green: 0.06, blue: 0.22, alpha: 1)
        glow.materials = [glowMat]
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(x: 0, y: -26, z: -12)
        glowNode.constraints = [SCNBillboardConstraint()]
        glowNode.castsShadow = false
        glowNode.renderingOrder = -10
        scene.rootNode.addChildNode(glowNode)
    }

    // MARK: Lighting

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(red: 0.35, green: 0.4, blue: 0.7, alpha: 1)
        ambient.intensity = 260
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Cyan-white key light with shadows for readable depth.
        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(red: 0.75, green: 0.93, blue: 1.0, alpha: 1)
        key.intensity = 1100
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowSampleCount = 8
        key.shadowRadius = 2
        key.shadowColor = UIColor(white: 0, alpha: 0.55)
        key.maximumShadowDistance = 30
        key.automaticallyAdjustsShadowProjection = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(x: 6, y: 14, z: 8)
        keyNode.look(at: SCNVector3(x: 0, y: 0, z: -3))
        scene.rootNode.addChildNode(keyNode)

        // Purple rim light from behind the structure.
        let rim = SCNLight()
        rim.type = .directional
        rim.color = Palette.purple
        rim.intensity = 900
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(x: -4, y: 6, z: -14)
        rimNode.look(at: SCNVector3(x: 0, y: 1, z: 0))
        scene.rootNode.addChildNode(rimNode)

        // Soft violet accent near the arena floor.
        let accent = SCNLight()
        accent.type = .omni
        accent.color = Palette.purple
        accent.intensity = 250
        accent.attenuationStartDistance = 2
        accent.attenuationEndDistance = 12
        let accentNode = SCNNode()
        accentNode.light = accent
        accentNode.position = SCNVector3(x: 5, y: 2.5, z: -6)
        scene.rootNode.addChildNode(accentNode)

        // Impact highlight light (intensity driven by EffectsManager).
        let impact = SCNLight()
        impact.type = .omni
        impact.color = Palette.cyan
        impact.intensity = 0
        impact.attenuationStartDistance = 0.5
        impact.attenuationEndDistance = 7
        impactLight.light = impact
        scene.rootNode.addChildNode(impactLight)
    }

    // MARK: Camera

    /// Fixed cannon-perspective camera: behind and above the cannon, looking
    /// down at the structure. Horizontal FOV keeps the full platform width
    /// visible in portrait on every iPhone.
    private func buildCamera() {
        camera.projectionDirection = .horizontal
        camera.fieldOfView = CGFloat(PhysicsTuning().cameraFieldOfView)
        camera.zNear = 0.1
        camera.zFar = 400
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 1.1
        camera.bloomThreshold = 0.75
        camera.bloomBlurRadius = 10
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 0.8
        cameraNode.camera = camera

        cameraRig.addChildNode(shakeNode)
        shakeNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraRig)
        frame(level: Levels.all[0], config: DestructionPhysicsConfig())
    }
}
