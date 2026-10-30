import Charts
import SwiftUI

/// Words and colours for the server's training-load status (lib/stats.ts, from form / fitness).
enum TrainingLoadStatus {
    static func label(_ status: String) -> String {
        switch status {
        case "calibrating": return "Calibrating"
        case "fresh": return "Fresh"
        case "neutral": return "Neutral"
        case "productive": return "Productive"
        case "overreaching": return "Overreaching"
        default: return status.capitalized
        }
    }

    static func color(_ status: String) -> Color {
        switch status {
        case "fresh": return Theme.recoveryGreen
        case "productive": return Theme.strain
        case "overreaching": return Theme.recoveryRed
        case "calibrating": return Theme.tertiary
        default: return Theme.secondary
        }
    }

    /// Days until the status settles: the server calibrates for 28 days from the first day with
    /// TRIMP, which is where the series starts while it calibrates.
    static func daysToGo(_ load: TrainingLoad, today: String) -> Int {
        guard let first = load.series.map(\.date).min() else { return 28 }
        return Swift.max(1, 28 - Format.daysBetween(first, today))
    }

    static func calibratingText(_ load: TrainingLoad, today: String) -> String {
        let left = daysToGo(load, today: today)
        return "Calibrating: fitness is a 6-week average, so the status needs 4 weeks of history. \(left == 1 ? "1 more day" : "\(left) more days") to go."
    }
}

struct LoadStatusPill: View {
    let status: String

    var body: some View {
        let color = TrainingLoadStatus.color(status)
        Text(TrainingLoadStatus.label(status))
            .font(Font.fs(.caption, .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

private struct LoadLinePoint: Identifiable {
    let date: Date
    let value: Double
    let fitness: Bool
    var id: String
}

/// Fitness (blue) and fatigue (pink) over the last `days` days of the load series.
struct TrainingLoadChart: View {
    let series: [LoadPoint]
    var days: Int = 90
    var height: CGFloat = 170

    static let fitnessColor = Theme.strain
    static let fatigueColor = Theme.heart

    private var points: [LoadLinePoint] {
        guard let last = series.map(\.date).max() else { return [] }
        let from = Format.addDays(last, -(days - 1))
        var out: [LoadLinePoint] = []
        for p in series where p.date >= from {
            guard let date = Format.chartDate(p.date) else { continue }
            out.append(LoadLinePoint(date: date, value: p.ctl, fitness: true, id: "f-\(p.date)"))
            out.append(LoadLinePoint(date: date, value: p.atl, fitness: false, id: "a-\(p.date)"))
        }
        return out
    }

    var body: some View {
        let data = points
        let dates = data.map(\.date)
        let ticks = ChartAxis.dayTicks(dates)
        let label = ChartAxis.dayLabel(false)
        let domain = ChartAxis.paddedDomain(data.map(\.value), includeZero: true)
        Chart {
            ForEach(data) { p in
                LineMark(x: .value("Day", p.date, unit: .day), y: .value("Load", p.value),
                         series: .value("Line", p.fitness ? "Fitness" : "Fatigue"))
                    .foregroundStyle(p.fitness ? Self.fitnessColor : Self.fatigueColor)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel(format: label, centered: false)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().foregroundStyle(Theme.tertiary)
            }
        }
        .chartTapBubble(bubblePoints(data), tint: Self.fitnessColor)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fitness and fatigue chart, last \(days) days")
    }

    /// One bubble per day, at the fitness line: "Fitness 42 · Fatigue 55".
    private func bubblePoints(_ data: [LoadLinePoint]) -> [ChartPoint] {
        let fatigue = Dictionary(data.filter { !$0.fitness }.map { ($0.date, $0.value) }, uniquingKeysWith: { a, _ in a })
        return data.filter(\.fitness).map { p in
            .day(p.date, p.value, title: "Fitness \(Int(p.value.rounded())) · Fatigue \(fatigue[p.date].map { "\(Int($0.rounded()))" } ?? "–")")
        }
    }
}

/// Insights: the server's training load (stats.load). Fitness is the 42-day exponentially
/// weighted average of daily TRIMP and fatigue the 7-day one; form is fitness minus fatigue, and
/// its share of fitness sets the status. The acute:chronic ratio compares the last 7 days with
/// the last 28. Nothing is computed here beyond picking the last 90 days to draw.
struct TrainingLoadCard: View {
    let load: TrainingLoad?
    /// The day the stats were built for (stats.today).
    let today: String

    var body: some View {
        Card {
            SectionHeader(title: "Training load", subtitle: "From the heart-rate load (TRIMP) of each day, last 90 days")
            if let load, !load.series.isEmpty {
                if load.status == "calibrating" {
                    Label(TrainingLoadStatus.calibratingText(load, today: today), systemImage: "hourglass")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                }
                summary(load)
                TrainingLoadChart(series: load.series)
                legend
                acwr(load)
            } else {
                Text(emptyText)
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
            Text("Fresh: fitness above fatigue, you are rested. Neutral: the two roughly balance. Productive: fatigue above fitness, the normal state while training builds you up. Overreaching: fatigue far above fitness; ease off for a few days.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
            Text("Fitness is a 42-day weighted average of your daily load, fatigue a 7-day one, and form is fitness minus fatigue. Today is left out until it is over.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("training-load")
    }

    private var emptyText: String {
        if load == nil { return "Training load appears after the server's next statistics update. Pull down to refresh." }
        return "No training load yet. It builds from the heart rate your band records, once days with heart rate have synced."
    }

    private func summary(_ load: TrainingLoad) -> some View {
        let latest = load.latest
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Form").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                HStack(alignment: .center, spacing: 8) {
                    // 1 decimal, as sent: the server takes form from the rounded fitness and fatigue, so the three add up.
                    Text(Format.signed(latest?.form, decimals: 1))
                        .font(Font.fredoka(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    LoadStatusPill(status: load.status)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                valueRow("Fitness", latest?.ctl, color: TrainingLoadChart.fitnessColor)
                valueRow("Fatigue", latest?.atl, color: TrainingLoadChart.fatigueColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func valueRow(_ title: String, _ value: Double?, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            Text(Format.number(value, decimals: 1))
                .font(Font.fredoka(17, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Fitness (42 days)", TrainingLoadChart.fitnessColor)
            legendItem("Fatigue (7 days)", TrainingLoadChart.fatigueColor)
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(title).font(Font.fs(.caption2)).foregroundStyle(Theme.secondary)
        }
    }

    @ViewBuilder private func acwr(_ load: TrainingLoad) -> some View {
        let ratio = load.latest?.acwr
        Divider().overlay(Theme.track)
        KeyValueRow(key: "Acute:chronic ratio", value: ratio.map { Format.number($0, decimals: 2) } ?? "–",
                    color: load.spike ? Theme.recoveryRed : .white)
        if load.spike {
            Label("Load spike: your last 7 days averaged at least 1.5 times your last 28. Jumps like this are harder to recover from, so consider building up more gradually.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.recoveryRed)
        } else if ratio == nil {
            Text("The ratio needs a daily load on at least 21 of the last 28 days.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        } else {
            Text("Your last 7 days' average load divided by your last 28 days'. 1.5 or more counts as a spike.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
