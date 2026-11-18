import Foundation
import simd

/// The planet a block of levels is set on (build 5). Every 10 levels the
/// fight moves to a new world, starting on the Moon. A world is purely the
/// look: sky and its planet, ground tint, glowing vein colors and lighting.
/// Physics stay per level. Mirrors `WORLDS` in web-preview/index.html.
struct WorldTheme: Equatable {
    enum Key: String, CaseIterable { case moon, mars, mercury, venus, jupiter, saturn, uranus, neptune }

    struct Sky: Equatable {
        /// Vertical gradient: top, horizon, bottom (sRGB 0...1).
        var gradient: [SIMD3<Float>]
        var nebula: [SIMD3<Float>]
        var nebulaAlpha: ClosedRange<Float>
        /// Star count multiplier (0 = none, e.g. under Venus's clouds).
        var stars: Float
        /// Horizon haze color, if any.
        var haze: SIMD3<Float>?
    }

    struct Lighting: Equatable {
        var ambient: SIMD3<Float>, ambientIntensity: Float
        var key: SIMD3<Float>, keyIntensity: Float
        var rim: SIMD3<Float>, rimIntensity: Float
        var accent: SIMD3<Float>
        /// Glow deep under the island.
        var deep: SIMD3<Float>
    }

    var key: Key
    var name: String
    var tagline: String
    /// Linear multipliers on the island's top and side textures.
    var ground: SIMD3<Float>
    var rock: SIMD3<Float>
    /// Glowing vein colors: [0] edge accents and fractures, [1] crystals and veins.
    var veins: [SIMD3<Float>]
    var light: Lighting
    var sky: Sky

    static let levelsPerWorld = 10

    /// World for a 0-based level index.
    static func forLevel(index: Int) -> WorldTheme {
        all[min(all.count - 1, max(0, index) / levelsPerWorld)]
    }

    /// 1-based world number.
    var number: Int { (Self.all.firstIndex { $0.key == key } ?? 0) + 1 }

    /// Short name for the HUD ("MOON", "MARS").
    var shortName: String { name.replacingOccurrences(of: "The ", with: "").uppercased() }

    private static func hex(_ v: UInt32) -> SIMD3<Float> {
        SIMD3<Float>(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }
    private static func rgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { SIMD3<Float>(r, g, b) / 255 }

    static let all: [WorldTheme] = [
        WorldTheme(key: .moon, name: "The Moon", tagline: "Earthrise over the gray dust.",
                   ground: [1, 1, 1], rock: [1, 1, 1], veins: [rgb(51, 230, 255), rgb(153, 71, 255)],
                   light: Lighting(ambient: hex(0x5a66b3), ambientIntensity: 0.55, key: hex(0xbfeeff), keyIntensity: 1.6,
                                   rim: hex(0x9e4dff), rimIntensity: 1.3, accent: hex(0x9e4dff), deep: hex(0x1a0f38)),
                   sky: Sky(gradient: [hex(0x010205), hex(0x050818), hex(0x010205)],
                            nebula: [rgb(77, 31, 158), rgb(20, 51, 153), rgb(31, 97, 179)], nebulaAlpha: 0.05...0.13, stars: 1, haze: nil)),
        WorldTheme(key: .mars, name: "Mars", tagline: "Rust dunes under twin moons.",
                   ground: [2.1, 0.95, 0.62], rock: [1.8, 0.85, 0.6], veins: [rgb(255, 178, 46), rgb(255, 59, 78)],
                   light: Lighting(ambient: hex(0x8a5040), ambientIntensity: 0.6, key: hex(0xffd9b8), keyIntensity: 1.6,
                                   rim: hex(0xff6a3d), rimIntensity: 1.2, accent: hex(0xff8a3d), deep: hex(0x3a120a)),
                   sky: Sky(gradient: [hex(0x060206), hex(0x3c140e), hex(0x120506)],
                            nebula: [rgb(120, 40, 30), rgb(90, 30, 60), rgb(150, 70, 40)], nebulaAlpha: 0.03...0.08, stars: 0.55,
                            haze: rgb(220, 110, 60))),
        WorldTheme(key: .mercury, name: "Mercury", tagline: "Scorched rock, a sun that fills the sky.",
                   ground: [1.25, 1.1, 0.95], rock: [1.2, 1.05, 0.9], veins: [rgb(255, 210, 90), rgb(255, 120, 40)],
                   light: Lighting(ambient: hex(0x6a5a50), ambientIntensity: 0.5, key: hex(0xfff1d6), keyIntensity: 2.0,
                                   rim: hex(0xffa040), rimIntensity: 1.4, accent: hex(0xffb040), deep: hex(0x2a1405)),
                   sky: Sky(gradient: [hex(0x010101), hex(0x0b0705), hex(0x010101)],
                            nebula: [rgb(120, 60, 20), rgb(80, 40, 20), rgb(140, 90, 40)], nebulaAlpha: 0.02...0.06, stars: 1,
                            haze: rgb(255, 170, 80))),
        WorldTheme(key: .venus, name: "Venus", tagline: "Acid clouds and burning haze.",
                   ground: [1.8, 1.35, 0.7], rock: [1.6, 1.2, 0.65], veins: [rgb(125, 255, 77), rgb(255, 178, 46)],
                   light: Lighting(ambient: hex(0x8a7040), ambientIntensity: 0.75, key: hex(0xffe2a0), keyIntensity: 1.3,
                                   rim: hex(0xffb02e), rimIntensity: 1.0, accent: hex(0x7dff4d), deep: hex(0x3a2a08)),
                   sky: Sky(gradient: [hex(0x1e1206), hex(0xb06a22), hex(0x2a1806)],
                            nebula: [], nebulaAlpha: 0...0, stars: 0, haze: rgb(255, 190, 90))),
        WorldTheme(key: .jupiter, name: "Jupiter", tagline: "Io's sulfur fields beneath the giant.",
                   ground: [1.9, 1.65, 0.7], rock: [1.6, 1.3, 0.7], veins: [rgb(255, 64, 191), rgb(255, 140, 60)],
                   light: Lighting(ambient: hex(0x6a5060), ambientIntensity: 0.55, key: hex(0xffe8d0), keyIntensity: 1.5,
                                   rim: hex(0xff40bf), rimIntensity: 1.2, accent: hex(0xff40bf), deep: hex(0x2a0a20)),
                   sky: Sky(gradient: [hex(0x020104), hex(0x0c0710), hex(0x020104)],
                            nebula: [rgb(110, 40, 90), rgb(60, 30, 80), rgb(120, 70, 40)], nebulaAlpha: 0.03...0.08, stars: 0.9, haze: nil)),
        WorldTheme(key: .saturn, name: "Saturn", tagline: "A shard adrift inside the rings.",
                   ground: [1.55, 1.4, 1.1], rock: [1.4, 1.25, 1.0], veins: [rgb(255, 178, 46), rgb(51, 230, 255)],
                   light: Lighting(ambient: hex(0x6a6050), ambientIntensity: 0.55, key: hex(0xfff0d0), keyIntensity: 1.6,
                                   rim: hex(0xffb22e), rimIntensity: 1.2, accent: hex(0xffb22e), deep: hex(0x2a1e08)),
                   sky: Sky(gradient: [hex(0x020203), hex(0x0d0a06), hex(0x020203)],
                            nebula: [rgb(120, 90, 40), rgb(70, 50, 30), rgb(60, 60, 90)], nebulaAlpha: 0.03...0.07, stars: 0.9, haze: nil)),
        WorldTheme(key: .uranus, name: "Uranus", tagline: "Ice under a sideways world.",
                   ground: [0.95, 1.45, 1.55], rock: [0.9, 1.3, 1.45], veins: [rgb(51, 235, 255), rgb(120, 255, 210)],
                   light: Lighting(ambient: hex(0x407a80), ambientIntensity: 0.6, key: hex(0xd8ffff), keyIntensity: 1.5,
                                   rim: hex(0x33ebff), rimIntensity: 1.2, accent: hex(0x33ebff), deep: hex(0x082a2a)),
                   sky: Sky(gradient: [hex(0x010304), hex(0x04101a), hex(0x010304)],
                            nebula: [rgb(30, 120, 130), rgb(20, 80, 110), rgb(60, 140, 140)], nebulaAlpha: 0.03...0.08, stars: 1, haze: nil)),
        WorldTheme(key: .neptune, name: "Neptune", tagline: "The last blue giant before the dark.",
                   ground: [0.75, 1.0, 1.8], rock: [0.7, 0.9, 1.6], veins: [rgb(166, 102, 255), rgb(51, 235, 255)],
                   light: Lighting(ambient: hex(0x3a4aa0), ambientIntensity: 0.6, key: hex(0xc8d8ff), keyIntensity: 1.5,
                                   rim: hex(0xa666ff), rimIntensity: 1.3, accent: hex(0xa666ff), deep: hex(0x100a38)),
                   sky: Sky(gradient: [hex(0x010104), hex(0x040820), hex(0x010104)],
                            nebula: [rgb(50, 60, 180), rgb(90, 40, 170), rgb(30, 90, 180)], nebulaAlpha: 0.04...0.1, stars: 1, haze: nil)),
    ]
}
