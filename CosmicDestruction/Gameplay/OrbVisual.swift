import SceneKit
import UIKit

/// Visual for the projectile. Physics lives on a separate parent node owned by
/// OrbController, so the final branded Cnmbuck orb can replace this visual
/// without touching projectile physics.
@MainActor
protocol OrbVisual {
    func makeNode(radius: Float) -> SCNNode
}

/// Prototype version of the Cnmbuck Studios signature orb: a glassy shell with
/// concentric energy bands, an illuminated cyan core, orbiting rings, a soft
/// halo, a small light, and a short luminous trail.
/// No logo or wordmark is implied by this design.
struct SignatureOrbVisual: OrbVisual {
    func makeNode(radius: Float) -> SCNNode {
        let lib = MaterialLibrary.shared
        let r = CGFloat(radius)
        let root = SCNNode()
        root.name = "orbVisual"

        let core = SCNSphere(radius: r * 0.5)
        core.segmentCount = 24
        core.materials = [lib.orbCore]
        root.addChildNode(SCNNode(geometry: core))

        let shell = SCNSphere(radius: r)
        shell.segmentCount = 36
        shell.materials = [lib.orbShell]
        let shellNode = SCNNode(geometry: shell)
        shellNode.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 2.5)))
        root.addChildNode(shellNode)

        // Two counter-rotating energy rings inside the shell.
        for (tilt, speed) in [(Float(0.5), 3.0), (Float(-0.9), -4.2)] as [(Float, Double)] {
            let ring = SCNTorus(ringRadius: r * 0.74, pipeRadius: r * 0.035)
            ring.ringSegmentCount = 36
            ring.materials = [lib.orbRing]
            let holder = SCNNode()
            holder.eulerAngles = SCNVector3(x: tilt, y: 0, z: tilt * 0.5)
            let ringNode = SCNNode(geometry: ring)
            ringNode.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat(speed), z: 0, duration: 1)))
            holder.addChildNode(ringNode)
            root.addChildNode(holder)
        }

        // Soft blue-white halo, always facing the camera.
        let halo = SCNPlane(width: r * 4.2, height: r * 4.2)
        halo.materials = [lib.orbHalo]
        let haloNode = SCNNode(geometry: halo)
        haloNode.constraints = [SCNBillboardConstraint()]
        haloNode.castsShadow = false
        haloNode.renderingOrder = 10
        root.addChildNode(haloNode)

        // A small light so the orb illuminates blocks as it flies past.
        let light = SCNLight()
        light.type = .omni
        light.color = Palette.cyan
        light.intensity = 350
        light.attenuationStartDistance = 0.3
        light.attenuationEndDistance = 4
        root.light = light

        root.addParticleSystem(Self.makeTrail(radius: r))
        return root
    }

    /// Short cyan trail, emitted in world space so it streams behind the orb.
    private static func makeTrail(radius: CGFloat) -> SCNParticleSystem {
        let trail = SCNParticleSystem()
        trail.loops = true
        trail.birthRate = 240
        trail.emissionDuration = 1
        trail.particleLifeSpan = 0.22
        trail.particleLifeSpanVariation = 0.05
        trail.particleSize = radius * 0.9
        trail.particleSizeVariation = radius * 0.2
        trail.particleColor = Palette.cyan
        trail.particleImage = MaterialLibrary.shared.glowImage
        trail.blendMode = .additive
        trail.isLightingEnabled = false
        trail.particleVelocity = 0
        trail.emitterShape = SCNSphere(radius: radius * 0.4)
        trail.birthLocation = .volume
        trail.isLocal = false
        trail.sortingMode = .none

        // Property controller values are absolute: size in meters, opacity 0...1.
        let shrink = CAKeyframeAnimation()
        shrink.values = [radius * 0.9, radius * 0.1]
        shrink.keyTimes = [0, 1]
        let fade = CAKeyframeAnimation()
        fade.values = [1.0, 0.0]
        fade.keyTimes = [0, 1]
        trail.propertyControllers = [
            .size: SCNParticlePropertyController(animation: shrink),
            .opacity: SCNParticlePropertyController(animation: fade),
        ]
        return trail
    }
}
