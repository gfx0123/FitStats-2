import SwiftUI

/// A front and a back figure with each muscle shaded by how much it was worked: `levels` from
/// 0 (not at all) to 1 (most). The figures are anatomical outlines (BodyMapPaths, from
/// react-native-body-highlighter, MIT); muscles with no level are drawn in the body's base
/// colour, the head, hands, knees and feet in a darker one. Female figures with Sex set to female.
struct BodyMapView: View {
    let levels: [String: Double]
    var color: Color = Theme.muscle
    var height: CGFloat = 230
    var showsLabels = true
    @Environment(\.bodyFigure) private var figure

    var body: some View {
        HStack(spacing: height * 0.06) {
            side(front: true)
            side(front: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("body-map")
    }

    private func side(front: Bool) -> some View {
        let shapes = BodyShapes.figure(figure, front: front)
        let levels = levels
        let color = color
        return VStack(spacing: 4) {
            Canvas { ctx, size in
                BodyShapes.draw(shapes, levels: levels, color: color, in: ctx, size: size)
            }
            .frame(width: height * shapes.aspect, height: height)
            if showsLabels {
                Text(front ? "Front" : "Back").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var accessibilityText: String {
        let worked = levels.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { $0.key.replacingOccurrences(of: "_", with: " ") }
        return worked.isEmpty ? "Body map: no muscles worked" : "Body map, most worked first: \(worked.joined(separator: ", "))"
    }
}

/// A small tile for lists: the side of the body that does most of the work, zoomed in on the
/// main muscles so they read at thumbnail size.
struct BodyMapThumbnail: View {
    let levels: [String: Double]
    var size: CGFloat = 52
    @Environment(\.bodyFigure) private var figure

    var body: some View {
        let levels = levels
        let front = BodyShapes.figure(figure, front: true), back = BodyShapes.figure(figure, front: false)
        let shapes = BodyShapes.worked(back, levels) > BodyShapes.worked(front, levels) ? back : front
        Canvas { ctx, size in
            BodyShapes.draw(shapes, levels: levels, color: Theme.muscle, in: ctx, size: size, area: BodyShapes.focus(shapes, levels: levels))
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

extension Theme {
    /// Muscles on the body map.
    static let muscle = Color(red: 1.0, green: 0.47, blue: 0.32)
}

/// Which figures the body map draws (Settings → Sex; "not set" draws the male ones).
enum BodyFigure {
    case male, female
}

private struct BodyFigureKey: EnvironmentKey {
    static let defaultValue = BodyFigure.male
}

extension EnvironmentValues {
    var bodyFigure: BodyFigure {
        get { self[BodyFigureKey.self] }
        set { self[BodyFigureKey.self] = newValue }
    }
}

/// The body map's figures, made once from BodyMapPaths.
enum BodyShapes {
    struct Figure {
        /// Muscle id → its outline; "" is the body around the muscles.
        let regions: [(muscle: String, path: Path)]
        /// The part of the 724 × 1448 box the figure covers.
        let bounds: CGRect
        var aspect: CGFloat { bounds.width / bounds.height }
    }

    private static let maleFront = make(BodyMapPaths.maleFront)
    private static let maleBack = make(BodyMapPaths.maleBack)
    private static let femaleFront = make(BodyMapPaths.femaleFront)
    private static let femaleBack = make(BodyMapPaths.femaleBack)

    static func figure(_ figure: BodyFigure, front: Bool) -> Figure {
        switch (figure, front) {
        case (.male, true): return maleFront
        case (.male, false): return maleBack
        case (.female, true): return femaleFront
        case (.female, false): return femaleBack
        }
    }

    private static func make(_ source: [(String, String)]) -> Figure {
        let regions = source.map { (muscle: $0.0, path: path($0.1)) }
        let bounds = regions.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
        return Figure(regions: regions, bounds: bounds.isNull ? CGRect(x: 0, y: 0, width: 724, height: 1448) : bounds)
    }

    /// How much of the figure's muscles are worked, for picking the side to show.
    static func worked(_ figure: Figure, _ levels: [String: Double]) -> Double {
        figure.regions.reduce(0) { $0 + ($1.muscle.isEmpty ? 0 : levels[$1.muscle] ?? 0) }
    }

    /// A square around the main muscles (all worked ones when none is main), at least 45% of
    /// the figure's height and kept within it top to bottom; nil when nothing is worked.
    static func focus(_ figure: Figure, levels: [String: Double]) -> CGRect? {
        let main = figure.regions.filter { !$0.muscle.isEmpty && (levels[$0.muscle] ?? 0) >= 1 }
        let regions = main.isEmpty ? figure.regions.filter { !$0.muscle.isEmpty && (levels[$0.muscle] ?? 0) > 0 } : main
        guard !regions.isEmpty else { return nil }
        let worked = regions.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
        let b = figure.bounds
        let side = min(max(worked.width, worked.height, b.height * 0.45) * 1.15, b.height)
        let y = min(max(worked.midY - side / 2, b.minY), b.maxY - side)
        return CGRect(x: b.midX - side / 2, y: y, width: side, height: side)
    }

    /// "M x y L x y C x1 y1 x2 y2 x y Z", as body_map.py writes it.
    static func path(_ commands: String) -> Path {
        var p = Path()
        let t = commands.split(separator: " ")
        var i = 0
        func n(_ k: Int) -> CGFloat { CGFloat(Double(t[i + k]) ?? 0) }
        while i < t.count {
            switch t[i] {
            case "M" where i + 2 < t.count:
                p.move(to: CGPoint(x: n(1), y: n(2)))
                i += 3
            case "L" where i + 2 < t.count:
                p.addLine(to: CGPoint(x: n(1), y: n(2)))
                i += 3
            case "C" where i + 6 < t.count:
                p.addCurve(to: CGPoint(x: n(5), y: n(6)), control1: CGPoint(x: n(1), y: n(2)), control2: CGPoint(x: n(3), y: n(4)))
                i += 7
            case "Z":
                p.closeSubpath()
                i += 1
            default:
                i += 1
            }
        }
        return p
    }

    /// Fits the figure into `size` and fills each region: the body, the muscles in the base
    /// colour, then the worked ones in `color` by level.
    static func draw(_ figure: Figure, levels: [String: Double], color: Color, in ctx: GraphicsContext, size: CGSize, area: CGRect? = nil) {
        var ctx = ctx
        let b = area ?? figure.bounds
        let scale = min(size.width / b.width, size.height / b.height)
        ctx.translateBy(x: (size.width - b.width * scale) / 2, y: (size.height - b.height * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -b.minX, y: -b.minY)
        let body = Color.white.opacity(0.06)
        let base = Color.white.opacity(0.13)
        for region in figure.regions {
            guard !region.muscle.isEmpty else {
                ctx.fill(region.path, with: .color(body))
                continue
            }
            let level = levels[region.muscle] ?? 0
            ctx.fill(region.path, with: .color(level > 0 ? color.opacity(0.3 + 0.7 * min(1, level)) : base))
        }
    }
}

/// Muscles as chips: the main ones filled, the helpers outlined.
struct MuscleChips: View {
    let primary: [String]
    let secondary: [String]
    let library: ExerciseLibrary

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(primary, id: \.self) { chip(library.label($0), main: true) }
            ForEach(secondary, id: \.self) { chip(library.label($0), main: false) }
        }
    }

    private func chip(_ label: String, main: Bool) -> some View {
        Text(label)
            .font(Font.fs(.caption, main ? .semibold : .regular))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(main ? Theme.muscle.opacity(0.22) : Color.clear))
            .overlay(Capsule().stroke(Theme.muscle.opacity(main ? 0 : 0.5), lineWidth: 1))
            .foregroundStyle(main ? Theme.muscle : Theme.secondary)
    }
}
