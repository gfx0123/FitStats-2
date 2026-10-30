import Charts
import SwiftUI

/// Home: resting heart rate for the 30 days ending on `date`, as a line with one point per
/// recorded day. Days without a reading stay empty (the line breaks there, nothing is filled
/// in). Shows the reading on `date` (or the latest one in the window, labelled with its day)
/// against your 30-day baseline; lower is better. Tapping opens the resting heart rate detail.
struct RestingHRTrendCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    /// How many days the card covers (a Home card setting).
    var windowDays = 30

    var body: some View {
        let trend = trendDays()
        let points = chartPoints(trend)
        let latest = points.last
        let baseline = latest.flatMap { roundedBaseline(before: $0.day) }
        NavigationLink(value: DetailRoute.metric("rhr")) {
            Card {
                header(recordedCount: points.count)
                if let latest {
                    summary(latest: latest, baseline: baseline)
                    chart(points, highlighted: latest, baseline: baseline)
                    legend(points, baseline: baseline)
                } else {
                    EmptyStateView(icon: "heart.text.square", title: "No resting heart rate yet", message: emptyMessage)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary(latest: latest, baseline: baseline, count: points.count))
        .accessibilityValue(points.isEmpty ? "" : spokenRange(points))
        .accessibilityHint("Opens resting heart rate details")
        .accessibilityIdentifier("resting-hr-trend")
    }

    // MARK: sections

    private func header(recordedCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title: "Resting heart rate trend", subtitle: subtitle(recordedCount: recordedCount))
            Spacer()
            Image(systemName: "chevron.right")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func summary(latest: RestingHRPoint, baseline: Double?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.number(latest.value))
                        .font(Font.fredoka(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("bpm")
                        .font(Font.fredoka(16, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    DeltaBadge(change: difference(latest, baseline: baseline), better: .lower, suffix: " bpm")
                }
                Text(dayCaption(latest.day))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(baseline.map { "\(Format.number($0)) bpm" } ?? "–")
                    .font(Font.fredoka(20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(baseline == nil ? "No baseline yet" : "30-day baseline")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private func chart(_ points: [RestingHRPoint], highlighted: RestingHRPoint, baseline: Double?) -> some View {
        let start = Format.chartDate(Format.addDays(date, -(windowDays - 1))) ?? highlighted.date
        let end = Format.chartDate(date) ?? highlighted.date
        let halfDay: TimeInterval = 12 * 3600
        let lower = start.addingTimeInterval(-halfDay)
        let upper = max(end, start).addingTimeInterval(halfDay)
        let ticks = ChartAxis.dayTicks([start, end])
        let label = ChartAxis.dayLabel(false)
        let values = points.map(\.value) + (baseline.map { [$0] } ?? [])
        let domain = ChartAxis.paddedDomain(values, includeZero: false)
        Chart {
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(points) { p in
                LineMark(
                    x: .value("Day", p.date),
                    y: .value("Resting heart rate", p.value),
                    series: .value("Run", p.run)
                )
                .foregroundStyle(Theme.heart)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                PointMark(x: .value("Day", p.date), y: .value("Resting heart rate", p.value))
                    .foregroundStyle(Theme.heart)
                    .symbolSize(14)
            }
            PointMark(x: .value("Day", highlighted.date), y: .value("Resting heart rate", highlighted.value))
                .foregroundStyle(Color.white)
                .symbolSize(48)
        }
        .chartXScale(domain: lower...upper)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel(format: label, centered: false)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Format.number(v)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartTapBubble(points.map { p in
            ChartPoint(x: p.date, y: p.value, title: "Resting HR \(Int(p.value.rounded())) bpm",
                       subtitle: p.date.formatted(.dateTime.month(.wide).day()))
        }, tint: Theme.heart)
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resting heart rate line chart, \(windowDays) days ending \(Format.longDay(date))")
        .accessibilityValue(spokenDays(points))
    }

    private func legend(_ points: [RestingHRPoint], baseline: Double?) -> some View {
        let low = points.map(\.value).min()
        let high = points.map(\.value).max()
        return HStack(spacing: 6) {
            if baseline != nil {
                RestingHRDashLine()
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 16, height: 2)
                Text("30-day baseline")
            }
            Spacer(minLength: 8)
            Text("Low \(Format.number(low)) · High \(Format.number(high)) bpm")
                .monospacedDigit()
        }
        .font(Font.fs(.caption2))
        .foregroundStyle(Theme.tertiary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    // MARK: data

    /// The 30 days ending on `date`, oldest first; `value` is nil for a day without a reading.
    private func trendDays() -> [RestingHRDay] {
        (0..<windowDays).reversed().map { offset -> RestingHRDay in
            let d = Format.addDays(date, -offset)
            return RestingHRDay(date: d, value: restingHR(on: d))
        }
    }

    /// Resting heart rate is a daily value, not a growing day total, but it still goes through
    /// `countsToward` like every other compared value. Zero is not a reading.
    private func restingHR(on d: String) -> Double? {
        guard let def = MetricCatalog.def("rhr"), let day = model.daysByDate[d],
              model.countsToward(def, day), let v = def.value(day), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// Recorded days only. `run` changes after every missing day, so the line breaks at gaps
    /// instead of drawing a value that was never measured.
    private func chartPoints(_ trend: [RestingHRDay]) -> [RestingHRPoint] {
        var out: [RestingHRPoint] = []
        var run = 0
        var gap = false
        for d in trend {
            if let v = d.value, let chartDate = Format.chartDate(d.date) {
                if gap && !out.isEmpty { run += 1 }
                gap = false
                out.append(RestingHRPoint(day: d.date, date: chartDate, value: v, run: run))
            } else {
                gap = true
            }
        }
        return out
    }

    /// Mean of the 30 days before `day` (nil with fewer than 3 readings), rounded to whole
    /// bpm so the shown baseline and the difference badge always agree.
    private func roundedBaseline(before day: String) -> Double? {
        guard let def = MetricCatalog.def("rhr"), let base = model.baseline(def, before: day), base.isFinite else { return nil }
        return base.rounded()
    }

    /// Whole bpm, reading minus baseline (negative = lower = better).
    private func difference(_ point: RestingHRPoint, baseline: Double?) -> Double? {
        guard let baseline else { return nil }
        return point.value.rounded() - baseline
    }

    private func dayCaption(_ day: String) -> String {
        let pretty = Format.prettyDay(day, today: model.today)
        return day == date ? pretty : "Latest: \(pretty)"
    }

    private func subtitle(recordedCount: Int) -> String {
        let first = Format.addDays(date, -(windowDays - 1))
        let range = "\(Format.shortDay(first)) – \(Format.shortDay(date))"
        if recordedCount == 0 || recordedCount >= windowDays { return range }
        return "\(range) · \(recordedCount) of \(windowDays) days recorded"
    }

    private var emptyMessage: String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        return "No resting heart rate was recorded in the \(windowDays) days ending \(Format.shortDay(date))."
    }

    // MARK: accessibility

    private func accessibilitySummary(latest: RestingHRPoint?, baseline: Double?, count: Int) -> String {
        var parts = ["Resting heart rate trend, \(windowDays) days ending \(Format.longDay(date))"]
        guard let latest else {
            parts.append("No resting heart rate recorded")
            return parts.joined(separator: ". ")
        }
        let day = latest.day == date
            ? Format.prettyDay(latest.day, today: model.today)
            : "Latest reading, \(Format.longDay(latest.day))"
        var reading = "\(day): \(Format.number(latest.value)) beats per minute"
        if let baseline, let diff = difference(latest, baseline: baseline) {
            let base = "your 30-day baseline of \(Format.number(baseline))"
            if abs(diff) < 0.5 {
                reading += ", in line with \(base)"
            } else {
                reading += ", \(Format.number(abs(diff))) \(diff < 0 ? "below" : "above") \(base)"
            }
        } else {
            reading += ", no baseline yet"
        }
        parts.append(reading)
        parts.append("Recorded on \(count) of \(windowDays) days")
        return parts.joined(separator: ". ")
    }

    private func spokenRange(_ points: [RestingHRPoint]) -> String {
        guard let low = points.min(by: { $0.value < $1.value }),
              let high = points.max(by: { $0.value < $1.value }) else { return "" }
        return "Lowest \(Format.number(low.value)) on \(Format.longDay(low.day)), highest \(Format.number(high.value)) on \(Format.longDay(high.day))"
    }

    private func spokenDays(_ points: [RestingHRPoint]) -> String {
        points.map { p -> String in
            "\(Format.longDay(p.day)), \(Format.number(p.value)) beats per minute"
        }
        .joined(separator: ". ")
    }
}

private struct RestingHRDay: Identifiable {
    let date: String
    let value: Double?
    var id: String { date }
}

private struct RestingHRPoint: Identifiable {
    let day: String
    let date: Date
    let value: Double
    let run: Int
    var id: String { day }
}

/// A horizontal line through the middle of its frame (the legend's dashed baseline sample).
private struct RestingHRDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
