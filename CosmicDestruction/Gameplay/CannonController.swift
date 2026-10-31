import SceneKit
import UIKit

/// Futuristic electromagnetic railgun. Handles appearance, aiming limits,
/// charging glow, recoil, and launch origin/direction.
@MainActor
final class CannonController {
    let rootNode = SCNNode()
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()
    /// Moves backward on recoil.
    private let barrelGroup = SCNNode()
    private let chamberRing = SCNNode()
    let muzzleNode = SCNNode()

    private(set) var yawDegrees: Float = 0
    private(set) var elevationDegrees: Float = GameRules.defaultElevationDegrees

    /// 0 = idle, 1 = fully charged. Rises while the player holds aim.
    private var charge: Float = 0
    private var isCharging = false
    /// Extra glow right after firing, decays to 0.
    private var fireGlow: Float = 0
    private var time: Float = 0

    private let barrelRestZ: Float = 0

    init() {
        build()
        applyAim()
    }

    // MARK: Aiming

    func setAim(yawDegrees yaw: Float, elevationDegrees elevation: Float) {
        yawDegrees = yaw.clamped(-GameRules.yawLimitDegrees, GameRules.yawLimitDegrees)
        elevationDegrees = elevation.clamped(GameRules.minElevationDegrees, GameRules.maxElevationDegrees)
        applyAim()
    }

    func resetAim() {
        setAim(yawDegrees: 0, elevationDegrees: GameRules.defaultElevationDegrees)
        isCharging = false
        charge = 0
    }

    private func applyAim() {
        yawNode.eulerAngles.y = -yawDegrees.degreesToRadians
        pitchNode.eulerAngles.x = elevationDegrees.degreesToRadians
    }

    /// Unit launch direction from the current aim. The barrel points down -Z;
    /// positive yaw turns right (toward +X), positive elevation tilts up.
    var launchDirection: SIMD3<Float> {
        let yaw = yawDegrees.degreesToRadians
        let pitch = elevationDegrees.degreesToRadians
        return SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    /// World-space muzzle position at rest (independent of recoil animation).
    var muzzleWorldPosition: SIMD3<Float> {
        let local = SIMD3<Float>(0, 0, -1.95)
        return pitchNode.simdConvertPosition(local, to: nil)
    }

    // MARK: Charging & firing

    func beginCharging() { isCharging = true }
    func cancelCharging() { isCharging = false }

    /// Plays the firing sequence: energy surge, recoil, smooth return.
    func playFireAnimation() {
        isCharging = false
        charge = 0
        fireGlow = 1
        barrelGroup.removeAction(forKey: "recoil")
        barrelGroup.position.z = barrelRestZ
        let kick = SCNAction.move(to: SCNVector3(x: 0, y: 0, z: barrelRestZ + 0.32), duration: 0.05)
        kick.timingMode = .easeOut
        let settle = SCNAction.move(to: SCNVector3(x: 0, y: 0, z: barrelRestZ), duration: 0.4)
        settle.timingMode = .easeInEaseOut
        barrelGroup.runAction(.sequence([kick, settle]), forKey: "recoil")
    }

    /// Per-frame idle animation: chamber ring spin and energy glow.
    func update(dt: Float) {
        time += dt
        if isCharging {
            charge = min(1, charge + dt * 1.8)
        } else {
            charge = max(0, charge - dt * 3)
        }
        fireGlow = max(0, fireGlow - dt * 2.2)
        let pulse = 0.15 * sin(time * 3)
        let intensity = 1.1 + pulse + charge * 1.6 + fireGlow * 4
        MaterialLibrary.shared.cannonEnergy.emission.intensity = CGFloat(intensity)
        chamberRing.eulerAngles.z += dt * (0.8 + charge * 6 + fireGlow * 10)
    }

    // MARK: Construction

    private func build() {
        let lib = MaterialLibrary.shared
        rootNode.name = "cannon"
        rootNode.simdPosition = GameRules.cannonPosition

        // Base pedestal with a glowing ring.
        let base = SCNCylinder(radius: 0.95, height: 0.32)
        base.radialSegmentCount = 40
        base.materials = [lib.cannonDark]
        let baseNode = SCNNode(geometry: base)
        baseNode.position.y = 0.16
        rootNode.addChildNode(baseNode)

        let baseRing = SCNTorus(ringRadius: 0.9, pipeRadius: 0.035)
        baseRing.materials = [lib.cannonEnergy]
        let baseRingNode = SCNNode(geometry: baseRing)
        baseRingNode.position.y = 0.32
        baseRingNode.castsShadow = false
        rootNode.addChildNode(baseRingNode)

        // Yaw turret.
        yawNode.position.y = 0.32
        rootNode.addChildNode(yawNode)

        let housing = SCNCylinder(radius: 0.58, height: 0.36)
        housing.radialSegmentCount = 32
        housing.materials = [lib.cannonGraphite]
        let housingNode = SCNNode(geometry: housing)
        housingNode.position.y = 0.18
        yawNode.addChildNode(housingNode)

        let cheek = SCNBox(width: 0.16, height: 0.75, length: 0.9, chamferRadius: 0.05)
        cheek.materials = [lib.cannonGraphite]
        for x in [-0.5, 0.5] as [Float] {
            let node = SCNNode(geometry: cheek)
            node.position = SCNVector3(x: x, y: 0.62, z: 0)
            yawNode.addChildNode(node)
            let strip = SCNBox(width: 0.02, height: 0.5, length: 0.05, chamferRadius: 0)
            strip.materials = [lib.cannonEnergy]
            let stripNode = SCNNode(geometry: strip)
            stripNode.position = SCNVector3(x: x > 0 ? 0.085 : -0.085, y: 0, z: 0.25)
            stripNode.castsShadow = false
            node.addChildNode(stripNode)
        }

        // Pitch assembly.
        pitchNode.position.y = 0.72
        yawNode.addChildNode(pitchNode)

        // Circular energy chamber.
        let chamber = SCNSphere(radius: 0.4)
        chamber.segmentCount = 32
        chamber.materials = [lib.cannonGraphite]
        pitchNode.addChildNode(SCNNode(geometry: chamber))

        let ring = SCNTorus(ringRadius: 0.44, pipeRadius: 0.045)
        ring.materials = [lib.cannonEnergy]
        let ringHolder = SCNNode()
        ringHolder.eulerAngles.x = .pi / 2 // face down the barrel axis
        chamberRing.geometry = ring
        chamberRing.castsShadow = false
        ringHolder.addChildNode(chamberRing)
        pitchNode.addChildNode(ringHolder)

        let core = SCNSphere(radius: 0.16)
        core.materials = [lib.cannonEnergy]
        let coreNode = SCNNode(geometry: core)
        coreNode.position.z = 0.32
        pitchNode.addChildNode(coreNode)

        // Twin rails (the "barrel"), with energy channels.
        pitchNode.addChildNode(barrelGroup)
        let rail = SCNBox(width: 0.15, height: 0.22, length: 1.75, chamferRadius: 0.035)
        rail.materials = [lib.cannonGraphite]
        let channel = SCNBox(width: 0.04, height: 0.03, length: 1.55, chamferRadius: 0)
        channel.materials = [lib.cannonEnergy]
        for x in [-0.17, 0.17] as [Float] {
            let railNode = SCNNode(geometry: rail)
            railNode.position = SCNVector3(x: x, y: 0, z: -0.95)
            barrelGroup.addChildNode(railNode)
            let channelNode = SCNNode(geometry: channel)
            channelNode.position = SCNVector3(x: 0, y: 0.115, z: 0)
            channelNode.castsShadow = false
            railNode.addChildNode(channelNode)
        }
        // Center energy line between the rails.
        let line = SCNBox(width: 0.035, height: 0.035, length: 1.6, chamferRadius: 0)
        line.materials = [lib.cannonEnergy]
        let lineNode = SCNNode(geometry: line)
        lineNode.position = SCNVector3(x: 0, y: 0, z: -0.95)
        lineNode.castsShadow = false
        barrelGroup.addChildNode(lineNode)

        // Segmented collars along the barrel.
        let collar = SCNBox(width: 0.62, height: 0.34, length: 0.08, chamferRadius: 0.03)
        collar.materials = [lib.cannonDark]
        for z in [-0.55, -1.05, -1.55] as [Float] {
            let node = SCNNode(geometry: collar)
            node.position = SCNVector3(x: 0, y: 0, z: z)
            barrelGroup.addChildNode(node)
        }

        // Glowing muzzle ring.
        let muzzle = SCNTorus(ringRadius: 0.2, pipeRadius: 0.04)
        muzzle.materials = [lib.cannonEnergy]
        let muzzleRing = SCNNode(geometry: muzzle)
        muzzleRing.eulerAngles.x = .pi / 2
        muzzleRing.position.z = -1.85
        muzzleRing.castsShadow = false
        barrelGroup.addChildNode(muzzleRing)

        muzzleNode.position.z = -1.95
        barrelGroup.addChildNode(muzzleNode)
    }
}
