import SwiftUI

/// Sleep: the last 14 nights as bars from falling asleep to waking up, so irregular nights stand
/// out, with the usual times (the middle night of the 14) as dashed lines, the wake-up times set
/// by hand as marks, and how much bedtimes and wake times varied.
struct BedtimeConsistencyCard: View {
    let endDate: String
    @EnvironmentObject private var model: AppModel

    private struct Night: Identifiable {
        let date: String
        /// Minutes from the wake-up day's midnight (negative = the evening before).
        let bed: Double
        let wake: Double
        let setWake: Double?
        var id: String { date }
    }

    private static let count = 14

    var body: some View {
        let nights = recentNights()
        if nights.count >= 3 {
            let beds = nights.map(\.bed).sorted(), wakes = nights.map(\.wake).sorted()
            let usualBed = Self.median(beds), usualWake = Self.median(wakes)
            Card {
                SectionHeader(title: "Bedtime consistency", subtitle: "Last \(Self.count) nights, asleep to awake")
                // Drawn by hand: a fixed column of day labels, so they never sit on the bars.
                let lowest = beds.first! - 30, highest = wakes.last! + 30
                Canvas { ctx, size in
                    Self.draw(nights, in: ctx, size: size, from: lowest, to: highest, usualBed: usualBed, usualWake: usualWake)
                }
                .frame(height: CGFloat(nights.count) * Self.rowHeight + 22)
                Text(summary(beds: beds, wakes: wakes, usualBed: usualBed, usualWake: usualWake))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    legend(Capsule().fill(Theme.sleep), "Asleep")
                    legend(Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(Theme.secondary), "Usual times")
                    if nights.contains(where: { $0.setWake != nil }) {
                        legend(Image(systemName: "diamond.fill").font(Font.fredoka(7, weight: .regular)).foregroundStyle(Theme.recoveryYellow), "Wake-up you set")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bedtime-consistency")
        }
    }

    private static let rowHeight: CGFloat = 18
    private static let labelWidth: CGFloat = 58

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEd")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Day labels, then each night's bar from asleep to awake, the set wake-up as a diamond, the
    /// usual times as dashed lines and a time axis every 2 hours below.
    nonisolated private static func draw(_ nights: [Night], in ctx: GraphicsContext, size: CGSize, from lowest: Double, to highest: Double,
                             usualBed: Double, usualWake: Double) {
        let left = labelWidth + 6, right = size.width - 4
        let x = { (m: Double) -> CGFloat in left + (right - left) * CGFloat((m - lowest) / max(1, highest - lowest)) }
        let rowsBottom = CGFloat(nights.count) * rowHeight
        // Grid and time labels every 2 hours.
        var tick = (lowest / 120).rounded(.up) * 120
        while tick <= highest {
            var line = Path()
            line.move(to: CGPoint(x: x(tick), y: 0))
            line.addLine(to: CGPoint(x: x(tick), y: rowsBottom))
            ctx.stroke(line, with: .color(Theme.track), lineWidth: 0.5)
            ctx.draw(Text(Format.clock(tick)).font(Font.fs(.caption2)).foregroundColor(Theme.tertiary), at: CGPoint(x: x(tick), y: rowsBottom + 4), anchor: .top)
            tick += 120
        }
        for (i, n) in nights.enumerated() {
            let y = CGFloat(i) * rowHeight + rowHeight / 2
            let label = Format.date(n.date).map { dayFormatter.string(from: $0) } ?? n.date
            ctx.draw(Text(label).font(Font.fs(.caption2)).foregroundColor(Theme.secondary), at: CGPoint(x: 0, y: y), anchor: .leading)
            let bar = CGRect(x: x(n.bed), y: y - 4.5, width: max(4, x(n.wake) - x(n.bed)), height: 9)
            ctx.fill(Path(roundedRect: bar, cornerRadius: 4.5), with: .color(Theme.sleep))
            if let set = n.setWake {
                var diamond = Path()
                let c = CGPoint(x: x(set), y: y)
                diamond.move(to: CGPoint(x: c.x, y: c.y - 5))
                diamond.addLine(to: CGPoint(x: c.x + 4, y: c.y))
                diamond.addLine(to: CGPoint(x: c.x, y: c.y + 5))
                diamond.addLine(to: CGPoint(x: c.x - 4, y: c.y))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(Theme.recoveryYellow))
            }
        }
        for usual in [usualBed, usualWake] {
            var line = Path()
            line.move(to: CGPoint(x: x(usual), y: 0))
            line.addLine(to: CGPoint(x: x(usual), y: rowsBottom))
            ctx.stroke(line, with: .color(Theme.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func legend(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 4) {
            mark.frame(width: 10, height: 6)
            Text(text).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
    }

    /// The nights ending on the 14 days up to `endDate` that have both times.
    private func recentNights() -> [Night] {
        let times = model.wakeTimes
        return (0..<Self.count).reversed().compactMap { offset -> Night? in
            let date = Format.addDays(endDate, -offset)
            guard let day = model.daysByDate[date], let bed = day.double("sleep_bedtime_min"), let wake = day.double("sleep_waketime_min"), wake > bed else { return nil }
            let set = times.flatMap { $0[SleepPlan.weekdayIndex(date)] }.map(Double.init)
            return Night(date: date, bed: bed, wake: wake, setWake: set)
        }
    }

    /// "Usually asleep by 23:20 and up at 7:05. Bedtimes varied by about 35 min, wake times by 20 min."
    private func summary(beds: [Double], wakes: [Double], usualBed: Double, usualWake: Double) -> String {
        let bedSpread = Self.median(beds.map { abs($0 - usualBed) }).rounded()
        let wakeSpread = Self.median(wakes.map { abs($0 - usualWake) }).rounded()
        let verdict = max(bedSpread, wakeSpread) <= 30 ? "That's regular." : max(bedSpread, wakeSpread) <= 60 ? "Fairly regular." : "Quite irregular: a steadier bedtime tends to help."
        return "Usually asleep by \(Format.clock(usualBed)) and up at \(Format.clock(usualWake)). On a typical night, bedtime is \(Format.duration(bedSpread)) "
            + "from that and wake-up \(Format.duration(wakeSpread)). \(verdict)"
    }

    private static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
