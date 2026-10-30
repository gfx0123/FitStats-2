import SwiftUI

/// The screen background: a calm nature scene whose sky follows the time of day, or a plain grey
/// (Settings → Appearance). It moves slowly; it stands still with Reduce Motion and in UI tests.
struct AppBackground: View {
    @AppStorage(AppBackground.natureKey) private var nature = true

    static let natureKey = "appearance.nature"

    var body: some View {
        Group {
            if nature {
                NatureScene()
            } else {
                LinearGradient(colors: [Color(red: 0.235, green: 0.243, blue: 0.259), Color(red: 0.118, green: 0.122, blue: 0.133)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum SkyTime: String {
    case dawn, day, dusk, night

    static func at(_ date: Date) -> SkyTime {
        if let forced = ProcessInfo.processInfo.environment["FITSTATS_SKY"].flatMap(SkyTime.init(rawValue:)) { return forced }
        switch Calendar.current.component(.hour, from: date) {
        case 5..<9: return .dawn
        case 9..<17: return .day
        case 17..<20: return .dusk
        default: return .night
        }
    }
}

private struct ScenePalette {
    let sky: [Color]
    /// Sun (or moon) centre and radius in the 402 × 874 design space.
    let sun: CGPoint
    let sunRadius: CGFloat
    let sunCore: Color
    let halo: Color
    let hills: [(Color, Color)]
    let mist: Color
    let mote: Color

    static func rgb(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func of(_ time: SkyTime) -> ScenePalette {
        switch time {
        case .dawn:
            return ScenePalette(sky: [0x0E2531, 0x24495A, 0x6F8F93, 0xD9B78E, 0xF0C98F].map(rgb), sun: CGPoint(x: 304, y: 452), sunRadius: 24,
                                sunCore: rgb(0xFFF0D2), halo: rgb(0xFFD696),
                                hills: [(0x7F9C9C, 0x6C8B8D), (0x55767A, 0x45666A), (0x35565A, 0x2A4749), (0x1F3A3B, 0x172D2E), (0x112324, 0x0B1819)].map { (rgb($0.0), rgb($0.1)) },
                                mist: rgb(0xE1EBE8), mote: rgb(0xFFECBE))
        case .day:
            // Kept deep enough for white text on the sky.
            return ScenePalette(sky: [0x123A4E, 0x1F5870, 0x417D91, 0x8DB6B4, 0xBBD5CA].map(rgb), sun: CGPoint(x: 352, y: 318), sunRadius: 18,
                                sunCore: rgb(0xFFFCF0), halo: rgb(0xFFF8DC),
                                hills: [(0x86AFA3, 0x77A193), (0x5F9182, 0x4F8172), (0x3E6E5D, 0x33604F), (0x264C3E, 0x1D3F33), (0x143026, 0x0E241C)].map { (rgb($0.0), rgb($0.1)) },
                                mist: rgb(0xEBF4F0), mote: rgb(0xFFFAE1))
        case .dusk:
            return ScenePalette(sky: [0x17142E, 0x33284F, 0x6E4766, 0xC9786C, 0xEBA277].map(rgb), sun: CGPoint(x: 92, y: 470), sunRadius: 26,
                                sunCore: rgb(0xFFD6AA), halo: rgb(0xFF966E),
                                hills: [(0x77607A, 0x655069), (0x4F405C, 0x41354F), (0x33304A, 0x2A273F), (0x1F1F33, 0x181829), (0x11121F, 0x0B0C16)].map { (rgb($0.0), rgb($0.1)) },
                                mist: rgb(0xEBD7DC), mote: rgb(0xFFD2AA))
        case .night:
            return ScenePalette(sky: [0x040912, 0x08162A, 0x0F2538, 0x183446, 0x1D3B4A].map(rgb), sun: CGPoint(x: 352, y: 74), sunRadius: 15,
                                sunCore: rgb(0xEBF2FF), halo: rgb(0xA0BEE6),
                                hills: [(0x1D3640, 0x182F38), (0x152A33, 0x11242C), (0x0F2026, 0x0C1B21), (0x0A171B, 0x081316), (0x060F12, 0x040B0D)].map { (rgb($0.0), rgb($0.1)) },
                                mist: rgb(0xA0BEC8), mote: rgb(0xC8FFAA))
        }
    }
}

/// Everything in the scene that doesn't move by itself, made once (positions are fixed so the
/// scene looks the same every time).
private struct SceneLayout {
    struct Layer { let y, amp: CGFloat; let f: (CGFloat, CGFloat); let ph: (CGFloat, CGFloat); let speed: CGFloat; let trees: [(x: CGFloat, h: CGFloat)] }
    struct Drift { let x, y, w, h, speed, alpha: CGFloat }
    struct Mote { let x, y, phase, r: CGFloat }
    struct Star { let x, y, r, phase: CGFloat }

    let layers: [Layer]
    let mists: [Drift]
    let clouds: [Drift]
    let motes: [Mote]
    let stars: [Star]

    static let shared = SceneLayout()

    private init() {
        var seed: UInt64 = 11
        func rnd() -> CGFloat {
            seed = (seed * 16807) % 2_147_483_647
            return CGFloat(seed) / 2_147_483_647
        }
        let spec: [(CGFloat, CGFloat, (CGFloat, CGFloat), (CGFloat, CGFloat), CGFloat, Int)] = [
            (468, 26, (0.011, 0.023), (0, 2), 0.6, 0),
            (512, 30, (0.009, 0.019), (1, 4), 1.1, 0),
            (566, 26, (0.013, 0.027), (3, 1), 1.8, 26),
            (640, 30, (0.010, 0.021), (5, 2), 2.8, 20),
            (735, 22, (0.012, 0.025), (2, 6), 4.0, 14),
        ]
        layers = spec.map { s in
            Layer(y: s.0, amp: s.1, f: s.2, ph: s.3, speed: s.4, trees: (0..<s.5).map { _ in (x: rnd() * 522, h: 0.7 + rnd() * 0.6) })
        }
        mists = [488, 530, 548, 600, 620, 690, 700].map { y in
            Drift(x: rnd() * 402, y: y, w: 180 + rnd() * 160, h: 16 + rnd() * 14, speed: 3 + rnd() * 4, alpha: 0.10 + rnd() * 0.08)
        }
        clouds = (0..<4).map { i in
            Drift(x: rnd() * 402, y: 90 + CGFloat(i) * 70 + rnd() * 30, w: 140 + rnd() * 120, h: 0, speed: 1.5 + rnd() * 2, alpha: 0)
        }
        // A few specks of light only: the scene stays calm.
        motes = (0..<5).map { _ in Mote(x: rnd() * 402, y: 440 + rnd() * 330, phase: rnd() * 6.28, r: 1 + rnd() * 1.2) }
        stars = (0..<90).map { _ in Star(x: rnd() * 402, y: rnd() * 440, r: 0.4 + rnd() * 1.1, phase: rnd() * 6.28) }
    }
}

struct NatureScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let still = !(ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? "").isEmpty

    var body: some View {
        // Slow drift needs few frames: 15 a second is smooth and light on the battery.
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || Self.still)) { timeline in
            let t = (reduceMotion || Self.still) ? 4 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400)
            let palette = ScenePalette.of(SkyTime.at(timeline.date))
            Canvas(rendersAsynchronously: true) { gc, size in
                NatureScene.draw(&gc, size: size, t: CGFloat(t), palette: palette, night: SkyTime.at(timeline.date) == .night)
            }
        }
    }

    private static func soft(_ gc: inout GraphicsContext, center: CGPoint, width: CGFloat, squash: CGFloat, color: Color, alpha: CGFloat) {
        var c = gc
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: 1, y: squash)
        let r = width / 2
        c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: width, height: width)),
               with: .radialGradient(Gradient(colors: [color.opacity(alpha), color.opacity(0)]), center: .zero, startRadius: 0, endRadius: r))
    }

    fileprivate static func draw(_ gc: inout GraphicsContext, size: CGSize, t: CGFloat, palette p: ScenePalette, night: Bool) {
        let layout = SceneLayout.shared
        // Laid out on a 402-point-wide design, scaled to the screen and kept at the bottom.
        let s = size.width / 402
        let dy = size.height - 874 * s
        let skyStops = zip(p.sky, [0, 0.42, 0.72, 0.88, 1.0]).map { Gradient.Stop(color: $0.0, location: $0.1) }
        gc.fill(Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(Gradient(stops: skyStops), startPoint: .zero, endPoint: CGPoint(x: 0, y: dy + 560 * s)))

        var g = gc
        g.translateBy(x: 0, y: dy)
        g.scaleBy(x: s, y: s)
        let top = -dy / s, w: CGFloat = 402

        if night {
            for star in layout.stars {
                let a = 0.35 + 0.45 * (0.5 + 0.5 * sin(t * 0.8 + star.phase))
                g.fill(Path(ellipseIn: CGRect(x: star.x - star.r, y: star.y - star.r, width: star.r * 2, height: star.r * 2)), with: .color(.white.opacity(a)))
            }
        }
        // The sun's (or moon's) glow breathes over 12 seconds.
        let breath = 0.5 + 0.5 * sin(t / 12 * 2 * .pi)
        let haloR = (night ? 170 : 260) + 20 * breath
        g.fill(Path(CGRect(x: 0, y: top, width: w, height: 874 - top)),
               with: .radialGradient(Gradient(stops: [.init(color: p.halo.opacity(0.75), location: 0), .init(color: p.halo.opacity(0.42), location: 0.12),
                                                      .init(color: p.halo.opacity(0.1), location: 0.4), .init(color: p.halo.opacity(0), location: 1)]),
                                     center: p.sun, startRadius: 0, endRadius: haloR))
        let r = p.sunRadius
        g.fill(Path(ellipseIn: CGRect(x: p.sun.x - r, y: p.sun.y - r, width: r * 2, height: r * 2)), with: .color(p.sunCore.opacity(0.92)))
        if night {
            let m = CGRect(x: p.sun.x + 7 - r * 0.9, y: p.sun.y - 5 - r * 0.9, width: r * 1.8, height: r * 1.8)
            g.fill(Path(ellipseIn: m), with: .color(p.sky[1]))
        }
        for cloud in layout.clouds {
            let x = (cloud.x + t * cloud.speed).truncatingRemainder(dividingBy: w + cloud.w * 2) - cloud.w
            soft(&g, center: CGPoint(x: x, y: cloud.y), width: cloud.w, squash: 0.16, color: Color(red: 0.9, green: 0.88, blue: 0.86), alpha: 0.12)
        }
        for (i, layer) in layout.layers.enumerated() {
            let off = t * layer.speed
            func ridge(_ x: CGFloat) -> CGFloat {
                layer.y - layer.amp * (0.6 * sin((x + off) * layer.f.0 + layer.ph.0) + 0.4 * sin((x + off) * layer.f.1 + layer.ph.1))
            }
            let (light, dark) = p.hills[i]
            var hill = Path()
            hill.move(to: CGPoint(x: -4, y: 1300))
            hill.addLine(to: CGPoint(x: -4, y: ridge(-4)))
            for x in stride(from: CGFloat(0), through: w, by: 4) { hill.addLine(to: CGPoint(x: x, y: ridge(x))) }
            // 402 isn't a multiple of 4: end the ridge exactly at (and a little past) the right edge,
            // or a sliver of sky shows down that side.
            hill.addLine(to: CGPoint(x: w, y: ridge(w)))
            hill.addLine(to: CGPoint(x: w + 4, y: ridge(w + 4)))
            hill.addLine(to: CGPoint(x: w + 4, y: 1300))
            hill.closeSubpath()
            g.fill(hill, with: .linearGradient(Gradient(stops: [.init(color: light, location: 0), .init(color: dark, location: 0.5)]),
                                               startPoint: CGPoint(x: 0, y: layer.y - layer.amp), endPoint: CGPoint(x: 0, y: 874)))
            var trees = Path()
            for tree in layer.trees {
                let span = w + 120
                let x = ((tree.x - off).truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span) - 60
                let base = ridge(x) + 4, h = (14 + CGFloat(i) * 7) * tree.h, half = h * 0.34
                for k in 0..<3 {
                    let kk = CGFloat(k)
                    let tip = base - h * (0.35 + kk * 0.28) - h * 0.18, bottom = base - h * (kk * 0.25), wk = half * (1 - kk * 0.22)
                    trees.move(to: CGPoint(x: x, y: tip))
                    trees.addLine(to: CGPoint(x: x + wk, y: bottom))
                    trees.addLine(to: CGPoint(x: x - wk, y: bottom))
                    trees.closeSubpath()
                }
                trees.addRect(CGRect(x: x - 1, y: base - 3, width: 2, height: 4))
            }
            g.fill(trees, with: .color(dark))
            for mist in layout.mists where mist.y >= layer.y - 10 && mist.y <= layer.y + 60 {
                let x = (mist.x + t * mist.speed).truncatingRemainder(dividingBy: w + mist.w * 2) - mist.w
                let a = mist.alpha * (0.75 + 0.25 * sin(t * 0.4 + mist.x))
                soft(&g, center: CGPoint(x: x, y: mist.y), width: mist.w, squash: mist.h / (mist.w / 2), color: p.mist, alpha: a)
            }
        }
        for mote in layout.motes {
            let x = mote.x + sin(t * 0.25 + mote.phase) * 14, y = mote.y - sin(t * 0.18 + mote.phase * 2) * 10
            let a = 0.18 + 0.25 * (0.5 + 0.5 * sin(t * 0.7 + mote.phase))
            let rr = mote.r * 4
            g.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)),
                   with: .radialGradient(Gradient(colors: [p.mote.opacity(a), p.mote.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: rr))
        }
    }
}
