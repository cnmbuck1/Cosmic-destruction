import Foundation

// Engine-agnostic configuration. Nothing in Core/ imports SceneKit, so the
// rules and tuning values survive a future move to RealityKit or another engine.

/// Physics tuning values. Production defaults live here; the debug overlay edits
/// a per-session copy and never writes back to these defaults.
struct PhysicsTuning: Equatable {
    // Orb
    var orbMass: Float = 9
    var orbRadius: Float = 0.38
    var orbRestitution: Float = 0.3
    var orbFriction: Float = 0.45
    var launchSpeed: Float = 21

    // Blocks
    var blockMass: Float = 1.0
    var heavyMassMultiplier: Float = 3.5
    var blockFriction: Float = 0.7
    var blockRestitution: Float = 0.08
    var blockLinearDamping: Float = 0.06
    var blockAngularDamping: Float = 0.1

    /// Damping applied before the first shot so stacks stay perfectly still.
    var stabilizerDamping: Float = 0.92

    /// Speed (m/s) under which a block or orb counts as "settled".
    var settleSpeedThreshold: Float = 0.35

    // Camera
    var cameraFieldOfView: Float = 50

    /// When non-nil, overrides the level's gravity (debug only).
    var gravityOverride: Float? = nil
}

/// Fixed gameplay rules. Values that designers may want per-level live on
/// `LevelDefinition` instead.
enum GameRules {
    // Platform footprint (meters). Top surface sits at y = 0.
    static let platformWidth: Float = 16
    static let platformDepth: Float = 14
    static let platformThickness: Float = 1.5

    // Cannon
    static let cannonPosition = SIMD3<Float>(0, 0, 5.9)
    static let yawLimitDegrees: Float = 32
    static let minElevationDegrees: Float = -4
    static let maxElevationDegrees: Float = 40
    static let defaultElevationDegrees: Float = 8
    static let aimSensitivityDegreesPerPoint: Float = 0.22

    // Target removal: a target block counts as removed once its center drops
    // below this plane (beneath the platform) or leaves the play area.
    static let removalPlaneY: Float = -1.6
    static let playAreaHalfExtent: Float = 12.5

    // Abyss: blocks fade/shrink between these depths, then get removed.
    static let abyssFadeStartY: Float = -5
    static let abyssCleanupY: Float = -18

    // Projectiles
    static let orbMaxLifetime: TimeInterval = 7
    static let orbCleanupY: Float = -18
    static let maxActiveOrbs = 3

    // Shot resolution timing (simulation seconds)
    static let minResolveTime: TimeInterval = 1.0
    static let maxResolveTime: TimeInterval = 4.5
    static let failureSettleDelay: TimeInterval = 1.0

    // Slow motion
    static let slowMotionScale: Float = 0.3
    static let slowMotionDuration: TimeInterval = 0.4
    /// Fraction of target blocks that must be displaced within one shot to
    /// trigger the cinematic slow-motion beat.
    static let slowMotionDisplacedFraction: Float = 0.35
    static let blockDisplacedDistance: Float = 0.6
}
