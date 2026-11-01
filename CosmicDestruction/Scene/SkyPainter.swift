import UIKit
import simd

/// Paints each world's equirectangular sky (build 5): gradient, nebula, stars,
/// horizon haze, and the world's planet or sun placed where the gameplay
/// camera sees it. Mirrors `spaceTexture(w)` in web-preview/index.html.
enum SkyPainter {
    static let width: CGFloat = 4096
    static let height: CGFloat = 2048
    /// Horizontal image position the default camera (looking down -z) faces.
    /// The web build (three.js) uses 0.25. SceneKit also uses 0.25 with u
    /// growing to the right; checked against CI screenshots.
    static let viewCenterU: CGFloat = 0.25

    private typealias Painter = (CGContext, CGPoint, CGFloat) -> Void

    private static func color(_ v: SIMD3<Float>, _ a: CGFloat = 1) -> CGColor {
        UIColor(red: CGFloat(v.x), green: CGFloat(v.y), blue: CGFloat(v.z), alpha: a).cgColor
    }
    private static func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a).cgColor
    }
    private static let space = CGColorSpaceCreateDeviceRGB()
    private static func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    }
    private static func radial(_ cg: CGContext, _ c: CGPoint, _ r0: CGFloat, _ r1: CGFloat, _ colors: [CGColor], _ locs: [CGFloat]) {
        cg.drawRadialGradient(gradient(colors, locs), startCenter: c, startRadius: r0, endCenter: c, endRadius: r1, options: [])
    }

    /// Degrees right of / above the view center to image pixels.
    private static func point(_ az: CGFloat, _ el: CGFloat) -> CGPoint {
        let d = width / 360
        return CGPoint(x: width * viewCenterU + az * d, y: height * 0.5 - el * d)
    }
    private static var deg: CGFloat { width / 360 }

    static func image(for world: WorldTheme) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            paint(ctx.cgContext, world)
        }
    }

    private static func paint(_ cg: CGContext, _ w: WorldTheme) {
        var rng = SeededRandom(seed: 7)
        let s = w.sky, W = width, H = height
        cg.drawLinearGradient(gradient(s.gradient.map { color($0) }, [0, 0.5, 1]),
                              start: .zero, end: CGPoint(x: 0, y: H), options: [])
        if !s.nebula.isEmpty {
            for i in 0..<48 {
                let c = CGPoint(x: rng.cg(400...3700), y: rng.cg(560...1240))
                let r = rng.cg(180...600)
                let a = CGFloat(Float.random(in: s.nebulaAlpha, using: &rng))
                let n = s.nebula[i % s.nebula.count]
                radial(cg, c, 0, r, [color(n, a), color(n, 0)], [0, 1])
            }
        }
        for _ in 0..<Int(5200 * s.stars) {
            let b = rng.cg(0.27...0.9), sz = rng.cg(1...2.6)
            cg.setFillColor(UIColor(red: b, green: b * 0.95, blue: b, alpha: 1).cgColor)
            cg.fill(CGRect(x: rng.cg(0...W), y: rng.cg(0...H), width: sz, height: sz))
        }
        for _ in 0..<Int(140 * s.stars) {
            let p = CGPoint(x: rng.cg(0...W), y: rng.cg(0...H))
            radial(cg, p, 0, rng.cg(5...12), [color(0xD9F2FF, 0.9), color(0x80CCFF, 0)], [0, 1])
        }
        if let haze = s.haze {
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: H * 0.36, width: W, height: H * 0.26))
            cg.drawLinearGradient(gradient([color(haze, 0), color(haze, 0.35), color(haze, 0)], [0, 0.55, 1]),
                                  start: CGPoint(x: 0, y: H * 0.36), end: CGPoint(x: 0, y: H * 0.62), options: [])
            cg.restoreGState()
        }
        paintFeature(cg, w.key)
    }

    // MARK: Planets

    private static func disc(_ cg: CGContext, _ c: CGPoint, _ r: CGFloat, _ base: UInt32,
                             atmo: UInt32? = nil, light: CGPoint = CGPoint(x: 0.55, y: -0.45), paint: Painter? = nil) {
        if let atmo {
            radial(cg, c, r * 0.9, r * 1.35, [color(atmo, 0.55), color(atmo, 0)], [0, 1])
        }
        cg.saveGState()
        cg.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        cg.clip()
        cg.setFillColor(color(base))
        cg.fill(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        paint?(cg, c, r)
        let p0 = CGPoint(x: c.x + light.x * r * 0.7, y: c.y + light.y * r * 0.7)
        let p1 = CGPoint(x: c.x + light.x * r * 0.35, y: c.y + light.y * r * 0.35)
        cg.drawRadialGradient(gradient([UIColor(white: 1, alpha: 0.12).cgColor, UIColor(white: 0, alpha: 0).cgColor,
                                        UIColor(white: 0, alpha: 0.55).cgColor, UIColor(white: 0, alpha: 0.93).cgColor],
                                       [0, 0.45, 0.8, 1]),
                              startCenter: p0, startRadius: r * 0.05, endCenter: p1, endRadius: r * 1.55,
                              options: [.drawsAfterEndLocation])
        cg.restoreGState()
    }

    private static func bands(_ cols: [UInt32], wobble: CGFloat = 0.03, seed: UInt64) -> Painter {
        { cg, c, r in
            var rr = SeededRandom(seed: seed)
            var y = c.y - r
            while y < c.y + r {
                let h = r * rr.cg(0.06...0.16)
                let col = cols[Int(rr.cg(0...0.999) * CGFloat(cols.count))]
                let path = CGMutablePath()
                path.move(to: CGPoint(x: c.x - r, y: y))
                for k in 0...24 {
                    let fk = CGFloat(k)
                    path.addLine(to: CGPoint(x: c.x - r + fk / 24 * 2 * r, y: y + sin(fk * 0.9 + y) * r * wobble))
                }
                path.addLine(to: CGPoint(x: c.x + r, y: y + h + r * wobble))
                path.addLine(to: CGPoint(x: c.x - r, y: y + h + r * wobble))
                path.closeSubpath()
                cg.addPath(path)
                cg.setFillColor(color(col))
                cg.fillPath()
                y += h
            }
        }
    }

    private static func ellipse(_ cg: CGContext, _ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ rot: CGFloat) {
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rot)
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: t)
        cg.addPath(path)
    }

    private static func blobs(_ cols: [UInt32], _ n: Int, _ rmin: CGFloat, _ rmax: CGFloat, seed: UInt64,
                              alpha: CGFloat = 1, squash: CGFloat = 1) -> Painter {
        { cg, c, r in
            var rr = SeededRandom(seed: seed)
            cg.saveGState()
            cg.setAlpha(alpha)
            for i in 0..<n {
                let p = CGPoint(x: c.x + rr.cg(-r...r), y: c.y + rr.cg(-r...r))
                let rx = r * rr.cg(rmin...rmax), ry = r * rr.cg(rmin...rmax) * squash
                ellipse(cg, p, rx, ry, rr.cg(0...3))
                cg.setFillColor(color(cols[i % cols.count]))
                cg.fillPath()
            }
            cg.restoreGState()
        }
    }

    private static func both(_ painters: Painter...) -> Painter {
        { cg, c, r in painters.forEach { $0(cg, c, r) } }
    }

    /// Rings as stacked partial ellipses: back half before the planet, front half after.
    private static func rings(_ cg: CGContext, _ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, tilt: CGFloat, front: Bool,
                              _ layers: [(CGFloat, CGFloat, UInt32, CGFloat)]) {
        for (k, lw, col, a) in layers {
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: tilt).scaledBy(x: rx * k, y: ry * k)
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: 1, startAngle: front ? 0 : .pi, endAngle: front ? .pi : 2 * .pi,
                        clockwise: false, transform: t)
            cg.addPath(path)
            cg.setStrokeColor(color(col, a))
            cg.setLineWidth(lw)
            cg.strokePath()
        }
    }

    private static func paintFeature(_ cg: CGContext, _ key: WorldTheme.Key) {
        let W = width, H = height
        switch key {
        case .moon:
            // Earth low over the dust; the violet ringed world stays far off to the side.
            disc(cg, point(10, 0.5), 4 * deg, 0x1F5FAE, atmo: 0x78B4FF,
                 paint: both(blobs([0x3F7A3A, 0x8A7A4A, 0x2F6A34], 9, 0.18, 0.4, seed: 11),
                             blobs([0xFFFFFF], 14, 0.08, 0.35, seed: 12, alpha: 0.7, squash: 0.35)))
            let p = point(-12, 2), pr = 1.8 * deg
            disc(cg, p, pr, 0x3A2766)
            rings(cg, p, pr * 1.9, pr * 0.4, tilt: -0.35, front: true, [(1, 10, 0x9E4DFF, 0.55)])
        case .mars:
            disc(cg, point(-10, 1), 1.6 * deg, 0x6B5D52, paint: blobs([0x4A3F37, 0x82705F], 6, 0.15, 0.35, seed: 21))
            disc(cg, point(10, 3), 0.8 * deg, 0x7A6A5C)
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: H * 0.42, width: W, height: H * 0.14))
            cg.drawLinearGradient(gradient([color(0xFF8C50, 0), color(0xFF8C50, 0.28)], [0, 1]),
                                  start: CGPoint(x: 0, y: H * 0.42), end: CGPoint(x: 0, y: H * 0.56), options: [])
            cg.restoreGState()
        case .mercury:
            let c = point(-9, 0), sr = 5 * deg
            radial(cg, c, sr * 0.8, sr * 5, [color(0xFFC86E, 0.75), color(0xFF963C, 0.25), color(0xFF7828, 0)], [0, 0.3, 1])
            var rr = SeededRandom(seed: 31)
            cg.setStrokeColor(color(0xFFDC96, 0.35))
            cg.setLineCap(.round)
            for _ in 0..<40 {
                let a = rr.cg(0...6.28), l = sr * rr.cg(1.2...2.4)
                cg.setLineWidth(rr.cg(2...7))
                cg.move(to: CGPoint(x: c.x + cos(a) * sr, y: c.y + sin(a) * sr))
                cg.addLine(to: CGPoint(x: c.x + cos(a) * l, y: c.y + sin(a) * l))
                cg.strokePath()
            }
            cg.saveGState()
            cg.addEllipse(in: CGRect(x: c.x - sr, y: c.y - sr, width: sr * 2, height: sr * 2))
            cg.clip()
            radial(cg, c, 0, sr, [color(0xFFFEF2), color(0xFFE9A8), color(0xFFB84A)], [0, 0.7, 1])
            cg.restoreGState()
        case .venus:
            let c = point(5, 2)
            radial(cg, c, 0, 30 * deg, [color(0xFFF0BE, 0.75), color(0xFFC878, 0)], [0, 1])
            var rr = SeededRandom(seed: 41)
            let cols: [UInt32] = [0xFFD282, 0xC87832, 0xFFBE5A, 0x784619]
            for i in 0..<520 {
                let cy = rr.cg(H * 0.18...H * 0.62), a = rr.cg(0.04...0.14)
                ellipse(cg, CGPoint(x: rr.cg(0...W), y: cy), rr.cg(60...360), rr.cg(8...34), rr.cg(-0.08...0.08))
                cg.setFillColor(color(cols[i % 4], a))
                cg.fillPath()
            }
        case .jupiter:
            disc(cg, point(5, -1), 12 * deg, 0xE2CFB0, atmo: 0xFFDCB4,
                 paint: both(bands([0xEFE2CC, 0xC9A27A, 0xE6CFAE, 0xA9744F, 0xF3E8D6, 0x8A5A3C, 0xD9B58C], wobble: 0.025, seed: 5),
                             { cg, c, r in
                                 ellipse(cg, CGPoint(x: c.x + r * 0.25, y: c.y + r * 0.32), r * 0.2, r * 0.11, 0)
                                 cg.setFillColor(color(0xB8492F))
                                 cg.fillPath()
                                 ellipse(cg, CGPoint(x: c.x + r * 0.25, y: c.y + r * 0.32), r * 0.2, r * 0.11, 0)
                                 cg.setStrokeColor(color(0xFFE6C8, 0.6))
                                 cg.setLineWidth(r * 0.025)
                                 cg.strokePath()
                             }))
            disc(cg, point(-12, 1.5), 1.3 * deg, 0xE6D24A, paint: blobs([0xC47A2A, 0xF0E080], 8, 0.1, 0.25, seed: 51))
            disc(cg, point(-7, 3.5), 1 * deg, 0xE8E4DC, paint: blobs([0xB08A6A], 6, 0.05, 0.4, seed: 52, alpha: 0.6, squash: 0.15))
        case .saturn:
            let c = point(-6, 1), sr = 5.5 * deg
            let layers: [(CGFloat, CGFloat, UInt32, CGFloat)] = [
                (2.25, 7, 0xC8B48C, 0.35), (2.05, 22, 0xE6CD96, 0.55), (1.8, 18, 0xFAE6B4, 0.7),
                (1.55, 10, 0xC8AA78, 0.45), (1.4, 6, 0x968264, 0.3),
            ]
            rings(cg, c, sr, sr * 0.22, tilt: -0.18, front: false, layers)
            disc(cg, c, sr, 0xE4CC94, paint: bands([0xEEDBAA, 0xD9B878, 0xE9D29C, 0xC8A468, 0xF2E2B8], wobble: 0.012, seed: 7))
            rings(cg, c, sr, sr * 0.22, tilt: -0.18, front: true, layers)
            var rr = SeededRandom(seed: 61)
            for _ in 0..<900 {
                cg.setFillColor(color(0xE6D2AA, rr.cg(0.15...0.6)))
                let sz = rr.cg(1...3)
                cg.fill(CGRect(x: rr.cg(0...W), y: H * 0.5 + rr.cg(-1...1) * rr.cg(0...1) * 90 - 30, width: sz, height: sz))
            }
        case .uranus:
            let c = point(8, 1), ur = 5 * deg
            let layers: [(CGFloat, CGFloat, UInt32, CGFloat)] = [(1.9, 4, 0xC8F0FF, 0.45), (1.7, 2.5, 0xAADCF0, 0.35)]
            rings(cg, c, ur * 0.35, ur, tilt: 0.25, front: false, layers)
            disc(cg, c, ur, 0x9FE3E8, atmo: 0xA0F0F5, light: CGPoint(x: 0.2, y: -0.7),
                 paint: bands([0xA6E6EA, 0x97DBE2, 0xAEEAEE], wobble: 0.01, seed: 9))
            rings(cg, c, ur * 0.35, ur, tilt: 0.25, front: true, layers)
        case .neptune:
            disc(cg, point(-8, 1), 5 * deg, 0x2A52C9, atmo: 0x5A82FF,
                 paint: both(bands([0x2A52C9, 0x2448B4, 0x3360D8, 0x1F3FA0], wobble: 0.015, seed: 13),
                             { cg, c, r in
                                 ellipse(cg, CGPoint(x: c.x - r * 0.2, y: c.y + r * 0.15), r * 0.18, r * 0.09, 0)
                                 cg.setFillColor(color(0x14286E))
                                 cg.fillPath()
                             },
                             blobs([0xE8F0FF], 7, 0.04, 0.2, seed: 14, alpha: 0.6, squash: 0.12)))
            disc(cg, point(10, 2.5), 0.9 * deg, 0xD8C8C0)
        }
    }
}
