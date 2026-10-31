import SceneKit

/// Dotted cyan guide showing the approximate ballistic path of the next orb.
@MainActor
final class TrajectoryIndicator {
    let rootNode = SCNNode()
    private var dots: [SCNNode] = []
    private let dotCount = 26
    private let timeStep: Float = 0.05

    init() {
        rootNode.name = "trajectory"
        let geometry = SCNSphere(radius: 0.055)
        geometry.segmentCount = 8
        geometry.materials = [MaterialLibrary.shared.trajectoryDot]
        for i in 0..<dotCount {
            let dot = SCNNode(geometry: geometry)
            dot.castsShadow = false
            dot.renderingOrder = 5
            // Dots shrink and fade along the path.
            let t = Float(i) / Float(dotCount)
            dot.simdScale = SIMD3<Float>(repeating: 1 - 0.55 * t)
            dots.append(dot)
            rootNode.addChildNode(dot)
        }
        rootNode.isHidden = true
    }

    /// Recomputes dot positions: p(t) = origin + v·t + ½·g·t².
    func update(origin: SIMD3<Float>, velocity: SIMD3<Float>, gravity: Float, emphasis: Float) {
        rootNode.isHidden = false
        for (i, dot) in dots.enumerated() {
            let t = Float(i + 1) * timeStep
            var p = origin + velocity * t
            p.y += 0.5 * gravity * t * t
            // Stop drawing once the path drops below the platform surface.
            if p.y < -0.6 {
                dot.isHidden = true
                continue
            }
            dot.isHidden = false
            dot.simdPosition = p
            let fade = 1 - Float(i) / Float(dotCount)
            dot.opacity = CGFloat(emphasis * (0.25 + 0.75 * fade))
        }
    }

    func hide() { rootNode.isHidden = true }
}
