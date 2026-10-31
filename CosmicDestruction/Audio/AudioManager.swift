import AVFoundation
import UIKit

enum SoundEffect: CaseIterable {
    case charge, launch, impact, blockHit, collapse, victory, failure, menu
}

/// Sound effects, background ambience, and haptics. Every call is safe when
/// audio fails to start or is disabled in settings.
@MainActor
final class AudioManager {
    static let shared = AudioManager()

    var soundEnabled = true {
        didSet { soundEnabled ? startAmbience() : stopAmbience() }
    }
    var hapticsEnabled = true

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private let ambiencePlayer = AVAudioPlayerNode()
    private var nextPlayer = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var ambienceBuffer: AVAudioPCMBuffer?
    private var isReady = false
    private var lastPlayed: [SoundEffect: TimeInterval] = [:]

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    /// Synthesizes buffers and starts the engine. Call once at launch.
    func prepare() {
        guard !isReady else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Audio] Session setup failed: \(error)")
        }

        buffers[.charge] = SoundSynth.charge()
        buffers[.launch] = SoundSynth.launch()
        buffers[.impact] = SoundSynth.impact()
        buffers[.blockHit] = SoundSynth.blockHit()
        buffers[.collapse] = SoundSynth.collapse()
        buffers[.victory] = SoundSynth.victory()
        buffers[.failure] = SoundSynth.failure()
        buffers[.menu] = SoundSynth.menu()
        ambienceBuffer = SoundSynth.ambience()

        let format = SoundSynth.format
        for _ in 0..<8 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.attach(ambiencePlayer)
        engine.connect(ambiencePlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9

        do {
            try engine.start()
            isReady = true
            if soundEnabled { startAmbience() }
        } catch {
            print("[Audio] Engine failed to start: \(error). Continuing silently.")
        }
    }

    // MARK: Sound

    /// Plays an effect. `minInterval` throttles rapid repeats (e.g. block hits).
    func play(_ effect: SoundEffect, volume: Float = 1, minInterval: TimeInterval = 0) {
        guard soundEnabled, isReady, let buffer = buffers[effect] else { return }
        let now = CACurrentMediaTime()
        if minInterval > 0, let last = lastPlayed[effect], now - last < minInterval { return }
        lastPlayed[effect] = now
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = max(0, min(1, volume))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func startAmbience() {
        guard isReady, let buffer = ambienceBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning, !ambiencePlayer.isPlaying else { return }
        ambiencePlayer.volume = 0.35
        ambiencePlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        ambiencePlayer.play()
    }

    private func stopAmbience() {
        ambiencePlayer.stop()
    }

    // MARK: Haptics (restrained: firing, significant impacts, victory)

    func hapticFire() {
        guard hapticsEnabled else { return }
        mediumImpact.impactOccurred(intensity: 0.8)
    }

    func hapticImpact(intensity: Float) {
        guard hapticsEnabled else { return }
        if intensity > 0.7 {
            heavyImpact.impactOccurred(intensity: CGFloat(min(1, intensity)))
        } else {
            lightImpact.impactOccurred(intensity: CGFloat(max(0.3, intensity)))
        }
    }

    func hapticVictory() {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(.success)
    }

    func prepareHaptics() {
        guard hapticsEnabled else { return }
        mediumImpact.prepare()
        lightImpact.prepare()
    }
}
