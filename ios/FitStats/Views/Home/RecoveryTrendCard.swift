import Charts
import SwiftUI

/// Home: recovery for the `days` days (14 by default) ending on `date`, one bar per day colored by recovery band,
/// with the average of the scored days. Days without a score stay empty (nothing is filled in).
/// Tapping opens the recovery detail.
struct RecoveryTrendCard: View {
    let date: String
    /// How many days the card covers (a Home card setting).
    var days = 14
    @EnvironmentObject var model: AppModel

    var body: some View {
        let trend = trendDays()
        let points = trend.compactMap { d -> RecoveryTrendPoint? in
            guard let v = d.value else { return nil }
            return RecoveryTrendPoint(date: d.date, value: v)
        }
        let average = mean(points)
        NavigationLink(value: DetailRoute.recovery(date)) {
            Card {
                header(trend)
                if points.isEmpty {
                    EmptyStateView(icon: "bolt.heart", title: "No recovery yet", message: emptyMessage)
                } else {
                    summary(average: average, count: points.count, total: trend.count)
                    chart(trend, points: points, average: average)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary(average: average, count: points.count, total: trend.count))
        .accessibilityValue(points.isEmpty ? "" : spokenDays(trend))
        .accessibilityHint("Opens recovery details")
        .accessibilityIdentifier("recovery-trend")
    }

    // MARK: sections

    private func header(_ trend: [RecoveryTrendDay]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title: "Recovery trend", subtitle: rangeText(trend))
            Spacer()
            Image(systemName: "chevron.right")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private func summary(average: Double?, count: Int, total: Int) -> some View {
        let latest = recovery(on: date)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Format.number(average))
                        .font(Font.fredoka(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("%")
                        .font(Font.fredoka(16, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                }
                Text(averageCaption(count: count, total: total))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(latest.map { "\(Format.number($0))%" } ?? "–")
                    .font(Font.fredoka(20, weight: .semibold))
                    .foregroundStyle(Theme.recoveryColor(latest))
                    .lineLimit(1)
                Text(Format.prettyDay(date, today: model.today))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private func chart(_ trend: [RecoveryTrendDay], points: [RecoveryTrendPoint], average: Double?) -> some View {
        let dates = trend.map(\.date)
        let selected = date
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Day", p.date), y: .value("Recovery", p.value), width: .ratio(0.62))
                    .foregroundStyle(Theme.recoveryColor(p.value).gradient)
                    .cornerRadius(3)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: dates)
        .chartYScale(domain: 0.0...100.0)
        .chartXAxis {
            AxisMarks(values: dates) { value in
                AxisValueLabel {
                    if let d = value.as(String.self) {
                        Text(Format.weekdayLetter(d))
                            .fontWeight(d == selected ? .semibold : .regular)
                            .foregroundStyle(d == selected ? Color.white : Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0.0, 50.0, 100.0]) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().foregroundStyle(Theme.tertiary)
            }
        }
        .chartTapBubble(points.map { p in
            ChartPoint(x: p.date, y: p.value, title: "Recovery \(Format.number(p.value))%", subtitle: Format.longDay(p.date))
        }, tint: Theme.recoveryGreen)
        .frame(height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery bar chart, \(days) days ending \(Format.longDay(date))")
        .accessibilityValue(spokenDays(trend))
    }

    // MARK: data

    /// The `days` days ending on `date`, oldest first; `value` is nil for a day without a score.
    private func trendDays() -> [RecoveryTrendDay] {
        (0..<days).reversed().map { offset -> RecoveryTrendDay in
            let d = Format.addDays(date, -offset)
            return RecoveryTrendDay(date: d, value: recovery(on: d))
        }
    }

    /// Recovery is a morning score, not a growing day total, but it still goes through
    /// `countsToward` like every other averaged value.
    private func recovery(on d: String) -> Double? {
        guard let def = MetricCatalog.def("recovery"), let day = model.daysByDate[d],
              model.countsToward(def, day) else { return nil }
        return def.value(day)
    }

    /// Mean of the scored days only (nil when none): missing days are never counted as zero.
    private func mean(_ points: [RecoveryTrendPoint]) -> Double? {
        guard !points.isEmpty else { return nil }
        let total = points.reduce(0.0) { sum, p in sum + p.value }
        return total / Double(points.count)
    }

    private func rangeText(_ trend: [RecoveryTrendDay]) -> String? {
        guard let first = trend.first?.date else { return nil }
        return "\(Format.shortDay(first)) – \(Format.shortDay(date))"
    }

    private func averageCaption(count: Int, total: Int) -> String {
        if count >= total { return "\(total)-day average" }
        return count == 1 ? "Average of 1 scored day" : "Average of \(count) scored days"
    }

    private var emptyMessage: String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        return "No recovery score in the \(days) days ending \(Format.shortDay(date)). Recovery needs at least 5 nights of HRV or resting heart rate to build your personal baseline."
    }

    // MARK: accessibility

    private func accessibilitySummary(average: Double?, count: Int, total: Int) -> String {
        var parts = ["Recovery trend, \(days) days ending \(Format.longDay(date))"]
        guard let average else {
            parts.append("No recovery score yet")
            return parts.joined(separator: ". ")
        }
        let scored = count >= total ? "all \(total) days" : (count == 1 ? "1 scored day" : "\(count) scored days")
        parts.append("Average \(Format.number(average)) percent over \(scored)")
        let latest = recovery(on: date)
        let day = Format.prettyDay(date, today: model.today)
        parts.append(latest.map { "\(day): \(Format.number($0)) percent, \(Theme.recoveryLabel($0))" } ?? "\(day): no score")
        return parts.joined(separator: ". ")
    }

    private func spokenDays(_ trend: [RecoveryTrendDay]) -> String {
        trend.map { d -> String in
            let value = d.value.map { "\(Format.number($0)) percent" } ?? "no score"
            return "\(Format.longDay(d.date)), \(value)"
        }
        .joined(separator: ". ")
    }
}

private struct RecoveryTrendDay: Identifiable {
    let date: String
    let value: Double?
    var id: String { date }
}

private struct RecoveryTrendPoint: Identifiable {
    let date: String
    let value: Double
    var id: String { date }
}
