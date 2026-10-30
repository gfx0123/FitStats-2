import SwiftUI

struct HypnogramSegment: Equatable {
    let code: Int
    let start: Date
    let end: Date
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

/// Lanes and time range for one night. Stage sessions show Awake / REM / Light / Deep;
/// classic sessions (older devices, short naps) only have Awake / Restless / Asleep.
struct HypnogramLayout {
    let segments: [HypnogramSegment]
    let classic: Bool
    let start: Date
    let end: Date

    init(stages: [[Double]]) {
        segments = stages.compactMap { s -> HypnogramSegment? in
            guard s.count >= 3, s[2] > s[1] else { return nil }
            return HypnogramSegment(code: Int(s[0]), start: Date(timeIntervalSince1970: s[1]), end: Date(timeIntervalSince1970: s[2]))
        }
        .sorted { $0.start < $1.start }
        classic = !segments.contains { [1, 2, 3].contains($0.code) }
        start = segments.first?.start ?? Date()
        end = segments.map(\.end).max() ?? start
    }

    var lanes: [(name: String, color: Color)] {
        classic
            ? [("Awake", Theme.stageAwake), ("Restless", Theme.stageRestless), ("Asleep", Theme.stageLight)]
            : [("Awake", Theme.stageAwake), ("REM", Theme.stageRem), ("Light", Theme.stageLight), ("Deep", Theme.stageDeep)]
    }

    func lane(of code: Int) -> Int {
        if classic { return code == 0 ? 0 : code == 5 ? 1 : 2 }
        switch code {
        case 0: return 0
        case 3: return 1
        case 2: return 3
        default: return 2
        }
    }

    func color(of code: Int) -> Color { lanes[lane(of: code)].color }

    func name(of code: Int) -> String { lanes[lane(of: code)].name }

    /// Minutes per stage code, summed from the segments.
    func minutes(_ code: Int) -> Double {
        segments.filter { $0.code == code }.reduce(0) { $0 + $1.minutes }
    }

    func segment(at date: Date) -> HypnogramSegment? {
        segments.last { $0.start <= date && date < $0.end }
    }
}

/// One night as stage lanes (Awake on top, Deep at the bottom) joined by connectors,
/// like the Health app's sleep chart. Tap a stage to read it; tap it again to clear.
/// (A tap, unlike a drag, never competes with scrolling the page.)
struct HypnogramView: View {
    let layout: HypnogramLayout
    var zone: TimeZone?
    var onSelect: (HypnogramSegment?) -> Void = { _ in }

    @State var scrubX: CGFloat?

    private let labelWidth: CGFloat = 52
    private let axisHeight: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(&ctx, size: size) }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { location in
                    let width = geo.size.width
                    let x = min(max(location.x, labelWidth), width - 2)
                    let tapped = layout.segment(at: date(atX: x, width: width))
                    let current = scrubX.flatMap { layout.segment(at: date(atX: $0, width: width)) }
                    if tapped == nil || tapped == current {
                        scrubX = nil
                        onSelect(nil)
                    } else {
                        scrubX = x
                        onSelect(tapped)
                    }
                }
        }
        .frame(height: 190)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var span: TimeInterval { max(60, layout.end.timeIntervalSince(layout.start)) }

    private func x(_ d: Date, width: CGFloat) -> CGFloat {
        labelWidth + CGFloat(d.timeIntervalSince(layout.start) / span) * (width - 2 - labelWidth)
    }

    private func date(atX x: CGFloat, width: CGFloat) -> Date {
        let f = Double((x - labelWidth) / max(1, width - 2 - labelWidth))
        return layout.start.addingTimeInterval(f * span)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize) {
        let lanes = layout.lanes
        let plotHeight = size.height - axisHeight
        let laneHeight = plotHeight / CGFloat(lanes.count)
        let left = labelWidth, right = size.width - 2
        func midY(_ lane: Int) -> CGFloat { laneHeight * (CGFloat(lane) + 0.5) }

        for (i, lane) in lanes.enumerated() {
            let rect = CGRect(x: left, y: laneHeight * CGFloat(i) + 2, width: right - left, height: laneHeight - 4)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 7), with: .color(.white.opacity(0.035)))
            ctx.draw(Text(lane.name).font(Font.fs(.caption2, .semibold)).foregroundStyle(lane.color),
                     at: CGPoint(x: 0, y: midY(i)), anchor: .leading)
        }

        let ticks = ChartAxis.hourTicks(from: layout.start, to: layout.end, zone: zone)
        for t in ticks {
            let px = x(t, width: size.width)
            var grid = Path()
            grid.move(to: CGPoint(x: px, y: 2))
            grid.addLine(to: CGPoint(x: px, y: plotHeight - 2))
            ctx.stroke(grid, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }

        // Connectors first, so the stage bars sit on top of them.
        for (a, b) in zip(layout.segments, layout.segments.dropFirst()) where b.start.timeIntervalSince(a.end) < 180 {
            let la = layout.lane(of: a.code), lb = layout.lane(of: b.code)
            guard la != lb else { continue }
            let px = x(b.start, width: size.width)
            let p1 = CGPoint(x: px, y: midY(la)), p2 = CGPoint(x: px, y: midY(lb))
            var line = Path()
            line.move(to: p1)
            line.addLine(to: p2)
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [layout.color(of: a.code).opacity(0.75), layout.color(of: b.code).opacity(0.75)]),
                                                    startPoint: p1, endPoint: p2), lineWidth: 1.5)
        }

        let barHeight = laneHeight * 0.56
        let active = scrubX.flatMap { layout.segment(at: date(atX: $0, width: size.width)) }
        for s in layout.segments {
            let x0 = x(s.start, width: size.width)
            let x1 = max(x(s.end, width: size.width), x0 + 2)
            let rect = CGRect(x: x0, y: midY(layout.lane(of: s.code)) - barHeight / 2, width: x1 - x0, height: barHeight)
            let color = layout.color(of: s.code)
            let dimmed = active != nil && active != s
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(4, rect.width / 2, rect.height / 2)),
                     with: .linearGradient(Gradient(colors: [color.opacity(dimmed ? 0.35 : 1), color.opacity(dimmed ? 0.25 : 0.78)]),
                                           startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                           endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }

        if let sx = scrubX {
            var cursor = Path()
            cursor.move(to: CGPoint(x: sx, y: 0))
            cursor.addLine(to: CGPoint(x: sx, y: plotHeight))
            ctx.stroke(cursor, with: .color(.white.opacity(0.8)), lineWidth: 1)
        }

        // Bedtime and wake time anchor the axis; whole hours fill in where they fit.
        // Measured, so a 12-hour "6:19 AM" never sits on the hour before it.
        let labelY = plotHeight + 5
        let startLabel = ctx.resolve(Text(Format.time(layout.start, zone: zone)).font(Font.fs(.caption2, .semibold)).foregroundStyle(Theme.secondary))
        let endLabel = ctx.resolve(Text(Format.time(layout.end, zone: zone)).font(Font.fs(.caption2, .semibold)).foregroundStyle(Theme.secondary))
        let unbounded = CGSize(width: CGFloat.infinity, height: .infinity)
        ctx.draw(startLabel, at: CGPoint(x: left, y: labelY), anchor: .topLeading)
        ctx.draw(endLabel, at: CGPoint(x: right, y: labelY), anchor: .topTrailing)
        var free = left + startLabel.measure(in: unbounded).width + 6
        let limit = right - endLabel.measure(in: unbounded).width - 6
        for t in ticks {
            let px = x(t, width: size.width)
            let label = ctx.resolve(Text(Format.hour(t, zone: zone)).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary))
            let half = label.measure(in: unbounded).width / 2
            guard px - half >= free, px + half <= limit else { continue }
            ctx.draw(label, at: CGPoint(x: px, y: labelY), anchor: .top)
            free = px + half + 6
        }
    }

    private var accessibilitySummary: String {
        let parts = layout.lanes.indices.compactMap { lane -> String? in
            let minutes = layout.segments.filter { layout.lane(of: $0.code) == lane }.reduce(0) { $0 + $1.minutes }
            return minutes > 0 ? "\(layout.lanes[lane].name) \(Format.duration(minutes))" : nil
        }
        return "Sleep stages from \(Format.time(layout.start, zone: zone)) to \(Format.time(layout.end, zone: zone)): " + parts.joined(separator: ", ")
    }
}
