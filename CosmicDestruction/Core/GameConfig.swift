import Foundation

// Engine-agnostic configuration. Nothing in Core/ imports SceneKit, so the
// rules and tuning values survive a future move to RealityKit or another engine.

/// Central, tunable destruction-physics configuration (build sheet 2.0 §4.3).
/// Production defaults live here; the debug overlay edits a per-session copy
/// and never writes back to these defaults.
struct DestructionPhysicsConfig: Equatable {
    // MARK: Projectile
    var orbMass: Float = 12
    var orbRadius: Float = 0.4
    var orbRestitution: Float = 0.25
    var orbFriction: Float = 0.4
    var launchSpeed: Float = 24
    /// Extra impulse on the directly struck block, as a multiple of what the
    /// physics engine already transfers (1 = physics only).
    var orbImpulseMultiplier: Float = 1.6

    // MARK: Blocks
    /// Mass of a 0.8 m standard cube; other sizes scale by volume.
    var standardBlockMass: Float = 0.55
    /// Mass of a heavy block of the same volume.
    var heavyBlockMass: Float = 1.8
    var blockFriction: Float = 0.55
    var blockRestitution: Float = 0.12
    var blockLinearDamping: Float = 0.03
    var blockAngularDamping: Float = 0.06
    /// Damping applied during level settling and until the first shot, so
    /// stacks stay perfectly still before they are struck.
    var stabilizerDamping: Float = 0.92

    // MARK: Destruction (supplemental radial impulse, §4.4)
    var radialImpulseStrength: Float = 7.5
    var radialImpulseRadius: Float = 2.4
    /// Fraction of each radial impulse pointed upward.
    var verticalImpulseComponent: Float = 0.35
    /// How much the radial push leans along the orb's travel direction (0 = pure
    /// radial, 1 = pure forward). Keeps aim important.
    var forwardBias: Float = 0.45
    var maxSupplementalImpulse: Float = 9
    var maxBlockVelocity: Float = 22

    // MARK: Environment
    var gravityOverride: Float? = nil
    var platformWidth: Float = 18
    var platformDepth: Float = 16
    var platformThickness: Float = 2.5
    /// Depth below the platform top where falling debris starts to fade.
    var abyssFadeDepth: Float = 4
    /// Depth where faded debris is removed.
    var abyssCleanupDepth: Float = 22

    // MARK: Settling
    /// Speed (m/s) under which a block or orb counts as "settled".
    var settleSpeedThreshold: Float = 0.35

    // MARK: Camera
    var cameraElevation: Float = 7.6
    /// Distance from the cannon back to the camera along +Z.
    var cameraDistance: Float = 5.4
    var cameraFieldOfView: Float = 56
    var cameraShakeIntensity: Float = 1
}

/// Kept for source compatibility with v1 code.
typealias PhysicsTuning = DestructionPhysicsConfig

/// Fixed gameplay rules. Values that designers may want per-level live on
/// `LevelDefinition`; tunable physics lives on `DestructionPhysicsConfig`.
enum GameRules {
    // Cannon
    static let cannonPosition = SIMD3<Float>(0, 0, 6.2)
    static let yawLimitDegrees: Float = 32
    static let minElevationDegrees: Float = -4
    static let maxElevationDegrees: Float = 40
    static let defaultElevationDegrees: Float = 7
    static let aimSensitivityDegreesPerPoint: Float = 0.22

    // Target removal: a target block counts as removed once its center drops
    // below this plane (beneath the platform top) or leaves the play area.
    static let removalPlaneY: Float = -1.2
    static let playAreaHalfExtent: Float = 12.5
    /// Hard limit for anything flying far sideways.
    static let farCleanupDistance: Float = 70

    // Projectiles
    static let orbMaxLifetime: TimeInterval = 7
    static let orbCleanupY: Float = -24
    static let maxActiveOrbs = 3

    // Shot resolution timing (simulation seconds)
    static let minResolveTime: TimeInterval = 1.2
    static let maxResolveTime: TimeInterval = 5.0
    /// Quiet time after the last significant collision before a shot resolves.
    static let quietTimeAfterCollision: TimeInterval = 0.5
    static let failureSettleDelay: TimeInterval = 1.0
    /// Pause after victory before the overlay, so the collapse can play out.
    static let victoryCinematicDelay: TimeInterval = 1.1

    // Supplemental impulse safety
    static let significantOrbImpulse: Float = 4
    static let supplementalCooldown: TimeInterval = 0.3
    static let maxSupplementalPerOrb = 2

    // Slow motion
    static let slowMotionScale: Float = 0.3
    static let slowMotionDuration: TimeInterval = 0.45
    /// Fraction of target blocks that must be displaced within one shot to
    /// trigger the cinematic slow-motion beat.
    static let slowMotionDisplacedFraction: Float = 0.35
    static let blockDisplacedDistance: Float = 0.6

    // Debris trails
    static let debrisTrailSpeed: Float = 7
    static let maxDebrisTrails = 6
}
