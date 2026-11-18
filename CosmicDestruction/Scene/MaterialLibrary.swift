import SceneKit
import UIKit
import simd

/// Palette for the whole game.
enum Palette {
    static let cyan = UIColor(red: 0.2, green: 0.92, blue: 1.0, alpha: 1)
    static let purple = UIColor(red: 0.62, green: 0.3, blue: 1.0, alpha: 1)
    static let magenta = UIColor(red: 1.0, green: 0.25, blue: 0.75, alpha: 1)
    static let energyWhite = UIColor(red: 0.85, green: 0.97, blue: 1.0, alpha: 1)
    static let graphite = UIColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1)
    static let midnight = UIColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1)
}

/// Shared materials and generated textures. Sharing materials (and geometry,
/// see StructureManager) keeps draw-call state changes and memory low.
@MainActor
final class MaterialLibrary {
    static let shared = MaterialLibrary()

    private init() {}

    static func pbr(diffuse: Any, metalness: Float, roughness: Float, emission: Any? = nil, emissionIntensity: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = diffuse
        m.metalness.contents = NSNumber(value: metalness)
        m.roughness.contents = NSNumber(value: roughness)
        if let emission {
            m.emission.contents = emission
            m.emission.intensity = emissionIntensity
        }
        return m
    }

    /// Unlit, additive glow material for energy effects.
    static func glow(_ contents: Any, additive: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = contents
        m.blendMode = additive ? .add : .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    // MARK: Textures

    // MARK: Worlds (build 5)

    private struct WorldTextures {
        let sky: UIImage, topDiffuse: UIImage, topEmission: UIImage, strataDiffuse: UIImage, strataEmission: UIImage
    }
    /// Only the current world's textures are kept (a 4096 x 2048 sky is 32 MB).
    private var worldTextures: (key: WorldTheme.Key, textures: WorldTextures)?
    private(set) var currentWorld: WorldTheme.Key?

    private func textures(for world: WorldTheme) -> WorldTextures {
        if let cached = worldTextures, cached.key == world.key { return cached.textures }
        let t = WorldTextures(sky: SkyPainter.image(for: world),
                              topDiffuse: ProceduralTextures.lunarSurfaceDiffuse(tint: world.ground),
                              topEmission: ProceduralTextures.lunarSurfaceEmission(veins: world.veins),
                              strataDiffuse: ProceduralTextures.strataDiffuse(tint: world.rock),
                              strataEmission: ProceduralTextures.strataEmission(veins: world.veins))
        worldTextures = (world.key, t)
        return t
    }

    static func uiColor(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
    }

    /// Recolors the shared island materials for a world and returns its sky.
    @discardableResult
    func apply(world: WorldTheme) -> UIImage {
        let t = textures(for: world)
        currentWorld = world.key
        platformTop.diffuse.contents = t.topDiffuse
        platformTop.emission.contents = t.topEmission
        platformStrata.diffuse.contents = t.strataDiffuse
        platformStrata.emission.contents = t.strataEmission
        rimCyan.emission.contents = Self.uiColor(world.veins[0])
        crystal.emission.contents = Self.uiColor(world.veins[1])
        energyCircle.multiply.contents = Self.uiColor(simd_mix(world.veins[0], SIMD3<Float>(repeating: 1), SIMD3<Float>(repeating: 0.25)))
        return t.sky
    }
    lazy var glowImage: UIImage = ProceduralTextures.radialGlow()
    lazy var shockwaveImage: UIImage = ProceduralTextures.shockwaveRing()

    // MARK: Platform

    /// Cratered lunar rock with sparse glowing fractures (no grid or rings).
    lazy var platformTop: SCNMaterial = {
        let m = Self.pbr(diffuse: ProceduralTextures.lunarSurfaceDiffuse(), metalness: 0.05, roughness: 0.92,
                         emission: ProceduralTextures.lunarSurfaceEmission(), emissionIntensity: 1.2)
        m.normal.contents = ProceduralTextures.lunarSurfaceNormal()
        m.normal.intensity = 0.8
        return m
    }()

    /// Layered strata for the fragment's sides and underside.
    lazy var platformStrata: SCNMaterial = {
        let m = Self.pbr(diffuse: ProceduralTextures.strataDiffuse(), metalness: 0.05, roughness: 0.95,
                         emission: ProceduralTextures.strataEmission(), emissionIntensity: 1.1)
        for prop in [m.diffuse, m.emission] {
            prop.wrapS = .repeat
            prop.wrapT = .repeat
        }
        return m
    }()

    lazy var platformRock: SCNMaterial = Self.pbr(
        diffuse: UIColor(red: 0.07, green: 0.07, blue: 0.1, alpha: 1), metalness: 0.1, roughness: 0.95)

    lazy var rimCyan: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.black
        m.emission.contents = Palette.cyan
        m.emission.intensity = 1.8
        m.isDoubleSided = true
        return m
    }()

    lazy var crystal: SCNMaterial = Self.pbr(diffuse: UIColor(red: 0.16, green: 0.08, blue: 0.3, alpha: 1),
                                             metalness: 0.3, roughness: 0.2, emission: Palette.purple, emissionIntensity: 0.9)

    /// Additive ring pattern drawn under the structure.
    lazy var energyCircle: SCNMaterial = {
        let m = Self.glow(ProceduralTextures.energyCircle())
        m.multiply.contents = UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1)
        m.readsFromDepthBuffer = true
        return m
    }()

    // MARK: Blocks

    private var blockMaterials: [String: SCNMaterial] = [:]

    func blockMaterial(kind: BlockKind, isTarget: Bool, neon: NeonColor? = nil) -> SCNMaterial {
        let key = "\(kind.rawValue)-\(isTarget)-\(neon?.rawValue ?? "")"
        if let cached = blockMaterials[key] { return cached }
        let m: SCNMaterial
        // Structural pieces read as dark machined metal and stone. Energy cores
        // emit; from build 4, trimmed pieces carry a thin neon edge line.
        let trim = neon.map(\.uiColor)
        switch (kind, isTarget) {
        case (.barrier, _):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 1),
                edge: UIColor(red: 0.23, green: 0.24, blue: 0.3, alpha: 1),
                seam: UIColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1), seed: 9),
                metalness: 0.7, roughness: 0.45,
                emission: ProceduralTextures.barrierBand(color: trim ?? NeonColor.red.uiColor),
                emissionIntensity: 2.2)
        case (.reinforced, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.15, green: 0.16, blue: 0.2, alpha: 1),
                edge: UIColor(red: 0.34, green: 0.36, blue: 0.44, alpha: 1),
                seam: UIColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 1), seed: 8),
                metalness: 0.85, roughness: 0.3,
                emission: ProceduralTextures.blockTrim(color: trim ?? Palette.cyan),
                emissionIntensity: 2.0)
        case (_, false):
            // Decorative foundation: muted, no glow, so targets stand out.
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1),
                edge: UIColor(white: 0.2, alpha: 1), seam: UIColor(white: 0.05, alpha: 1), seed: 4),
                metalness: 0.4, roughness: 0.75)
        case (.standard, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.3, green: 0.32, blue: 0.37, alpha: 1),
                edge: UIColor(red: 0.5, green: 0.55, blue: 0.62, alpha: 1),
                seam: UIColor(red: 0.16, green: 0.17, blue: 0.21, alpha: 1), seed: 1),
                metalness: 0.6, roughness: 0.42)
        case (.beam, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.24, green: 0.26, blue: 0.31, alpha: 1),
                edge: UIColor(red: 0.62, green: 0.66, blue: 0.72, alpha: 1),
                seam: UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1), seed: 5),
                metalness: 0.8, roughness: 0.3)
        case (.column, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.36, green: 0.36, blue: 0.4, alpha: 1),
                edge: UIColor(red: 0.58, green: 0.58, blue: 0.64, alpha: 1),
                seam: UIColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1), seed: 6),
                metalness: 0.5, roughness: 0.5)
        case (.heavy, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1),
                edge: UIColor(red: 0.28, green: 0.27, blue: 0.34, alpha: 1),
                seam: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1), seed: 2),
                metalness: 0.8, roughness: 0.35)
        case (.wedge, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.27, green: 0.25, blue: 0.33, alpha: 1),
                edge: UIColor(red: 0.5, green: 0.46, blue: 0.62, alpha: 1),
                seam: UIColor(red: 0.14, green: 0.12, blue: 0.2, alpha: 1), seed: 7),
                metalness: 0.65, roughness: 0.38)
        case (.energy, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.1, green: 0.14, blue: 0.22, alpha: 1),
                edge: UIColor(red: 0.3, green: 0.6, blue: 0.75, alpha: 1),
                seam: UIColor(red: 0.08, green: 0.1, blue: 0.16, alpha: 1), seed: 3),
                metalness: 0.5, roughness: 0.3,
                emission: ProceduralTextures.blockEmission(color: trim ?? Palette.cyan, strong: true), emissionIntensity: 2.2)
        }
        // A neon trim on an ordinary target piece adds a thin glowing edge line.
        if let trim, isTarget, kind != .energy, kind != .reinforced, kind != .barrier {
            m.emission.contents = ProceduralTextures.blockTrim(color: trim)
            m.emission.intensity = 1.8
        }
        blockMaterials[key] = m
        return m
    }

    // MARK: Cannon

    lazy var cannonGraphite: SCNMaterial = Self.pbr(diffuse: Palette.graphite, metalness: 0.9, roughness: 0.32)
    lazy var cannonDark: SCNMaterial = Self.pbr(diffuse: UIColor(red: 0.06, green: 0.065, blue: 0.08, alpha: 1),
                                                metalness: 0.8, roughness: 0.45)
    /// Shared by every energy channel on the cannon; its emission intensity is
    /// driven per frame to show charging and firing.
    lazy var cannonEnergy: SCNMaterial = Self.pbr(diffuse: UIColor.black, metalness: 0, roughness: 1,
                                                  emission: Palette.cyan, emissionIntensity: 1.2)

    // MARK: Orb

    lazy var orbShell: SCNMaterial = {
        let m = Self.pbr(diffuse: UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1), metalness: 0.2, roughness: 0.06,
                         emission: ProceduralTextures.orbEnergyBands(), emissionIntensity: 1.6)
        m.transparency = 0.55
        m.transparencyMode = .dualLayer
        m.fresnelExponent = 1.5
        return m
    }()

    lazy var orbCore: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Palette.energyWhite
        m.emission.contents = Palette.cyan
        m.emission.intensity = 2.5
        return m
    }()

    lazy var orbRing: SCNMaterial = Self.glow(Palette.cyan)
    lazy var orbHalo: SCNMaterial = {
        let m = Self.glow(self.glowImage)
        m.multiply.contents = UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
        return m
    }()

    // MARK: Aiming & effects

    lazy var trajectoryDot: SCNMaterial = Self.glow(Palette.cyan)
    lazy var flash: SCNMaterial = {
        let m = Self.glow(self.glowImage)
        m.multiply.contents = Palette.energyWhite
        return m
    }()
    lazy var shockwave: SCNMaterial = {
        let m = Self.glow(self.shockwaveImage)
        m.multiply.contents = Palette.cyan
        return m
    }()
}

extension NeonColor {
    var uiColor: UIColor { UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1) }
}
