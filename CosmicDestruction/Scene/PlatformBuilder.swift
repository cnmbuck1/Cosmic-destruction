import SceneKit
import UIKit

/// Builds the floating neon lunar platform: an irregular extruded slab with a
/// static physics body, glowing rims, and a rocky underside.
@MainActor
enum PlatformBuilder {

    /// Irregular outline: a rounded-rectangle superellipse with seeded radial
    /// noise, smoothed so the edge reads as weathered rock, not jagged spikes.
    static func outlinePath(width: Float, depth: Float, scale: CGFloat = 1) -> UIBezierPath {
        var rng = SeededRandom(seed: 5)
        let count = 72
        let a = Double(width / 2), b = Double(depth / 2), n = 4.0
        var noise = (0..<count).map { _ in Double(rng.float(-1...1)) }
        // Two smoothing passes over the ring.
        for _ in 0..<2 {
            noise = noise.indices.map { i in
                (noise[(i + count - 1) % count] + 2 * noise[i] + noise[(i + 1) % count]) / 4
            }
        }
        let path = UIBezierPath()
        for i in 0..<count {
            let t = Double(i) / Double(count) * 2 * .pi
            let c = cos(t), s = sin(t)
            // Superellipse radius at angle t.
            let r = 1 / pow(pow(abs(c) / a, n) + pow(abs(s) / b, n), 1 / n)
            let jitter = noise[i] * 0.45 - 0.15 // mostly inward
            let rr = (r + jitter) * Double(scale)
            let p = CGPoint(x: rr * c, y: rr * s)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        path.flatness = 0.05
        return path
    }

    static func makePlatform() -> SCNNode {
        let lib = MaterialLibrary.shared
        let root = SCNNode()
        root.name = "platform"

        let thickness = CGFloat(GameRules.platformThickness)
        let path = outlinePath(width: GameRules.platformWidth, depth: GameRules.platformDepth)
        let shape = SCNShape(path: path, extrusionDepth: thickness)
        shape.chamferRadius = 0.08
        // Elements: front (top after rotation), back (bottom), sides, chamfers.
        shape.materials = [lib.platformTop, lib.platformRock, lib.platformRock, lib.platformRock, lib.platformRock]

        // SCNShape extrudes along +Z; rotate so the front face points up (+Y)
        // and drop it so the top surface sits exactly at y = 0.
        let slab = SCNNode(geometry: shape)
        slab.eulerAngles.x = -.pi / 2
        slab.position.y = -Float(thickness) / 2
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(
            geometry: shape, options: [SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.convexHull]))
        body.friction = 0.55
        body.restitution = 0.05
        body.categoryBitMask = PhysicsCategory.platform
        body.collisionBitMask = PhysicsCategory.orb | PhysicsCategory.block
        body.contactTestBitMask = 0
        slab.physicsBody = body
        root.addChildNode(slab)

        // Glowing rims: thin, slightly larger copies of the outline that peek
        // out from the edge, giving a crisp separation from the abyss.
        root.addChildNode(rim(scale: 1.02, y: -0.18, material: lib.rimCyan))
        root.addChildNode(rim(scale: 1.014, y: -1.25, material: lib.rimPurple))

        // Rocky underside: a tapered cone plus a few boulders and crystals.
        let cone = SCNCone(topRadius: 7.2, bottomRadius: 1.2, height: 4.5)
        cone.radialSegmentCount = 18
        cone.materials = [lib.platformRock]
        let coneNode = SCNNode(geometry: cone)
        coneNode.position = SCNVector3(x: 0, y: -thicknessF - 2.2, z: 0)
        coneNode.scale = SCNVector3(x: 1.0, y: 1, z: 0.86)
        root.addChildNode(coneNode)

        var rng = SeededRandom(seed: 11)
        let boulder = SCNSphere(radius: 1)
        boulder.segmentCount = 7
        boulder.materials = [lib.platformRock]
        for _ in 0..<9 {
            let node = SCNNode(geometry: boulder)
            let angle = rng.float(0...(2 * .pi))
            let radius = rng.float(2...5.5)
            node.position = SCNVector3(x: cos(angle) * radius, y: -thicknessF - rng.float(0.3...2.6), z: sin(angle) * radius * 0.8)
            let s = rng.float(0.6...1.5)
            node.scale = SCNVector3(x: s * rng.float(0.8...1.4), y: s * 0.7, z: s)
            node.eulerAngles = SCNVector3(x: rng.float(0...3), y: rng.float(0...3), z: rng.float(0...3))
            root.addChildNode(node)
        }
        let crystalGeo = SCNPyramid(width: 0.35, height: 1.1, length: 0.35)
        crystalGeo.materials = [lib.crystal]
        for _ in 0..<7 {
            let node = SCNNode(geometry: crystalGeo)
            let angle = rng.float(0...(2 * .pi))
            let radius = rng.float(3...6.5)
            node.position = SCNVector3(x: cos(angle) * radius, y: -thicknessF - 0.1, z: sin(angle) * radius * 0.85)
            node.eulerAngles = SCNVector3(x: .pi + rng.float(-0.4...0.4), y: rng.float(0...3), z: rng.float(-0.4...0.4))
            node.castsShadow = false
            root.addChildNode(node)
        }
        return root
    }

    private static var thicknessF: Float { GameRules.platformThickness }

    private static func rim(scale: CGFloat, y: Float, material: SCNMaterial) -> SCNNode {
        let shape = SCNShape(path: outlinePath(width: GameRules.platformWidth, depth: GameRules.platformDepth, scale: scale),
                             extrusionDepth: 0.06)
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        node.eulerAngles.x = -.pi / 2
        node.position.y = y
        node.castsShadow = false
        return node
    }
}
