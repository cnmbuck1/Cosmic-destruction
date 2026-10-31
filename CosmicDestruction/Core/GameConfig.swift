import Foundation

// Engine-agnostic configuration. Nothing in Core/ imports SceneKit, so the
// rules and tuning values survive a future move to RealityKit or another engine.

/// Tunable high-energy impact (build 3.0 §3). On a significant orb hit, every
/// block within `radius` of the impact gets a velocity change that follows the
/// orb's incoming direction, plus radial and upward scatter and tumble. Closer
/// blocks get more (distance falloff); heavier blocks resist slightly. It is
/// never a uniform explosion: the incoming direction and impact point decide
/// the result.
struct ImpactPreset: Equatable, Identifiable {
    enum ID: String, CaseIterable { case a = "A", b = "B", c = "C" }
    var id: ID
    var name: String
    /// Peak velocity change (m/s) at the impact point for a full-energy hit.
    var velocityChange: Float
    var radius: Float
    /// Direction weights: along the incoming direction, horizontal radial
    /// scatter away from the impact, and upward lift.
    var forwardWeight: Float
    var radialWeight: Float
    var upwardWeight: Float
    /// Tumble (rad/s) at the impact point.
    var spin: Float
    /// Maximum velocity change any one block can receive.
    var maxVelocityChange: Float
    /// Exponent of the (1 - d/r) distance falloff (1 = linear).
    var falloffExponent: Float

    static let moderate = ImpactPreset(id: .a, name: "Moderate", velocityChange: 6.5, radius: 2.0,
                                       forwardWeight: 0.7, radialWeight: 0.35, upwardWeight: 0.25,
                                       spin: 3, maxVelocityChange: 9, falloffExponent: 1.4)
    static let powerful = ImpactPreset(id: .b, name: "Powerful", velocityChange: 10.5, radius: 2.0,
                                       forwardWeight: 0.7, radialWeight: 0.3, upwardWeight: 0.35,
                                       spin: 5, maxVelocityChange: 14, falloffExponent: 1.2)
    static let spectacular = ImpactPreset(id: .c, name: "Spectacular", velocityChange: 15, radius: 3.2,
                                          forwardWeight: 0.6, radialWeight: 0.5, upwardWeight: 0.45,
                                          spin: 8, maxVelocityChange: 20, falloffExponent: 1.0)
    static let all: [ImpactPreset] = [.moderate, .powerful, .spectacular]

    static func preset(_ id: ID) -> ImpactPreset { all.first { $0.id == id } ?? .powerful }
}

/// Objective and score rules (build 3.0 §5). Progress comes from structural
/// displacement; launching blocks into the abyss earns a bonus on top.
struct ScoringConfig: Equatable {
    /// A target counts as structurally destroyed once it moves this far from its slot...
    var displacedDistance: Float = 0.7
    /// ...or tips more than this many degrees. Small nudges count for nothing.
    var displacedTiltDegrees: Float = 30
    var pointsPerDisplaced = 100
    var pointsPerAbyss = 150
    var pointsPerShotLeft = 250
}

/// Central, tunable destruction-physics configuration (build sheet 2.0 §4.3,
/// retuned for build 3.0). Production defaults live here; the debug overlay
/// edits a per-session copy and never writes back to these defaults.
struct DestructionPhysicsConfig: Equatable {
    // MARK: Projectile
    var orbMass: Float = 14
    var orbRadius: Float = 0.4
    var orbRestitution: Float = 0.25
    var orbFriction: Float = 0.4
    var launchSpeed: Float = 30

    // MARK: Blocks
    /// Mass of a 0.8 m standard cube; other sizes scale by volume.
    var standardBlockMass: Float = 0.55
    /// Mass of a heavy block of the same volume.
    var heavyBlockMass: Float = 1.8
    var blockFriction: Float = 0.42
    var blockRestitution: Float = 0.12
    var blockLinearDamping: Float = 0.02
    var blockAngularDamping: Float = 0.04
    /// Damping applied during level settling and until the first shot, so
    /// stacks stay perfectly still before they are struck.
    var stabilizerDamping: Float = 0.92

    // MARK: Impact (build 3.0 §3)
    var impact: ImpactPreset = .powerful
    var maxBlockVelocity: Float = 26

    // MARK: Scoring
    var scoring = ScoringConfig()

    // MARK: Environment
    var gravityOverride: Float? = nil
    /// Compact floating island (build 3.0 §1).
    var platformWidth: Float = 7.8
    var platformDepth: Float = 10
    /// Island center along Z. The cannon sits near its front edge and the
    /// structure near the far edge with clearance on every side.
    var platformCenterZ: Float = -0.6
    var platformThickness: Float = 2.2
    /// Depth below the platform top where falling debris starts to fade.
    var abyssFadeDepth: Float = 4
    /// Depth where faded debris is removed.
    var abyssCleanupDepth: Float = 22

    // MARK: Settling
    /// Speed (m/s) under which a block or orb counts as "settled".
    var settleSpeedThreshold: Float = 0.35

    // MARK: Camera (build 3.0 §2)
    var cameraElevation: Float = 5.4
    /// Distance from the cannon back to the camera along +Z.
    var cameraDistance: Float = 4.2
    /// Height of the look-at point above the platform.
    var cameraLookHeight: Float = 1.2
    /// How far in front of the structure origin (toward the cannon) the camera looks.
    var cameraLookAhead: Float = 0.6
    /// Horizontal field of view in degrees (portrait framing is width-limited).
    var cameraFieldOfView: Float = 38
    var cameraShakeIntensity: Float = 1
}

/// Kept for source compatibility with v1 code.
typealias PhysicsTuning = DestructionPhysicsConfig

/// Fixed gameplay rules. Values that designers may want per-level live on
/// `LevelDefinition`; tunable physics lives on `DestructionPhysicsConfig`.
enum GameRules {
    // Cannon
    static let cannonPosition = SIMD3<Float>(0, 0, 3.4)
    /// The cannon is drawn smaller so the target, not the turret, dominates.
    static let cannonScale: Float = 0.72
    static let yawLimitDegrees: Float = 32
    static let minElevationDegrees: Float = -6
    static let maxElevationDegrees: Float = 40
    static let defaultElevationDegrees: Float = 7
    static let aimSensitivityDegreesPerPoint: Float = 0.2

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

    // High-energy impact safety
    static let significantOrbImpulse: Float = 4
    static let supplementalCooldown: TimeInterval = 0.25
    static let maxSupplementalPerOrb = 2

    // Slow motion
    static let slowMotionScale: Float = 0.3
    static let slowMotionDuration: TimeInterval = 0.5
    /// Fraction of target blocks that must be displaced within one shot to
    /// trigger the cinematic slow-motion beat.
    static let slowMotionDisplacedFraction: Float = 0.3

    // Debris trails
    static let debrisTrailSpeed: Float = 6
    static let maxDebrisTrails = 8
}
