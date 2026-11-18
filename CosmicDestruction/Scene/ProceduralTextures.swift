import UIKit
import simd

/// Generates every texture in the game at runtime. No external art assets.
/// Each generator is deterministic (seeded) and cached by `MaterialLibrary`.
enum ProceduralTextures {

    private static func renderer(_ size: CGSize, opaque: Bool = true) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    // Skies are painted per world by SkyPainter (build 5).

    // MARK: Lunar fragment

    /// Shared height field (0...1) for the lunar surface: layered value noise
    /// plus craters with raised rims. Diffuse and normal maps derive from it,
    /// so shading and relief always agree.
    private static let lunarFieldSize = 512
    private static let lunarHeightField: [Float] = {
        let n = lunarFieldSize
        var field = [Float](repeating: 0, count: n * n)
        let noise = ValueNoise(seed: 61)
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n), v = Float(y) / Float(n)
                field[y * n + x] = 0.5 + 0.35 * noise.fbm(u * 9, v * 9, octaves: 5)
            }
        }
        var rng = SeededRandom(seed: 21)
        // Craters: a few large ones, many small ones.
        for i in 0..<70 {
            let r = i < 8 ? rng.float(22...46) : rng.float(4...16)
            let cx = rng.float(0...Float(n)), cy = rng.float(0...Float(n))
            let depth: Float = i < 8 ? 0.4 : 0.25
            let reach = Int(r * 1.5) + 1
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let x = Int(cx) + dx, y = Int(cy) + dy
                    guard x >= 0, y >= 0, x < n, y < n else { continue }
                    let d = sqrt(Float(dx * dx + dy * dy)) / r
                    var h: Float = 0
                    if d < 1 { h = -depth * (1 - d * d) } else if d < 1.5 { h = depth * 0.35 * sin((d - 1) / 0.5 * .pi) }
                    field[y * n + x] += h
                }
            }
        }
        return field
    }()

    private static func image(size n: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> UIImage {
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let (r, g, b) = pixel(x, y)
                let o = (y * n + x) * 4
                bytes[o] = r; bytes[o + 1] = g; bytes[o + 2] = b
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: cgImage)
    }

    private static func byte(_ v: Float) -> UInt8 { UInt8((v.clamped(0, 1) * 255).rounded()) }

    /// A linear-light multiplier expressed as a scale on sRGB values.
    private static func srgbScale(_ tint: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(pow(tint.x, 1 / 2.2), pow(tint.y, 1 / 2.2), pow(tint.z, 1 / 2.2))
    }

    private static func uiColor(_ v: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: 1)
    }

    /// Grey-blue regolith: darker crater floors, lighter sunlit rims, speckle.
    /// `tint` is the world's linear ground multiplier (build 5), applied in sRGB space.
    static func lunarSurfaceDiffuse(tint: SIMD3<Float> = [1, 1, 1]) -> UIImage {
        let n = lunarFieldSize
        let k = srgbScale(tint)
        let field = lunarHeightField
        let speckle = ValueNoise(seed: 77)
        return image(size: n) { x, y in
            let h = field[y * n + x]
            let hx = field[y * n + min(x + 1, n - 1)] - h
            let hy = field[min(y + 1, n - 1) * n + x] - h
            // Fake directional light from the upper left.
            let lit = (-(hx + hy) * 9).clamped(-0.25, 0.25)
            let grain = speckle.value(Float(x) * 0.9, Float(y) * 0.9) - 0.5
            let base = 0.13 + 0.12 * h + lit * 0.35 + grain * 0.05
            return (byte(base * 0.95 * k.x), byte(base * 0.97 * k.y), byte(base * 1.08 * k.z))
        }
    }

    static func lunarSurfaceNormal() -> UIImage {
        let n = lunarFieldSize
        let field = lunarHeightField
        return image(size: n) { x, y in
            let l = field[y * n + max(x - 1, 0)], r = field[y * n + min(x + 1, n - 1)]
            let u = field[max(y - 1, 0) * n + x], d = field[min(y + 1, n - 1) * n + x]
            let normal = simd_normalize(SIMD3<Float>((l - r) * 6, (u - d) * 6, 1))
            return (byte(normal.x * 0.5 + 0.5), byte(normal.y * 0.5 + 0.5), byte(normal.z * 0.5 + 0.5))
        }
    }

    /// Emission: a few thin cyan fractures and purple veins, kept mostly to
    /// the outer region so the play area stays calm. No grid, no rings.
    /// `veins` recolors the fractures per world (build 5); the shapes never change.
    static func lunarSurfaceEmission(veins: [SIMD3<Float>] = WorldTheme.all[0].veins) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        var rng = SeededRandom(seed: 33)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors = veins.map(uiColor)
            for i in 0..<14 {
                let color = colors[i % 2]
                // Start in the outer ring and wander roughly tangentially.
                let a0 = rng.cg(0...(2 * .pi))
                let r0 = rng.cg(300...470)
                var p = CGPoint(x: center.x + cos(a0) * r0, y: center.y + sin(a0) * r0)
                var angle = a0 + .pi / 2 * (rng.cg(0...1) > 0.5 ? 1 : -1)
                let path = CGMutablePath()
                path.move(to: p)
                for _ in 0..<Int(rng.cg(5...12)) {
                    angle += rng.cg(-0.8...0.8)
                    let len = rng.cg(8...26)
                    p = CGPoint(x: p.x + cos(angle) * len, y: p.y + sin(angle) * len)
                    path.addLine(to: p)
                }
                cg.addPath(path)
                cg.setStrokeColor(color.withAlphaComponent(0.18).cgColor)
                cg.setLineWidth(6)
                cg.strokePath()
                cg.addPath(path)
                cg.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
                cg.setLineWidth(1.6)
                cg.strokePath()
            }
        }
    }

    /// Horizontal rock layers for the fragment's sides (tiles horizontally).
    static func strataDiffuse(tint: SIMD3<Float> = [1, 1, 1]) -> UIImage {
        let n = 512
        let k = srgbScale(tint)
        var rng = SeededRandom(seed: 51)
        var bands: [Float] = []
        var shade: Float = 0.12
        while bands.count < n {
            shade = (shade + rng.float(-0.05...0.05)).clamped(0.06, 0.2)
            let h = Int(rng.float(6...40))
            bands += [Float](repeating: shade, count: h)
        }
        let noise = ValueNoise(seed: 53)
        return image(size: n) { x, y in
            // Gentle waviness so layers aren't ruler-straight.
            let wobble = Int(6 * noise.fbm(Float(x) / 64, 0.5, octaves: 2))
            let row = min(max(y + wobble, 0), n - 1)
            let grain = noise.fbm(Float(x) / 9, Float(y) / 3, octaves: 3) * 0.05
            let v = bands[row] + grain
            return (byte(v * 0.95 * k.x), byte(v * 0.95 * k.y), byte(v * 1.12 * k.z))
        }
    }

    /// Sparse purple veins along a couple of layers, with rare cyan glints.
    static func strataEmission(veins: [SIMD3<Float>] = WorldTheme.all[0].veins) -> UIImage {
        let size = CGSize(width: 512, height: 512)
        var rng = SeededRandom(seed: 57)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setLineCap(.round)
            for i in 0..<5 {
                let color = uiColor(i == 0 ? veins[0] : veins[1])
                var p = CGPoint(x: rng.cg(0...512), y: rng.cg(60...460))
                let path = CGMutablePath()
                path.move(to: p)
                for _ in 0..<Int(rng.cg(4...9)) {
                    p = CGPoint(x: p.x + rng.cg(12...34), y: p.y + rng.cg(-6...6))
                    path.addLine(to: p)
                }
                cg.addPath(path)
                cg.setStrokeColor(color.withAlphaComponent(0.2).cgColor)
                cg.setLineWidth(6)
                cg.strokePath()
                cg.addPath(path)
                cg.setStrokeColor(color.withAlphaComponent(0.8).cgColor)
                cg.setLineWidth(1.5)
                cg.strokePath()
            }
        }
    }

    /// White ring pattern (tinted by its material) for the energy circle.
    static func energyCircle() -> UIImage {
        let size: CGFloat = 512
        return renderer(CGSize(width: size, height: size), opaque: true).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let c = CGPoint(x: size / 2, y: size / 2)
            let space = CGColorSpaceCreateDeviceRGB()
            let fill = CGGradient(colorsSpace: space, colors: [
                UIColor(white: 0.08, alpha: 1).cgColor, UIColor(white: 0.03, alpha: 1).cgColor, UIColor.black.cgColor,
            ] as CFArray, locations: [0, 0.8, 1])!
            cg.drawRadialGradient(fill, startCenter: c, startRadius: 0, endCenter: c, endRadius: size / 2, options: [])
            func ring(_ r: CGFloat, _ width: CGFloat, _ white: CGFloat, dash: [CGFloat] = []) {
                cg.setStrokeColor(UIColor(white: white, alpha: 1).cgColor)
                cg.setLineWidth(width)
                cg.setLineDash(phase: 0, lengths: dash)
                cg.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            ring(246, 3, 0.55)
            ring(236, 1.5, 0.25)
            ring(200, 2, 0.35, dash: [18, 10])
            ring(120, 1.5, 0.2, dash: [4, 8])
            cg.setLineDash(phase: 0, lengths: [])
            // Tick marks between the outer rings.
            cg.setStrokeColor(UIColor(white: 0.4, alpha: 1).cgColor)
            cg.setLineWidth(2)
            for k in 0..<48 {
                let a = CGFloat(k) / 48 * 2 * .pi
                let r0: CGFloat = k % 4 == 0 ? 208 : 220
                cg.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                cg.addLine(to: CGPoint(x: c.x + cos(a) * 232, y: c.y + sin(a) * 232))
            }
            cg.strokePath()
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

    /// Neon trim (build 4): a bright edge frame plus a faint inner line, for
    /// trimmed structural pieces and reinforced blocks.
    static func blockTrim(color: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(12)
            cg.stroke(CGRect(x: 8, y: 8, width: 240, height: 240))
            cg.setStrokeColor(color.withAlphaComponent(0.5).cgColor)
            cg.setLineWidth(3)
            cg.stroke(CGRect(x: 40, y: 40, width: 176, height: 176))
        }
    }

    /// Shield-wall stripe (build 4): a bright horizontal band near the top
    /// edge and faint lines along the top and bottom.
    static func barrierBand(color: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return renderer(size).image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setFillColor(color.cgColor)
            cg.fill(CGRect(x: 0, y: 40, width: 256, height: 34))
            cg.setFillColor(color.withAlphaComponent(0.6).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 256, height: 6))
            cg.fill(CGRect(x: 0, y: 250, width: 256, height: 6))
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
}

/// Deterministic 2D value noise with fractal sums, used by the texture generators.
struct ValueNoise {
    private var table: [Float]

    init(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        table = (0..<256 * 256).map { _ in rng.float(0...1) }
    }

    private func lattice(_ x: Int, _ y: Int) -> Float {
        table[(y & 255) * 256 + (x & 255)]
    }

    func value(_ x: Float, _ y: Float) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        var fx = x - floor(x), fy = y - floor(y)
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        let a = lattice(xi, yi), b = lattice(xi + 1, yi)
        let c = lattice(xi, yi + 1), d = lattice(xi + 1, yi + 1)
        return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
    }

    /// Fractal sum centered on 0 (roughly -0.5...0.5).
    func fbm(_ x: Float, _ y: Float, octaves: Int) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, frequency: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += (value(x * frequency, y * frequency) - 0.5) * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return sum / norm
    }
}
