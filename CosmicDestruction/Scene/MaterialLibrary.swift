import SceneKit
import UIKit

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

    lazy var spaceBackground: UIImage = ProceduralTextures.spaceBackground()
    lazy var glowImage: UIImage = ProceduralTextures.radialGlow()
    lazy var shockwaveImage: UIImage = ProceduralTextures.shockwaveRing()

    // MARK: Platform

    lazy var platformTop: SCNMaterial = {
        let m = Self.pbr(diffuse: ProceduralTextures.lunarSurfaceDiffuse(), metalness: 0.15, roughness: 0.85,
                         emission: ProceduralTextures.lunarSurfaceEmission(), emissionIntensity: 1.4)
        return m
    }()

    lazy var platformRock: SCNMaterial = Self.pbr(
        diffuse: UIColor(red: 0.07, green: 0.07, blue: 0.1, alpha: 1), metalness: 0.1, roughness: 0.95)

    lazy var rimCyan: SCNMaterial = {
        let m = Self.pbr(diffuse: UIColor.black, metalness: 0, roughness: 1, emission: Palette.cyan, emissionIntensity: 2.2)
        return m
    }()

    lazy var rimPurple: SCNMaterial = Self.pbr(diffuse: UIColor.black, metalness: 0, roughness: 1,
                                               emission: Palette.purple, emissionIntensity: 1.6)

    lazy var crystal: SCNMaterial = Self.pbr(diffuse: UIColor(red: 0.2, green: 0.1, blue: 0.35, alpha: 1),
                                             metalness: 0.3, roughness: 0.2, emission: Palette.purple, emissionIntensity: 1.2)

    // MARK: Blocks

    private var blockMaterials: [String: SCNMaterial] = [:]

    func blockMaterial(kind: BlockKind, isTarget: Bool) -> SCNMaterial {
        let key = "\(kind.rawValue)-\(isTarget)"
        if let cached = blockMaterials[key] { return cached }
        let m: SCNMaterial
        switch (kind, isTarget) {
        case (_, false):
            // Decorative foundation: muted, no glow, so targets stand out.
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.1, green: 0.1, blue: 0.13, alpha: 1),
                edge: UIColor(white: 0.2, alpha: 1), seam: UIColor(white: 0.05, alpha: 1), seed: 4),
                metalness: 0.4, roughness: 0.75)
        case (.standard, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.3, green: 0.33, blue: 0.4, alpha: 1),
                edge: UIColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1),
                seam: UIColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1), seed: 1),
                metalness: 0.55, roughness: 0.45,
                emission: ProceduralTextures.blockEmission(color: Palette.cyan, strong: false), emissionIntensity: 0.6)
        case (.heavy, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1),
                edge: UIColor(red: 0.3, green: 0.28, blue: 0.38, alpha: 1),
                seam: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1), seed: 2),
                metalness: 0.75, roughness: 0.35,
                emission: ProceduralTextures.blockEmission(color: Palette.purple, strong: false), emissionIntensity: 0.8)
        case (.energy, true):
            m = Self.pbr(diffuse: ProceduralTextures.blockPanel(
                base: UIColor(red: 0.1, green: 0.14, blue: 0.22, alpha: 1),
                edge: UIColor(red: 0.3, green: 0.6, blue: 0.75, alpha: 1),
                seam: UIColor(red: 0.08, green: 0.1, blue: 0.16, alpha: 1), seed: 3),
                metalness: 0.5, roughness: 0.3,
                emission: ProceduralTextures.blockEmission(color: Palette.cyan, strong: true), emissionIntensity: 2.0)
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
