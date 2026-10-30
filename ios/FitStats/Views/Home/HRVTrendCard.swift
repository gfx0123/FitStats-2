import Charts
import SwiftUI

/// Home: HRV (RMSSD) over the 30 days ending on `date`. Shows the value on `date`, its
/// difference from your 30-day baseline (`model.baseline`: the mean of the 30 days before it),
/// and a line chart with your normal range shaded (mean ± 1 standard deviation of those same
/// 30 days before `date`, so the day being judged is never part of the range it is judged
/// against). Days without HRV stay empty: the line breaks there and nothing is filled in.
/// Tapping opens the HRV metric detail.
struct HRVTrendCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    private static let metricKey = "hrv_rmssd"
    /// How many days the card covers (a Home card setting).
    var windowDays = 30
    /// Days with HRV needed before a standard deviation says anything.
    private static let minBandDays = 5
    private static let tint = Theme.heart

    var body: some View {
        let data = trendData()
        let label: String = accessibilitySummary(data)
        let spoken: String = data.map { chartSummary($0) } ?? ""
        NavigationLink(value: DetailRoute.metric(Self.metricKey)) {
            Card {
                header
                if let data, !data.points.isEmpty {
                    summary(data)
                    chartSection(data)
                } else {
                    EmptyStateView(icon: "waveform.path", title: "No HRV yet", message: emptyMessage)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
        .accessibilityHint("Opens HRV details")
        .accessibilityIdentifier("hrv-trend")
    }

    // MARK: sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title: "HRV trend", subtitle: rangeText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private func summary(_ data: HRVTrendData) -> some View {
        let change = percentChange(data)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.prettyDay(date, today: model.today))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.number(data.latest))
                        .font(Font.fredoka(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if data.latest != nil {
                        Text(data.def.unit)
                            .font(Font.fredoka(15, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                    }
                    DeltaBadge(change: change, better: data.def.better)
                        .padding(.leading, 2)
                }
                Text(baselineText(data))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let latest = data.latest, let band = data.band {
                statusPill(HRVTrendPosition(latest, band: band))
            }
        }
    }

    private func statusPill(_ position: HRVTrendPosition) -> some View {
        Text(position.label)
            .font(Font.fs(.caption2, .semibold))
            .lineLimit(1)
            .foregroundStyle(position.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(position.color.opacity(0.16)))
    }

    @ViewBuilder private func chartSection(_ data: HRVTrendData) -> some View {
        if data.points.count >= 2 {
            HRVTrendChart(points: data.points, firstDay: data.firstDay, lastDay: data.lastDay,
                          band: data.band, selected: date, def: data.def, color: Self.tint)
                .frame(height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("HRV line chart, 30 days ending \(Format.longDay(date))")
                .accessibilityValue(chartSummary(data))
            legend(data)
        } else {
            Text("Only one day with HRV in these 30 days, not enough for a trend yet.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private func legend(_ data: HRVTrendData) -> some View {
        if let band = data.band {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Self.tint.opacity(0.3))
                    .frame(width: 12, height: 8)
                Text("Normal range \(bandText(band, data.def)) (mean ± 1 SD, \(band.count) days with HRV in the \(windowDays) before \(Format.shortDay(date)))")
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
            }
            .accessibilityHidden(true)
        } else {
            Text("The normal range appears once \(Self.minBandDays) of the \(windowDays) days before \(Format.shortDay(date)) have HRV.")
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(2)
        }
    }

    // MARK: data

    private func trendData() -> HRVTrendData? {
        guard let def = MetricCatalog.def(Self.metricKey) else { return nil }
        let start = Format.addDays(date, -(windowDays - 1))
        guard let firstDay = Format.chartDate(start), let lastDay = Format.chartDate(date) else { return nil }
        var points: [HRVTrendPoint] = []
        var run = 0
        var previousOffset: Int? = nil
        for offset in 0..<windowDays {
            let ymd = Format.addDays(start, offset)
            guard let v = value(of: def, on: ymd), let when = Format.chartDate(ymd) else { continue }
            // A missing day starts a new line segment, so the chart never bridges a gap.
            if let previous = previousOffset, offset - previous > 1 { run += 1 }
            points.append(HRVTrendPoint(ymd: ymd, date: when, value: v, run: run))
            previousOffset = offset
        }
        // The same 30 days before `date` as `model.baseline`, so the range and the badge agree.
        let before = (1...windowDays).compactMap { back -> Double? in
            value(of: def, on: Format.addDays(date, -back))
        }
        return HRVTrendData(
            def: def,
            firstDay: firstDay,
            lastDay: lastDay,
            points: points,
            latest: value(of: def, on: date),
            baseline: model.baseline(def, before: date),
            band: HRVTrendBand(values: before, minCount: Self.minBandDays)
        )
    }

    /// HRV is a nightly value, not a growing day total, but it still goes through
    /// `countsToward` like every other compared value.
    private func value(of def: MetricDef, on ymd: String) -> Double? {
        guard let day = model.daysByDate[ymd], model.countsToward(def, day) else { return nil }
        guard let v = def.value(day), v.isFinite else { return nil }
        return v
    }

    private func percentChange(_ data: HRVTrendData) -> Double? {
        guard let latest = data.latest, let baseline = data.baseline, baseline > 0 else { return nil }
        return (latest - baseline) / baseline * 100
    }

    private func baselineText(_ data: HRVTrendData) -> String {
        guard let latest = data.latest else {
            if date == model.today { return "No HRV for today yet. It appears after your band syncs." }
            return "No HRV recorded on this day."
        }
        guard let baseline = data.baseline else {
            return "A baseline needs 3 days with HRV in the 30 days before."
        }
        let diff = latest - baseline
        let base = data.def.formatted(baseline)
        if abs(diff) < 0.5 { return "Level with your 30-day baseline (\(base))" }
        return "\(Format.signed(diff)) \(data.def.unit) vs 30-day baseline (\(base))"
    }

    private func bandText(_ band: HRVTrendBand, _ def: MetricDef) -> String {
        "\(Format.number(band.low))–\(Format.number(band.high)) \(def.unit)"
    }

    private var rangeText: String {
        let start = Format.addDays(date, -(windowDays - 1))
        return "\(Format.shortDay(start)) – \(Format.shortDay(date))"
    }

    private var emptyMessage: String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        return "No HRV in the 30 days ending \(Format.shortDay(date)). HRV is measured while you sleep, so wear your band overnight."
    }

    // MARK: accessibility

    private func accessibilitySummary(_ data: HRVTrendData?) -> String {
        var parts = ["HRV trend, 30 days ending \(Format.longDay(date))"]
        guard let data, !data.points.isEmpty else {
            parts.append("No HRV recorded yet")
            return parts.joined(separator: ". ")
        }
        let day = Format.prettyDay(date, today: model.today)
        guard let latest = data.latest else {
            parts.append("\(day): no HRV recorded")
            return parts.joined(separator: ". ")
        }
        var line = "\(day): \(Format.number(latest)) milliseconds"
        if let baseline = data.baseline {
            let diff = latest - baseline
            if abs(diff) < 0.5 {
                line += ", level with your 30-day baseline"
            } else {
                let direction = diff > 0 ? "above" : "below"
                line += ", \(Format.number(abs(diff))) milliseconds \(direction) your 30-day baseline of \(Format.number(baseline))"
            }
        }
        if let band = data.band {
            line += ", \(HRVTrendPosition(latest, band: band).spoken)"
        }
        parts.append(line)
        return parts.joined(separator: ". ")
    }

    private func chartSummary(_ data: HRVTrendData) -> String {
        guard let lowest = data.points.min(by: { $0.value < $1.value }),
              let highest = data.points.max(by: { $0.value < $1.value }) else { return "No HRV recorded" }
        var parts = ["\(data.points.count) of \(windowDays) days with HRV"]
        parts.append("Lowest \(Format.number(lowest.value)) milliseconds on \(Format.longDay(lowest.ymd))")
        parts.append("Highest \(Format.number(highest.value)) milliseconds on \(Format.longDay(highest.ymd))")
        if let band = data.band {
            parts.append("Normal range \(Format.number(band.low)) to \(Format.number(band.high)) milliseconds")
            let above = data.points.filter { $0.value > band.high }.count
            let below = data.points.filter { $0.value < band.low }.count
            let aboveText = above == 1 ? "1 day above it" : "\(above) days above it"
            parts.append("\(aboveText), \(below) below")
        }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Data

private struct HRVTrendData {
    let def: MetricDef
    /// Local midnights of the first and last day of the window (`date`).
    let firstDay: Date
    let lastDay: Date
    /// Days with HRV, oldest first.
    let points: [HRVTrendPoint]
    /// HRV on `date`.
    let latest: Double?
    /// Mean of the 30 days before `date` (nil with fewer than 3 such days).
    let baseline: Double?
    /// Mean ± 1 SD of the 30 days before `date`, the baseline's window (nil with too few days).
    let band: HRVTrendBand?
}

private struct HRVTrendPoint: Identifiable {
    let ymd: String
    let date: Date
    let value: Double
    /// Consecutive days share a run; a missing day starts the next one.
    let run: Int
    var id: String { ymd }
}

/// Normal range: mean ± 1 sample standard deviation (n − 1, as in the server's stats).
private struct HRVTrendBand {
    let mean: Double
    let sd: Double
    let count: Int

    var low: Double { max(0, mean - sd) }
    var high: Double { mean + sd }

    init?(values: [Double], minCount: Int) {
        guard values.count >= max(2, minCount) else { return nil }
        let n = Double(values.count)
        let m = values.reduce(0, +) / n
        let squares = values.reduce(0.0) { acc, v in acc + (v - m) * (v - m) }
        mean = m
        sd = (squares / (n - 1)).squareRoot()
        count = values.count
    }
}

private enum HRVTrendPosition {
    case below, within, above

    init(_ value: Double, band: HRVTrendBand) {
        if value < band.low {
            self = .below
        } else if value > band.high {
            self = .above
        } else {
            self = .within
        }
    }

    var label: String {
        switch self {
        case .below: return "Below normal"
        case .within: return "Within normal"
        case .above: return "Above normal"
        }
    }

    var spoken: String {
        switch self {
        case .below: return "below your normal range"
        case .within: return "within your normal range"
        case .above: return "above your normal range"
        }
    }

    var color: Color {
        switch self {
        case .below: return Theme.recoveryYellow
        case .within: return Theme.secondary
        case .above: return Theme.recoveryGreen
        }
    }
}

// MARK: - Chart

/// Daily HRV as a line (broken at missing days) over the shaded normal range; the selected
/// day's point is drawn larger and white.
private struct HRVTrendChart: View {
    let points: [HRVTrendPoint]
    let firstDay: Date
    let lastDay: Date
    let band: HRVTrendBand?
    let selected: String
    let def: MetricDef
    let color: Color

    var body: some View {
        // Half a day of room on each side keeps the end points inside the plot.
        let xStart = firstDay.addingTimeInterval(-12 * 3600)
        let xEnd = lastDay.addingTimeInterval(12 * 3600)
        let bandValues: [Double] = band.map { [$0.low, $0.high] } ?? []
        let domain = ChartAxis.paddedDomain(points.map(\.value) + bandValues, includeZero: false)
        let axisDecimals = ChartAxis.decimals(for: domain, limit: def.decimals)
        let ticks = ChartAxis.dayTicks([firstDay, lastDay])
        let label = ChartAxis.dayLabel(false)
        Chart {
            if let band {
                RectangleMark(
                    xStart: .value("Start", xStart),
                    xEnd: .value("End", xEnd),
                    yStart: .value("Low", band.low),
                    yEnd: .value("High", band.high)
                )
                .foregroundStyle(color.opacity(0.18))
            }
            ForEach(points) { p in
                LineMark(x: .value("Day", p.date), y: .value("HRV", p.value), series: .value("Run", p.run))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Day", p.date), y: .value("HRV", p.value))
                    .foregroundStyle(p.ymd == selected ? Color.white : color)
                    .symbolSize(p.ymd == selected ? 48 : 14)
            }
        }
        .chartLegend(.hidden)
        .chartXScale(domain: xStart...xEnd)
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
                        Text(def.formatted(v, withUnit: false, decimals: axisDecimals)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
    }
}
