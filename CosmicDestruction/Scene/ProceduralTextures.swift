import UIKit

/// Generates every texture in the game at runtime. No external art assets.
/// Each generator is deterministic (seeded) and cached by `MaterialLibrary`.
enum ProceduralTextures {

    private static func renderer(_ size: CGSize, opaque: Bool = true) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    // MARK: Space background (equirectangular, 2:1)

    static func spaceBackground() -> UIImage {
        let size = CGSize(width: 2048, height: 1024)
        var rng = SeededRandom(seed: 7)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()

            // Vertical gradient: midnight blue at the horizon, near-black above/below.
            let base = CGGradient(colorsSpace: space, colors: [
                UIColor(red: 0.004, green: 0.006, blue: 0.02, alpha: 1).cgColor,
                UIColor(red: 0.02, green: 0.03, blue: 0.09, alpha: 1).cgColor,
                UIColor(red: 0.004, green: 0.006, blue: 0.02, alpha: 1).cgColor,
            ] as CFArray, locations: [0, 0.55, 1])!
            cg.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            // Nebula: soft overlapping radial blobs in purple, cyan and magenta.
            let nebulaColors: [UIColor] = [
                UIColor(red: 0.35, green: 0.1, blue: 0.6, alpha: 1),
                UIColor(red: 0.05, green: 0.35, blue: 0.55, alpha: 1),
                UIColor(red: 0.55, green: 0.08, blue: 0.4, alpha: 1),
            ]
            for i in 0..<34 {
                let color = nebulaColors[i % nebulaColors.count]
                // Concentrate the nebula in a band behind the arena.
                let center = CGPoint(x: rng.cg(200...1850), y: rng.cg(280...620))
                let radius = rng.cg(90...300)
                let alpha = rng.cg(0.05...0.13)
                let gradient = CGGradient(colorsSpace: space, colors: [
                    color.withAlphaComponent(alpha).cgColor,
                    color.withAlphaComponent(0).cgColor,
                ] as CFArray, locations: [0, 1])!
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: radius, options: [])
            }

            // Stars: many faint pinpoints, a few brighter ones with halos.
            for _ in 0..<2600 {
                let p = CGPoint(x: rng.cg(0...size.width), y: rng.cg(0...size.height))
                let b = rng.cg(0.25...0.9)
                let tint = rng.cg(0...1)
                let color = UIColor(red: b * (0.85 + 0.15 * tint), green: b * 0.92, blue: b, alpha: 1)
                cg.setFillColor(color.cgColor)
                let s = rng.cg(0.6...1.6)
                cg.fill(CGRect(x: p.x, y: p.y, width: s, height: s))
            }
            for _ in 0..<70 {
                let p = CGPoint(x: rng.cg(0...size.width), y: rng.cg(0...size.height))
                let halo = CGGradient(colorsSpace: space, colors: [
                    UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.9).cgColor,
                    UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 0).cgColor,
                ] as CFArray, locations: [0, 1])!
                cg.drawRadialGradient(halo, startCenter: p, startRadius: 0, endCenter: p,
                                      endRadius: rng.cg(2.5...6), options: [])
            }
        }
    }

    // MARK: Lunar platform

    /// Dark stone surface with craters and speckle.
    static func lunarSurfaceDiffuse() -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        var rng = SeededRandom(seed: 21)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor(red: 0.09, green: 0.095, blue: 0.12, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            for _ in 0..<5000 {
                let shade = rng.cg(0...1)
                let color = shade > 0.5
                    ? UIColor(white: 0.3, alpha: rng.cg(0.03...0.08))
                    : UIColor(white: 0.0, alpha: rng.cg(0.05...0.12))
                cg.setFillColor(color.cgColor)
                let r = rng.cg(1...9)
                cg.fillEllipse(in: CGRect(x: rng.cg(0...size.width), y: rng.cg(0...size.height), width: r, height: r))
            }
            // Craters
            for _ in 0..<26 {
                let r = rng.cg(12...60)
                let rect = CGRect(x: rng.cg(0...size.width), y: rng.cg(0...size.height), width: r, height: r)
                cg.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
                cg.fillEllipse(in: rect)
                cg.setStrokeColor(UIColor(white: 0.45, alpha: 0.12).cgColor)
                cg.setLineWidth(2)
                cg.strokeEllipse(in: rect.insetBy(dx: -1, dy: -1))
            }
        }
    }

    /// Emission map: glowing cyan/purple cracks plus faint geometric patterns.
    static func lunarSurfaceEmission() -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        var rng = SeededRandom(seed: 33)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            // Faint concentric arena rings and a hex lattice.
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.setStrokeColor(UIColor(red: 0.1, green: 0.55, blue: 0.75, alpha: 0.22).cgColor)
            cg.setLineWidth(2)
            for r in stride(from: CGFloat(120), through: 480, by: 120) {
                cg.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            cg.setStrokeColor(UIColor(red: 0.35, green: 0.15, blue: 0.6, alpha: 0.14).cgColor)
            cg.setLineWidth(1.5)
            let hex: CGFloat = 64
            var row = 0
            for y in stride(from: CGFloat(0), through: size.height, by: hex * 0.866) {
                let offset = row % 2 == 0 ? 0 : hex / 2
                for x in stride(from: offset, through: size.width, by: hex) {
                    let path = CGMutablePath()
                    for k in 0..<6 {
                        let a = CGFloat(k) * .pi / 3 + .pi / 6
                        let p = CGPoint(x: x + cos(a) * hex * 0.5, y: y + sin(a) * hex * 0.5)
                        if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    cg.addPath(path)
                }
                row += 1
            }
            cg.strokePath()

            // Cracks: branching random walks.
            let crackColors = [
                UIColor(red: 0.2, green: 0.9, blue: 1.0, alpha: 1),
                UIColor(red: 0.65, green: 0.3, blue: 1.0, alpha: 1),
            ]
            for i in 0..<16 {
                let color = crackColors[i % 2]
                var p = CGPoint(x: rng.cg(0...size.width), y: rng.cg(0...size.height))
                var angle = rng.cg(0...(2 * .pi))
                let path = CGMutablePath()
                path.move(to: p)
                for _ in 0..<Int(rng.cg(6...16)) {
                    angle += rng.cg(-0.7...0.7)
                    let len = rng.cg(10...34)
                    p = CGPoint(x: p.x + cos(angle) * len, y: p.y + sin(angle) * len)
                    path.addLine(to: p)
                }
                // Glow pass then bright core pass.
                cg.addPath(path)
                cg.setStrokeColor(color.withAlphaComponent(0.25).cgColor)
                cg.setLineWidth(7)
                cg.strokePath()
                cg.addPath(path)
                cg.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
                cg.setLineWidth(2)
                cg.strokePath()
            }
        }
    }

    // MARK: Blocks

    /// Panel texture for block faces: bevelled border with inner seams.
    static func blockPanel(base: UIColor, edge: UIColor, seam: UIColor, seed: UInt64) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        var rng = SeededRandom(seed: seed)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(base.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            // Grain
            for _ in 0..<700 {
                cg.setFillColor(UIColor(white: rng.cg(0...1) > 0.5 ? 1 : 0, alpha: rng.cg(0.02...0.06)).cgColor)
                let r = rng.cg(1...4)
                cg.fill(CGRect(x: rng.cg(0...256), y: rng.cg(0...256), width: r, height: r))
            }
            // Bevel border
            cg.setStrokeColor(edge.cgColor)
            cg.setLineWidth(10)
            cg.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 5, dy: 5))
            // Inner panel seam
            cg.setStrokeColor(seam.cgColor)
            cg.setLineWidth(3)
            cg.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 34, dy: 34))
        }
    }

    /// Emission mask for blocks: glowing edge strips and a central glyph ring.
    static func blockEmission(color: UIColor, strong: Bool) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setStrokeColor(color.withAlphaComponent(strong ? 1 : 0.55).cgColor)
            cg.setLineWidth(strong ? 6 : 3)
            cg.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14))
            if strong {
                cg.setLineWidth(5)
                cg.strokeEllipse(in: CGRect(x: 88, y: 88, width: 80, height: 80))
                cg.setFillColor(color.withAlphaComponent(0.8).cgColor)
                cg.fillEllipse(in: CGRect(x: 116, y: 116, width: 24, height: 24))
            }
        }
    }

    // MARK: Orb

    /// Equirectangular emission map with concentric latitude bands, which read
    /// as concentric energy rings around the orb's poles.
    static func orbEnergyBands() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            let bands: [CGFloat] = [0.12, 0.22, 0.34, 0.5, 0.66, 0.78, 0.88]
            for (i, v) in bands.enumerated() {
                let y = v * size.height
                let alpha: CGFloat = i == 3 ? 1 : 0.55
                cg.setFillColor(UIColor(red: 0.3, green: 0.95, blue: 1, alpha: alpha).cgColor)
                cg.fill(CGRect(x: 0, y: y - 2, width: size.width, height: i == 3 ? 5 : 3))
            }
        }
    }

    // MARK: Effects

    /// Soft radial glow used for particles, halos and flashes.
    static func radialGlow(size: CGFloat = 128) -> UIImage {
        renderer(CGSize(width: size, height: size), opaque: false).image { ctx in
            let space = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: space, colors: [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.35).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ] as CFArray, locations: [0, 0.3, 1])!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                             endCenter: c, endRadius: size / 2, options: [])
        }
    }

    /// Thin glowing ring used for shockwaves.
    static func shockwaveRing() -> UIImage {
        let size: CGFloat = 256
        return renderer(CGSize(width: size, height: size), opaque: false).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            for (inset, width, alpha) in [(18.0, 22.0, 0.18), (20.0, 10.0, 0.45), (22.0, 4.0, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
                cg.setStrokeColor(UIColor(white: 1, alpha: alpha).cgColor)
                cg.setLineWidth(width)
                cg.strokeEllipse(in: rect.insetBy(dx: inset, dy: inset))
            }
        }
    }

    // MARK: Distant planet

    static func planetBands() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        var rng = SeededRandom(seed: 99)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            var y: CGFloat = 0
            while y < size.height {
                let h = rng.cg(6...26)
                let t = rng.cg(0...1)
                let color = UIColor(red: 0.18 + 0.2 * t, green: 0.1 + 0.08 * t, blue: 0.35 + 0.25 * t, alpha: 1)
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: h))
                y += h
            }
        }
    }
}
