import Foundation

/// High-level state of a level in progress.
enum GamePhase: Equatable {
    /// Player may aim and fire.
    case aiming
    /// A shot is in flight / physics is settling. No firing allowed.
    case resolving
    /// Out of shots without reaching the objective; waiting briefly before
    /// showing the failure overlay so the last collapse can play out.
    case failing
    case won(stars: Int, shotsUsed: Int)
    case failed(progress: Float)
}

/// Engine-agnostic rules: shots, resolution timing, victory/failure, scoring.
/// Time values are simulation seconds supplied by the caller, so the manager
/// is trivially unit-testable and unaffected by pause.
final class GameManager {
    private(set) var level: LevelDefinition
    private(set) var phase: GamePhase = .aiming
    private(set) var shotsUsed = 0
    private(set) var shotStartTime: TimeInterval = 0
    private var failAt: TimeInterval = 0

    init(level: LevelDefinition) {
        self.level = level
    }

    var shotsRemaining: Int { max(0, level.maxShots - shotsUsed) }
    var canFire: Bool { phase == .aiming && shotsRemaining > 0 }
    var isFinished: Bool {
        switch phase {
        case .won, .failed: return true
        default: return false
        }
    }

    func start(level: LevelDefinition) {
        self.level = level
        phase = .aiming
        shotsUsed = 0
        shotStartTime = 0
        failAt = 0
    }

    /// Records a shot. Returns false if firing isn't currently allowed.
    @discardableResult
    func registerShot(at time: TimeInterval) -> Bool {
        guard canFire else { return false }
        shotsUsed += 1
        shotStartTime = time
        phase = .resolving
        return true
    }

    /// Whether the current shot has resolved: the orb is done and the structure
    /// has settled (after a minimum time), or the maximum time has elapsed.
    /// Once the objective is met we don't wait for every block to stop.
    func shouldEndResolution(at time: TimeInterval, orbResolved: Bool, structureSettled: Bool,
                             objectiveMet: Bool = false) -> Bool {
        guard phase == .resolving else { return false }
        let elapsed = time - shotStartTime
        if elapsed >= GameRules.maxResolveTime { return true }
        guard elapsed >= GameRules.minResolveTime else { return false }
        return objectiveMet || (orbResolved && structureSettled)
    }

    /// Evaluates the objective after a shot resolves and moves to the next phase.
    @discardableResult
    func evaluate(progress: Float, at time: TimeInterval) -> GamePhase {
        guard phase == .resolving else { return phase }
        if progress >= level.victoryThreshold {
            phase = .won(stars: level.stars(forShotsUsed: shotsUsed), shotsUsed: shotsUsed)
        } else if shotsRemaining == 0 {
            phase = .failing
            failAt = time + GameRules.failureSettleDelay
        } else {
            phase = .aiming
        }
        return phase
    }

    /// While failing, blocks may still be falling. A late victory still counts.
    @discardableResult
    func updateFailing(progress: Float, at time: TimeInterval) -> GamePhase {
        guard phase == .failing else { return phase }
        if progress >= level.victoryThreshold {
            phase = .won(stars: level.stars(forShotsUsed: shotsUsed), shotsUsed: shotsUsed)
        } else if time >= failAt {
            phase = .failed(progress: progress)
        }
        return phase
    }
}
