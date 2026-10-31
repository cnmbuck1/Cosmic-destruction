import simd

/// Decides what happens to anything that leaves the lunar fragment
/// (build sheet 2.0 §4.6). There are no invisible walls: debris keeps
/// simulating as it tumbles into the void, fades out gradually once it is
/// well below the platform (or very far away sideways), and is only removed
/// after it is fully faded. Nothing pops out of existence near the edge.
struct AbyssCleanupManager {
    enum Verdict: Equatable {
        /// Fully visible.
        case keep
        /// Partly faded: 0 = just started, 1 = fully faded.
        case fade(Float)
        /// Remove from the scene.
        case remove
    }

    /// Platform top is y = 0, so depths are positive distances below it.
    var fadeDepth: Float
    var cleanupDepth: Float
    /// Horizontal distance from the platform center where sideways fade starts.
    var horizontalFadeStart: Float
    var horizontalCleanup: Float

    init(config: DestructionPhysicsConfig) {
        fadeDepth = config.abyssFadeDepth
        cleanupDepth = max(config.abyssCleanupDepth, config.abyssFadeDepth + 1)
        horizontalFadeStart = max(config.platformWidth, config.platformDepth) * 1.6
        horizontalCleanup = GameRules.farCleanupDistance
    }

    func verdict(for position: SIMD3<Float>) -> Verdict {
        let depth = -position.y
        let horizontal = simd_length(SIMD2<Float>(position.x, position.z))
        if depth >= cleanupDepth || horizontal >= horizontalCleanup { return .remove }

        let vertical = ((depth - fadeDepth) / (cleanupDepth - fadeDepth)).clamped(0, 1)
        let sideways = ((horizontal - horizontalFadeStart) / (horizontalCleanup - horizontalFadeStart)).clamped(0, 1)
        let t = max(vertical, sideways)
        if t >= 1 { return .remove }
        return t > 0 ? .fade(t) : .keep
    }
}
