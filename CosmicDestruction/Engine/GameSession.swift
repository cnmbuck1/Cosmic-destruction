import SceneKit
import Combine
import QuartzCore
import simd

/// What the HUD shows. Published only when it changes.
struct HUDState: Equatable {
    var levelNumber = 1
    var levelName = ""
    var shotsRemaining = 3
    var maxShots = 3
    var progress: Float = 0
    var threshold: Float = 0.8
    var isAiming = false
    var showHint = false
}

enum SessionOverlay: Equatable {
    case none
    case victory(stars: Int, shotsUsed: Int, hasNextLevel: Bool)
    case failure(progress: Float)
}

/// Developer stats for the debug overlay.
struct DebugStats: Equatable {
    var fps: Double = 0
    var rigidBodies = 0
    var gravity: Float = 0
    var launchSpeed: Float = 0
    var yaw: Float = 0
    var elevation: Float = 0
    var remainingTargets = 0
    var progress: Float = 0
    var timeScale: Float = 1
    var phase = ""
}

/// Coordinates one play session: owns the SceneKit systems and the
/// engine-agnostic GameManager, runs the main-thread game loop, and turns
/// touches into aiming. This is the seam between gameplay rules and the
/// rendering/physics engine.
@MainActor
final class GameSession: ObservableObject, AimInputDelegate {
    @Published private(set) var hud = HUDState()
    @Published private(set) var overlay: SessionOverlay = .none
    @Published private(set) var isPaused = false
    @Published private(set) var debugStats = DebugStats()
    @Published var showDebugPanel = false
    /// Live tuning (debug overlay edits this copy, never the production defaults).
    @Published var tuning = PhysicsTuning() {
        didSet { applyTuning(previous: oldValue) }
    }

    let sceneManager = SceneManager()
    let cannon = CannonController()
    let trajectory = TrajectoryIndicator()
    private(set) lazy var orbs = OrbController(parent: sceneManager.levelRoot)
    private(set) lazy var structure = StructureManager(parent: sceneManager.levelRoot)
    private(set) lazy var effects = EffectsManager(sceneManager: sceneManager)

    private let levelManager = LevelManager()
    private let gameManager: GameManager
    private(set) var levelIndex: Int
    private let progressStore: ProgressStore
    private let settings: SettingsStore
    private let audio = AudioManager.shared
    private var cancellables = Set<AnyCancellable>()

    private weak var view: GameSCNView?
    private var displayLink: CADisplayLink?
    private let contacts = ContactCollector()
    private var lastTimestamp: CFTimeInterval = 0
    /// Simulation clock: advances with physics speed, frozen while paused.
    private var simTime: TimeInterval = 0
    private var levelToken = UUID()

    // Aiming
    private var isDragging = false
    private var aimStartPoint = CGPoint.zero
    private var aimStartYaw: Float = 0
    private var aimStartElevation: Float = 0

    // Per-shot tracking
    private var currentOrb: OrbController.Orb?
    private var stabilizersReleased = false
    private var displacedThisShot = 0
    private var collapseTriggeredThisShot = false
    private var lastHapticTime: TimeInterval = 0

    // FPS / debug
    private var fpsFrames = 0
    private var fpsTime: Double = 0
    private var measuredFPS: Double = 0
    private var debugPublishTime: Double = 0

    var level: LevelDefinition { gameManager.level }
    var gravity: Float { sceneManager.gravity }

    init(levelIndex: Int, progress: ProgressStore, settings: SettingsStore) {
        let index = min(max(0, levelIndex), Levels.all.count - 1)
        self.levelIndex = index
        self.progressStore = progress
        self.settings = settings
        gameManager = GameManager(level: Levels.all[index])

        sceneManager.scene.rootNode.addChildNode(cannon.rootNode)
        sceneManager.scene.rootNode.addChildNode(trajectory.rootNode)
        sceneManager.scene.physicsWorld.contactDelegate = contacts

        effects.slowMotionEnabled = settings.slowMotionEnabled
        settings.$slowMotionEnabled
            .sink { [weak self] enabled in self?.effects.slowMotionEnabled = enabled }
            .store(in: &cancellables)

        loadLevel(index: index)
    }

    // MARK: View lifecycle

    func attach(to view: GameSCNView) {
        self.view = view
        view.scene = sceneManager.scene
        view.pointOfView = sceneManager.cameraNode
        view.aimDelegate = self
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true

        displayLink?.invalidate()
        let link = CADisplayLink(target: DisplayLinkProxy(session: self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = 0
        audio.prepareHaptics()
    }

    func detach() {
        displayLink?.invalidate()
        displayLink = nil
        view?.aimDelegate = nil
        view?.isPlaying = false
        view = nil
        effects.endSlowMotionImmediately()
    }

    // MARK: Level flow

    func loadLevel(index: Int) {
        guard let level = levelManager.level(at: index) else { return }
        levelIndex = index
        levelToken = UUID()

        effects.endSlowMotionImmediately()
        orbs.removeAll()
        structure.clear()
        sceneManager.clearLevel()
        effects.reset()

        sceneManager.setGravity(tuning.gravityOverride ?? level.gravity)
        sceneManager.setFieldOfView(tuning.cameraFieldOfView)
        structure.build(level: level, tuning: tuning)
        gameManager.start(level: level)
        cannon.resetAim()

        currentOrb = nil
        isDragging = false
        stabilizersReleased = false
        displacedThisShot = 0
        collapseTriggeredThisShot = false
        overlay = .none
        setPaused(false)
        updateTrajectory(emphasis: 0.35)
        publishHUD()
    }

    func restart() {
        audio.play(.menu)
        loadLevel(index: levelIndex)
    }

    func nextLevel() {
        audio.play(.menu)
        let next = levelManager.hasLevel(after: levelIndex) ? levelIndex + 1 : levelIndex
        loadLevel(index: next)
    }

    var hasNextLevel: Bool { levelManager.hasLevel(after: levelIndex) }

    func pause() {
        guard overlay == .none, !isPaused else { return }
        audio.play(.menu)
        setPaused(true)
    }

    func resume() {
        guard isPaused else { return }
        audio.play(.menu)
        setPaused(false)
    }

    private func setPaused(_ paused: Bool) {
        isPaused = paused
        sceneManager.scene.isPaused = paused
        if paused {
            isDragging = false
            cannon.cancelCharging()
        }
        lastTimestamp = 0
        publishHUD()
    }

    // MARK: Aiming input

    private var canAim: Bool { !isPaused && overlay == .none && gameManager.canFire }

    func aimBegan(at point: CGPoint) {
        guard canAim else { return }
        isDragging = true
        aimStartPoint = point
        aimStartYaw = cannon.yawDegrees
        aimStartElevation = cannon.elevationDegrees
        cannon.beginCharging()
        audio.play(.charge, volume: 0.55)
        updateTrajectory(emphasis: 1)
        publishHUD()
    }

    func aimMoved(to point: CGPoint) {
        guard isDragging else { return }
        let sensitivity = GameRules.aimSensitivityDegreesPerPoint
        let dx = Float(point.x - aimStartPoint.x)
        let dy = Float(point.y - aimStartPoint.y)
        // Drag right = aim right; drag up = raise elevation.
        cannon.setAim(yawDegrees: aimStartYaw + dx * sensitivity,
                      elevationDegrees: aimStartElevation - dy * sensitivity)
        updateTrajectory(emphasis: 1)
    }

    func aimEnded(at point: CGPoint) {
        guard isDragging else { return }
        aimMoved(to: point)
        isDragging = false
        fire()
    }

    func aimCancelled() {
        guard isDragging else { return }
        isDragging = false
        cannon.cancelCharging()
        updateTrajectory(emphasis: 0.35)
        publishHUD()
    }

    private func updateTrajectory(emphasis: Float) {
        guard gameManager.canFire else { trajectory.hide(); return }
        trajectory.update(origin: cannon.muzzleWorldPosition,
                          velocity: cannon.launchDirection * tuning.launchSpeed,
                          gravity: sceneManager.gravity,
                          emphasis: emphasis)
    }

    // MARK: Firing

    private func fire() {
        guard canAim, gameManager.registerShot(at: simTime) else { return }
        if !stabilizersReleased {
            structure.setStabilized(false, tuning: tuning)
            stabilizersReleased = true
        }
        let origin = cannon.muzzleWorldPosition
        currentOrb = orbs.launch(from: origin, direction: cannon.launchDirection, tuning: tuning, time: simTime)
        cannon.playFireAnimation()
        effects.muzzleFlash(at: origin)
        effects.shake(amplitude: 0.05, duration: 0.18)
        audio.play(.launch)
        audio.hapticFire()
        trajectory.hide()
        displacedThisShot = 0
        collapseTriggeredThisShot = false
        publishHUD()
    }

    // MARK: Game loop

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let rawDt = lastTimestamp == 0 ? 1.0 / 60.0 : now - lastTimestamp
        lastTimestamp = now
        let dt = min(rawDt, 1.0 / 20.0)
        measureFPS(rawDt)

        guard !isPaused else { return }

        simTime += dt * Double(effects.timeScale)
        effects.update(dt: Float(dt))
        cannon.update(dt: Float(dt))
        orbs.update(time: simTime)
        processContacts()

        let result = structure.update()
        if result.newlyDisplacedTargets > 0 {
            displacedThisShot += result.newlyDisplacedTargets
            checkForMajorCollapse()
        }
        if result.newlyRemovedTargets > 0 {
            publishHUD()
        }

        updateGameState()
        publishDebug(dt: dt)
    }

    private func updateGameState() {
        switch gameManager.phase {
        case .resolving:
            let progress = structure.progress
            let ended = gameManager.shouldEndResolution(
                at: simTime,
                orbResolved: orbs.isResolved(currentOrb, time: simTime, settleSpeed: tuning.settleSpeedThreshold * 2),
                structureSettled: structure.isSettled(threshold: tuning.settleSpeedThreshold),
                objectiveMet: progress >= level.victoryThreshold)
            if ended {
                handle(phase: gameManager.evaluate(progress: progress, at: simTime))
            }
        case .failing:
            let phase = gameManager.updateFailing(progress: structure.progress, at: simTime)
            if phase != .failing { handle(phase: phase) }
        default:
            break
        }
    }

    private func handle(phase: GamePhase) {
        let token = levelToken
        switch phase {
        case .aiming:
            currentOrb = nil
            updateTrajectory(emphasis: 0.35)
        case .won(let stars, let shotsUsed):
            progressStore.recordCompletion(levelIndex: levelIndex, levelID: level.id, stars: stars,
                                           levelCount: levelManager.count)
            trajectory.hide()
            // Let the collapse breathe for a moment before the overlay.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let self, self.levelToken == token else { return }
                self.audio.play(.victory)
                self.audio.hapticVictory()
                self.overlay = .victory(stars: stars, shotsUsed: shotsUsed, hasNextLevel: self.hasNextLevel)
            }
        case .failed(let progress):
            trajectory.hide()
            audio.play(.failure)
            overlay = .failure(progress: progress)
        case .failing, .resolving:
            trajectory.hide()
        }
        publishHUD()
    }

    /// Cinematic beat when a big chunk of the structure goes at once.
    private func checkForMajorCollapse() {
        guard gameManager.phase == .resolving, !collapseTriggeredThisShot else { return }
        let needed = Int((Float(structure.targetCount) * GameRules.slowMotionDisplacedFraction).rounded(.up))
        guard displacedThisShot >= needed else { return }
        collapseTriggeredThisShot = true
        effects.triggerSlowMotion()
        effects.shake(amplitude: 0.1, duration: 0.5)
        audio.play(.collapse, volume: 0.9)
        audio.hapticImpact(intensity: 0.9)
    }

    // MARK: Contacts

    private func processContacts() {
        for contact in contacts.drain() {
            let a = contact.nodeA, b = contact.nodeB
            if let orb = orbs.orb(for: a) ?? orbs.orb(for: b) {
                let other = orb.node === a ? b : a
                if structure.block(for: other) != nil {
                    orbHitBlock(orb, contact: contact)
                } else if contact.impulse > 10 {
                    effects.dust(at: contact.point, intensity: 0.5, time: simTime)
                    audio.play(.blockHit, volume: 0.35, minInterval: 0.1)
                }
                continue
            }
            // Block-on-block or block-on-platform.
            guard contact.impulse > 2.5 else { continue }
            let intensity = (contact.impulse / 25).clamped(0, 1)
            effects.dust(at: contact.point, intensity: intensity, time: simTime)
            audio.play(.blockHit, volume: 0.15 + 0.45 * intensity, minInterval: 0.06)
        }
    }

    private func orbHitBlock(_ orb: OrbController.Orb, contact: RecordedContact) {
        let first = orb.impactCount == 0
        guard first || contact.impulse > 6 else { return }
        orb.impactCount += 1
        let intensity = max((contact.impulse / 40).clamped(0, 1), first ? 0.6 : 0)
        effects.impact(at: contact.point, intensity: intensity)
        audio.play(.impact, volume: 0.4 + 0.6 * intensity, minInterval: 0.08)
        if first {
            effects.shake(amplitude: 0.06 + 0.06 * intensity, duration: 0.25)
        }
        if intensity > 0.3, simTime - lastHapticTime > 0.15 {
            lastHapticTime = simTime
            audio.hapticImpact(intensity: intensity)
        }
    }

    // MARK: Tuning (debug)

    private func applyTuning(previous: PhysicsTuning) {
        if tuning.gravityOverride != previous.gravityOverride {
            sceneManager.setGravity(tuning.gravityOverride ?? level.gravity)
        }
        if tuning.cameraFieldOfView != previous.cameraFieldOfView {
            sceneManager.setFieldOfView(tuning.cameraFieldOfView)
        }
        if tuning.blockMass != previous.blockMass
            || tuning.blockFriction != previous.blockFriction
            || tuning.blockRestitution != previous.blockRestitution {
            structure.apply(tuning: tuning)
        }
        // Orb mass/speed apply to the next shot. Settle threshold is read live.
        if gameManager.canFire { updateTrajectory(emphasis: isDragging ? 1 : 0.35) }
    }

    func resetTuning() {
        tuning = PhysicsTuning()
    }

    // MARK: Publishing

    private func publishHUD() {
        let state = HUDState(
            levelNumber: levelIndex + 1,
            levelName: level.name,
            shotsRemaining: gameManager.shotsRemaining,
            maxShots: level.maxShots,
            progress: structure.progress,
            threshold: level.victoryThreshold,
            isAiming: isDragging,
            showHint: levelIndex == 0 && gameManager.shotsUsed == 0 && !isDragging
        )
        if state != hud { hud = state }
    }

    private func measureFPS(_ dt: Double) {
        fpsFrames += 1
        fpsTime += dt
        if fpsTime >= 0.5 {
            measuredFPS = Double(fpsFrames) / fpsTime
            fpsFrames = 0
            fpsTime = 0
        }
    }

    private func publishDebug(dt: Double) {
        guard showDebugPanel else { return }
        debugPublishTime += dt
        guard debugPublishTime >= 0.25 else { return }
        debugPublishTime = 0
        let phaseName: String
        switch gameManager.phase {
        case .aiming: phaseName = "aiming"
        case .resolving: phaseName = "resolving"
        case .failing: phaseName = "failing"
        case .won: phaseName = "won"
        case .failed: phaseName = "failed"
        }
        debugStats = DebugStats(
            fps: measuredFPS,
            rigidBodies: structure.activeBodyCount + orbs.activeCount,
            gravity: sceneManager.gravity,
            launchSpeed: tuning.launchSpeed,
            yaw: cannon.yawDegrees,
            elevation: cannon.elevationDegrees,
            remainingTargets: structure.remainingTargetCount,
            progress: structure.progress,
            timeScale: effects.timeScale,
            phase: phaseName
        )
    }
}

/// CADisplayLink retains its target; this proxy holds the session weakly so
/// the session can deallocate when the game screen closes.
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var session: GameSession?

    init(session: GameSession) {
        self.session = session
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let session else {
            link.invalidate()
            return
        }
        session.tick(link)
    }
}
