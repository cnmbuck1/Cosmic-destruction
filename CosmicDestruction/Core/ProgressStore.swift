import Foundation
import Combine

/// Local progression, persisted in UserDefaults. No accounts, no cloud.
final class ProgressStore: ObservableObject {
    private enum Key {
        static let highestUnlocked = "progress.highestUnlockedIndex"
        static let bestStars = "progress.bestStars"
    }

    private let defaults: UserDefaults

    /// Zero-based index of the highest unlocked level.
    @Published private(set) var highestUnlockedIndex: Int
    /// Best star rating per level id.
    @Published private(set) var bestStars: [Int: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        highestUnlockedIndex = defaults.integer(forKey: Key.highestUnlocked)
        let stored = defaults.dictionary(forKey: Key.bestStars) as? [String: Int] ?? [:]
        bestStars = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
    }

    func isUnlocked(index: Int) -> Bool { index <= highestUnlockedIndex }

    func stars(forLevelID id: Int) -> Int { bestStars[id] ?? 0 }

    /// Records a completed level and unlocks the next one.
    func recordCompletion(levelIndex: Int, levelID: Int, stars: Int, levelCount: Int) {
        if stars > (bestStars[levelID] ?? 0) {
            bestStars[levelID] = stars
        }
        let next = min(levelIndex + 1, levelCount - 1)
        if next > highestUnlockedIndex {
            highestUnlockedIndex = next
        }
        save()
    }

    func reset() {
        highestUnlockedIndex = 0
        bestStars = [:]
        save()
    }

    private func save() {
        defaults.set(highestUnlockedIndex, forKey: Key.highestUnlocked)
        let stored = Dictionary(uniqueKeysWithValues: bestStars.map { (String($0.key), $0.value) })
        defaults.set(stored, forKey: Key.bestStars)
    }
}

/// Player settings, persisted in UserDefaults.
final class SettingsStore: ObservableObject {
    private enum Key {
        static let sound = "settings.soundEnabled"
        static let haptics = "settings.hapticsEnabled"
        static let debugOverlay = "settings.debugOverlayEnabled"
        static let slowMotion = "settings.slowMotionEnabled"
    }

    private let defaults: UserDefaults

    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    /// Developer-only: shows the debug button in the HUD.
    @Published var debugOverlayEnabled: Bool { didSet { defaults.set(debugOverlayEnabled, forKey: Key.debugOverlay) } }
    /// Developer-only: lets slow motion be switched off while debugging.
    @Published var slowMotionEnabled: Bool { didSet { defaults.set(slowMotionEnabled, forKey: Key.slowMotion) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.sound: true,
            Key.haptics: true,
            Key.debugOverlay: false,
            Key.slowMotion: true,
        ])
        soundEnabled = defaults.bool(forKey: Key.sound)
        hapticsEnabled = defaults.bool(forKey: Key.haptics)
        debugOverlayEnabled = defaults.bool(forKey: Key.debugOverlay)
        slowMotionEnabled = defaults.bool(forKey: Key.slowMotion)
    }
}
