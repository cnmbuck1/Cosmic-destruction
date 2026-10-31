import SwiftUI

enum Theme {
    static let cyan = Color(red: 0.2, green: 0.92, blue: 1.0)
    static let purple = Color(red: 0.62, green: 0.3, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.25, blue: 0.75)
    static let midnight = Color(red: 0.02, green: 0.03, blue: 0.09)
    static let panel = Color(red: 0.04, green: 0.06, blue: 0.14).opacity(0.86)
    static let textDim = Color.white.opacity(0.6)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .default).width(.expanded) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .default).width(.expanded) }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension View {
    /// Neon glow for text and icons.
    func neonGlow(_ color: Color = Theme.cyan, radius: CGFloat = 8) -> some View {
        shadow(color: color.opacity(0.8), radius: radius / 2)
            .shadow(color: color.opacity(0.5), radius: radius)
    }
}

/// Primary neon button style used across menus and overlays.
struct NeonButtonStyle: ButtonStyle {
    var color: Color = Theme.cyan
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(17))
            .tracking(3)
            .foregroundStyle(filled ? Color.black : color)
            .frame(maxWidth: 260)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(filled ? color : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(color, lineWidth: 1.5)
                    )
            }
            .shadow(color: color.opacity(configuration.isPressed ? 0.9 : 0.5), radius: configuration.isPressed ? 18 : 10)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Small circular icon button for the HUD.
struct HUDIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.panel))
                .overlay(Circle().stroke(Theme.cyan.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Row of star icons with optional staggered reveal.
struct StarRow: View {
    let stars: Int
    var size: CGFloat = 18
    var revealed: Int? = nil

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(0..<3, id: \.self) { i in
                let earned = i < stars
                let visible = revealed.map { i < $0 } ?? true
                Image(systemName: earned ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(earned ? Theme.cyan : Color.white.opacity(0.25))
                    .neonGlow(earned ? Theme.cyan : .clear, radius: earned ? size * 0.6 : 0)
                    .scaleEffect(visible ? 1 : 0.2)
                    .opacity(visible ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.5), value: visible)
            }
        }
    }
}

/// Animated starfield + nebula background for menus (pure SwiftUI).
struct SpaceBackdrop: View {
    private struct Star { let x, y, size, phase: CGFloat }

    private let stars: [Star] = {
        var rng = SeededRandom(seed: 3)
        return (0..<160).map { _ in
            Star(x: rng.cg(0...1), y: rng.cg(0...1), size: rng.cg(0.6...2.2), phase: rng.cg(0...6.28))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color.black, Theme.midnight, Color.black]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                // Nebula glows
                for (i, color) in [Theme.purple, Theme.cyan, Theme.magenta].enumerated() {
                    let cx = size.width * (0.25 + 0.3 * CGFloat(i)) + CGFloat(20 * sin(t * 0.1 + Double(i)))
                    let cy = size.height * (0.3 + 0.15 * CGFloat(i))
                    let r = size.width * 0.6
                    context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                                 with: .radialGradient(Gradient(colors: [color.opacity(0.16), .clear]),
                                                       center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
                }
                for star in stars {
                    let twinkle = 0.55 + 0.45 * sin(t * 1.3 + Double(star.phase))
                    let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(twinkle)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The signature orb rendered in 2D for menus.
struct MenuOrb: View {
    var size: CGFloat = 150

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Theme.cyan.opacity(0.45), .clear], center: .center,
                                         startRadius: size * 0.3, endRadius: size * 0.9))
                    .frame(width: size * 1.8, height: size * 1.8)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.6), Color(red: 0.02, green: 0.05, blue: 0.12)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: size * 0.6))
                    .frame(width: size, height: size)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Theme.cyan.opacity(0.6 - Double(i) * 0.15), lineWidth: 1.5)
                        .frame(width: size * (0.45 + 0.17 * CGFloat(i)), height: size * (0.45 + 0.17 * CGFloat(i)))
                }
                Ellipse()
                    .stroke(Theme.cyan, lineWidth: 2)
                    .frame(width: size * 0.8, height: size * 0.26)
                    .rotationEffect(.radians(t * 0.8))
                    .neonGlow()
                Ellipse()
                    .stroke(Theme.purple, lineWidth: 1.5)
                    .frame(width: size * 0.7, height: size * 0.2)
                    .rotationEffect(.radians(-t * 1.1 + 1))
                Circle()
                    .fill(RadialGradient(colors: [.white, Theme.cyan, Theme.cyan.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: size * 0.22))
                    .frame(width: size * 0.44, height: size * 0.44)
                    .scaleEffect(1 + 0.06 * sin(t * 2.5))
                Circle()
                    .stroke(LinearGradient(colors: [.white.opacity(0.7), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2)
                    .frame(width: size, height: size)
            }
        }
    }
}
