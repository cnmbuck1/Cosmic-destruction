import SceneKit
import UIKit
import simd

/// Builds the lunar fragment: a compact floating island (build 3.0 §1, about
/// 7.8 × 10 m) suspended over the void, so the structure sits near the far
/// edge with open space and the island's sides visible around it. It has an irregular rocky
/// perimeter, a cratered uneven surface around a level central area, layered
/// strata on its sides, and a tapering rocky root underneath that gives it a
/// floating-island silhouette. Neon is used sparingly (roughly a quarter of
/// the visual weight): broken cyan edge accents, purple veins, a few crystals.
///
/// Physics is deliberately simpler than the visuals: a flat static convex
/// slab whose top is exactly y = 0, so structures always rest on a level
/// surface. The visual terrain is flat (y = 0) over the whole play area and
/// only becomes uneven in the outer band.
@MainActor
enum PlatformBuilder {

    struct Dimensions {
        var width: Float
        var depth: Float
        var thickness: Float
        var centerZ: Float

        init(config: DestructionPhysicsConfig) {
            width = config.platformWidth
            depth = config.platformDepth
            thickness = config.platformThickness
            centerZ = config.platformCenterZ
        }
    }

    // MARK: Outline

    private static let segmentCount = 96

    /// Irregular rocky perimeter: a squarish superellipse with layered
    /// harmonic noise. No bites: the compact island stays nearly convex so its
    /// physics matches what you see. Points are (x, z) in meters relative to
    /// the island center, ordered by angle.
    static func outline(_ d: Dimensions) -> [SIMD2<Float>] {
        var rng = SeededRandom(seed: 5)
        let a = d.width / 2, b = d.depth / 2, n: Float = 3.2
        let phases = (0..<4).map { _ in rng.float(0...(2 * .pi)) }
        var jitter = (0..<segmentCount).map { _ in rng.float(-1...1) }
        for _ in 0..<2 {
            jitter = jitter.indices.map { i in
                (jitter[(i + segmentCount - 1) % segmentCount] + 2 * jitter[i] + jitter[(i + 1) % segmentCount]) / 4
            }
        }
        return (0..<segmentCount).map { i in
            let t = Float(i) / Float(segmentCount) * 2 * .pi
            let c = cos(t), s = sin(t)
            let r = 1 / pow(pow(abs(c) / a, n) + pow(abs(s) / b, n), 1 / n)
            let h1: Float = 0.02 * sin(3 * t + phases[0])
            let h2: Float = 0.015 * sin(5 * t + phases[1])
            let h3: Float = 0.012 * sin(9 * t + phases[2])
            let h4: Float = 0.01 * sin(17 * t + phases[3])
            var k: Float = 0.97 + h1 + h2 + h3 + h4 + 0.025 * jitter[i]
            // Keep the cannon's ground (front, +Z) whole.
            if s > 0.85 { k = max(k, 0.99) }
            return SIMD2<Float>(c, s) * r * min(k, 1)
        }
    }

    // MARK: Terrain

    private struct Crater {
        var center: SIMD2<Float>
        var radius: Float
        var depth: Float
    }

    private static func craters(_ outline: [SIMD2<Float>]) -> [Crater] {
        var rng = SeededRandom(seed: 17)
        var result: [Crater] = []
        var attempts = 0
        while result.count < 8, attempts < 200 {
            attempts += 1
            let i = Int(rng.float(0...Float(outline.count - 1)))
            // Craters live in the outer rim band only, away from the structure.
            let s = rng.float(0.88...0.94)
            let c = outline[i] * s
            if simd_distance(c, cannonXZ) < 2.6 { continue }
            if result.contains(where: { simd_distance($0.center, c) < $0.radius + 0.9 }) { continue }
            result.append(Crater(center: c, radius: rng.float(0.3...0.6), depth: rng.float(0.06...0.12)))
        }
        return result
    }

    /// The cannon in island-local coordinates (the island is built around its
    /// own center and then placed at `platformCenterZ`).
    private static var cannonXZ: SIMD2<Float> {
        SIMD2(GameRules.cannonPosition.x, GameRules.cannonPosition.z - DestructionPhysicsConfig().platformCenterZ)
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = ((x - e0) / (e1 - e0)).clamped(0, 1)
        return t * t * (3 - 2 * t)
    }

    /// Visual terrain height at a point on ring `s` (0 = center, 1 = edge).
    /// Exactly 0 over the central play area.
    private static func height(_ p: SIMD2<Float>, s: Float, craters: [Crater]) -> Float {
        // Flat everywhere structures or the cannon stand; uneven only in the outer rim band.
        var edge = smoothstep(0.86, 0.96, s)
        edge *= smoothstep(1.2, 1.9, simd_distance(p, cannonXZ))
        guard edge > 0 else { return 0 }
        let x = p.x, z = p.y
        let n1: Float = 0.09 * sin(0.9 * x + 1.3) * sin(0.8 * z + 0.4)
        let n2: Float = 0.06 * sin(2.1 * x - 1.7 * z + 2.0)
        let n3: Float = 0.035 * sin(4.3 * x + 3.1 * z + 0.7)
        var h: Float = n1 + n2 + n3 + 0.04
        for crater in craters {
            let d = simd_distance(p, crater.center) / crater.radius
            if d < 1 {
                h -= crater.depth * (1 - d * d)
            } else if d < 1.35 {
                let lip = (d - 1) / 0.35
                h += crater.depth * 0.45 * sin(lip * .pi)
            }
        }
        // Roll the rim down slightly so the edge reads as broken rock.
        h -= 0.18 * smoothstep(0.95, 1.0, s)
        return h * edge
    }

    // MARK: Mesh helper

    /// Small triangle-mesh builder with smooth normals and per-triangle
    /// orientation fixing (each triangle faces along a hint direction).
    private struct MeshBuilder {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        mutating func add(_ p: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
            positions.append(p)
            uvs.append(uv)
            return UInt32(positions.count - 1)
        }

        mutating func tri(_ a: UInt32, _ b: UInt32, _ c: UInt32, facing hint: SIMD3<Float>) {
            let pa = positions[Int(a)], pb = positions[Int(b)], pc = positions[Int(c)]
            let n = simd_cross(pb - pa, pc - pa)
            if simd_dot(n, hint) >= 0 { indices += [a, b, c] } else { indices += [a, c, b] }
        }

        func geometry(material: SCNMaterial) -> SCNGeometry {
            var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
            for t in stride(from: 0, to: indices.count, by: 3) {
                let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
                let n = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
                normals[a] += n; normals[b] += n; normals[c] += n
            }
            let vectors = positions.map { SCNVector3(simd: $0) }
            let normalVectors = normals.map { SCNVector3(simd: simd_length($0) > 0 ? simd_normalize($0) : SIMD3(0, 1, 0)) }
            let points = uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            let geometry = SCNGeometry(sources: [
                SCNGeometrySource(vertices: vectors),
                SCNGeometrySource(normals: normalVectors),
                SCNGeometrySource(textureCoordinates: points),
            ], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            geometry.materials = [material]
            return geometry
        }
    }

    // MARK: Build

    static func makePlatform(config: DestructionPhysicsConfig = DestructionPhysicsConfig()) -> SCNNode {
        let lib = MaterialLibrary.shared
        let dims = Dimensions(config: config)
        let ring = outline(dims)
        let craterList = craters(ring)
        let n = ring.count

        let root = SCNNode()
        root.name = "platform"
        root.simdPosition = SIMD3<Float>(0, 0, dims.centerZ)

        // Top surface: concentric rings following the outline.
        let rings: [Float] = [0.12, 0.25, 0.38, 0.5, 0.6, 0.68, 0.74, 0.79, 0.835, 0.87, 0.9, 0.925, 0.95, 0.97, 0.985, 1]
        var top = MeshBuilder()
        let uvTop: (SIMD2<Float>) -> SIMD2<Float> = { p in SIMD2(p.x / dims.width + 0.5, p.y / dims.depth + 0.5) }
        let center = top.add(SIMD3(0, 0, 0), uvTop(.zero))
        var previous: [UInt32] = []
        var edgeHeights: [Float] = []
        for (k, s) in rings.enumerated() {
            var current: [UInt32] = []
            for i in 0..<n {
                let p = ring[i] * s
                let h = height(p, s: s, craters: craterList)
                current.append(top.add(SIMD3(p.x, h, p.y), uvTop(p)))
                if k == rings.count - 1 { edgeHeights.append(h) }
            }
            let up = SIMD3<Float>(0, 1, 0)
            for i in 0..<n {
                let j = (i + 1) % n
                if k == 0 {
                    top.tri(center, current[i], current[j], facing: up)
                } else {
                    top.tri(previous[i], current[i], current[j], facing: up)
                    top.tri(previous[i], current[j], previous[j], facing: up)
                }
            }
            previous = current
        }
        let topNode = SCNNode(geometry: top.geometry(material: lib.platformTop))
        topNode.name = "platformTop"
        root.addChildNode(topNode)

        // Sides and underside: stacked strata rows, then a tapering rocky root.
        // (y, scale, jitter) per row. Alternating scales make ledges.
        let t = dims.thickness
        let rows: [(Float, Float, Float)] = [
            (-0.28, 1.0, 0.05), (-0.55, 0.975, 0.09), (-0.8, 0.99, 0.06), (-1.15, 0.955, 0.1),
            (-1.5, 0.965, 0.07), (-1.95, 0.925, 0.12), (-t, 0.9, 0.1),
            (-t - 0.7, 0.8, 0.15), (-t - 1.5, 0.64, 0.2), (-t - 2.4, 0.48, 0.22),
            (-t - 3.3, 0.33, 0.2), (-t - 4.2, 0.19, 0.15), (-t - 5.0, 0.08, 0.1),
        ]
        var rng = SeededRandom(seed: 23)
        var side = MeshBuilder()
        let around: Float = 14 // texture repeats around the perimeter
        func sideRow(_ points: [SIMD3<Float>]) -> [UInt32] {
            (0...n).map { i in
                let p = points[i % n]
                return side.add(p, SIMD2(Float(i) / Float(n) * around, -p.y / 3))
            }
        }
        // First row: the top edge itself, so the sides meet the surface exactly.
        var prevRow = sideRow((0..<n).map { SIMD3(ring[$0].x, edgeHeights[$0], ring[$0].y) })
        var prevPoints = (0..<n).map { SIMD3<Float>(ring[$0].x, edgeHeights[$0], ring[$0].y) }
        for (y, scale, jitter) in rows {
            let pts: [SIMD3<Float>] = (0..<n).map { i in
                let base = ring[i] * scale
                let dir = simd_length(ring[i]) > 0 ? simd_normalize(ring[i]) : .zero
                let r = rng.float(-jitter...jitter)
                return SIMD3(base.x + dir.x * r, y + rng.float(-0.06...0.06), base.y + dir.y * r)
            }
            let row = sideRow(pts)
            for i in 0..<n {
                let mid = (prevPoints[i] + pts[i]) * 0.5
                let hint = SIMD3<Float>(mid.x, 0, mid.z) + SIMD3(0, y < -t ? -2.5 : 0, 0)
                side.tri(prevRow[i], row[i], row[i + 1], facing: hint)
                side.tri(prevRow[i], row[i + 1], prevRow[i + 1], facing: hint)
            }
            prevRow = row
            prevPoints = pts
        }
        // Close the root with a tip.
        let tip = side.add(SIMD3(0.2, -t - 5.7, -0.3), SIMD2(0, (t + 5.7) / 3))
        for i in 0..<n {
            side.tri(prevRow[i], tip, prevRow[i + 1], facing: SIMD3(0, -1, 0))
        }
        let sideNode = SCNNode(geometry: side.geometry(material: lib.platformStrata))
        sideNode.name = "platformStrata"
        root.addChildNode(sideNode)

        // Broken neon accents along the top edge (not a continuous ring).
        root.addChildNode(edgeAccents(ring: ring, heights: edgeHeights))

        // Purple crystal clusters on the outer band and under the island.
        root.addChildNode(crystals(ring: ring, craters: craterList, thickness: t))

        // Physics: a flat convex slab with its top at y = 0.
        let slabPath = UIBezierPath()
        for (i, p) in ring.enumerated() {
            let q = CGPoint(x: CGFloat(p.x * 0.985), y: CGFloat(-p.y * 0.985))
            if i == 0 { slabPath.move(to: q) } else { slabPath.addLine(to: q) }
        }
        slabPath.close()
        let slabShape = SCNShape(path: slabPath, extrusionDepth: CGFloat(t))
        let slab = SCNNode()
        slab.name = "platformPhysics"
        slab.eulerAngles.x = -.pi / 2
        slab.position.y = -t / 2
        let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(
            geometry: slabShape, options: [SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.convexHull]))
        body.friction = 0.6
        body.restitution = 0.05
        body.categoryBitMask = PhysicsCategory.platform
        body.collisionBitMask = PhysicsCategory.orb | PhysicsCategory.block
        body.contactTestBitMask = 0
        slab.physicsBody = body
        root.addChildNode(slab)
        return root
    }

    // MARK: Accents

    private static func edgeAccents(ring: [SIMD2<Float>], heights: [Float]) -> SCNNode {
        var rng = SeededRandom(seed: 31)
        var mesh = MeshBuilder()
        let n = ring.count
        var i = 0
        while i < n {
            // Alternate lit runs and dark gaps of random length.
            let run = Int(rng.float(3...9))
            let gap = Int(rng.float(2...7))
            for k in i..<min(i + run, n) {
                let j = (k + 1) % n
                let a = ring[k] * 1.004, b = ring[j] * 1.004
                let ya = heights[k] - 0.02, yb = heights[j] - 0.02
                let h: Float = 0.05
                let v0 = mesh.add(SIMD3(a.x, ya, a.y), SIMD2(0, 0))
                let v1 = mesh.add(SIMD3(b.x, yb, b.y), SIMD2(1, 0))
                let v2 = mesh.add(SIMD3(b.x, yb - h, b.y), SIMD2(1, 1))
                let v3 = mesh.add(SIMD3(a.x, ya - h, a.y), SIMD2(0, 1))
                let mid = (a + b) * 0.5
                let out = SIMD3<Float>(mid.x, 0, mid.y)
                mesh.tri(v0, v1, v2, facing: out)
                mesh.tri(v0, v2, v3, facing: out)
            }
            i += run + gap
        }
        let node = SCNNode(geometry: mesh.geometry(material: MaterialLibrary.shared.rimCyan))
        node.name = "edgeAccents"
        node.castsShadow = false
        return node
    }

    private static func crystals(ring: [SIMD2<Float>], craters: [Crater], thickness: Float) -> SCNNode {
        let lib = MaterialLibrary.shared
        let root = SCNNode()
        root.name = "crystals"
        var rng = SeededRandom(seed: 41)
        let shard = SCNPyramid(width: 0.22, height: 0.75, length: 0.22)
        shard.materials = [lib.crystal]

        // Small clusters in the outer band of the top surface.
        var placed = 0
        var attempts = 0
        while placed < 6, attempts < 100 {
            attempts += 1
            let p = ring[Int(rng.float(0...Float(ring.count - 1)))] * rng.float(0.84...0.92)
            if simd_distance(p, cannonXZ) < 3 || abs(p.x) < 4 && p.y < 0 { continue }
            let cluster = SCNNode()
            cluster.simdPosition = SIMD3(p.x, -0.05, p.y)
            for _ in 0..<Int(rng.float(2...4.9)) {
                let node = SCNNode(geometry: shard)
                let s = rng.float(0.6...1.3)
                node.simdScale = SIMD3(s, s * rng.float(0.8...1.4), s)
                node.simdPosition = SIMD3(rng.float(-0.2...0.2), 0, rng.float(-0.2...0.2))
                node.eulerAngles = SCNVector3(x: rng.float(-0.45...0.45), y: rng.float(0...3), z: rng.float(-0.45...0.45))
                cluster.addChildNode(node)
            }
            cluster.castsShadow = false
            root.addChildNode(cluster)
            placed += 1
        }

        // Shards hanging from the underside.
        for _ in 0..<10 {
            let p = ring[Int(rng.float(0...Float(ring.count - 1)))] * rng.float(0.55...0.85)
            let node = SCNNode(geometry: shard)
            let s = rng.float(1.0...2.0)
            node.simdScale = SIMD3(s, s * 1.5, s)
            node.simdPosition = SIMD3(p.x, -thickness - rng.float(0.3...1.6), p.y)
            node.eulerAngles = SCNVector3(x: .pi + rng.float(-0.35...0.35), y: rng.float(0...3), z: rng.float(-0.35...0.35))
            node.castsShadow = false
            root.addChildNode(node)
        }
        return root
    }

    // MARK: Energy circle

    /// Circular energy pattern under the structure (§8). Positioned per level.
    static func makeEnergyCircle(radius: Float = 2.9) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(radius * 2), height: CGFloat(radius * 2))
        plane.materials = [MaterialLibrary.shared.energyCircle]
        let node = SCNNode(geometry: plane)
        node.name = "energyCircle"
        node.eulerAngles.x = -.pi / 2
        node.castsShadow = false
        node.renderingOrder = 5
        let holder = SCNNode()
        holder.addChildNode(node)
        holder.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)))
        return holder
    }
}
