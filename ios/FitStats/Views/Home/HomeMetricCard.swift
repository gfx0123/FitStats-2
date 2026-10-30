import SwiftUI

/// A Metric card at full size: the value, its change from the days before, the daily chart
/// with the average marked, and the average, lowest and highest of the period. Tapping opens
/// the metric's detail.
struct MetricLargeCard: View {
    let key: String
    let days: Int
    let date: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let def = MetricCatalog.def(key) ?? MetricCatalog.def("steps") {
            content(MetricSummary(def: def, model: model, date: date, days: days))
        }
    }

    @ViewBuilder private func content(_ m: MetricSummary) -> some View {
        let def = m.def
        let points = model.series(def, from: Format.addDays(date, -(days - 1)), through: date)
        NavigationLink(value: DetailRoute.metric(def.key)) {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: def.label, subtitle: "\(days) days ending \(Format.shortDay(date))")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Font.fs(.caption2, .semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                if let shown = m.shown {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        GlanceValue(value: def.formatted(shown.value, withUnit: false), unit: def.unit, size: 34)
                        DeltaBadge(change: m.change, better: def.better)
                        Spacer(minLength: 8)
                        Text(dayText(shown.day, def))
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.secondary)
                    }
                    if points.count > 1 {
                        DailyMetricChart(points: points, def: def, average: m.average, color: def.category.color, height: 180)
                    }
                    HStack(alignment: .top) {
                        GlanceStat(title: "Average", value: def.formatted(m.average), size: 17)
                        Spacer(minLength: 8)
                        GlanceStat(title: "Lowest", value: def.formatted(m.low), size: 17)
                        Spacer(minLength: 8)
                        GlanceStat(title: "Highest", value: def.formatted(m.high), size: 17)
                        Spacer(minLength: 8)
                        GlanceStat(title: "Days", value: "\(m.counted)", size: 17)
                    }
                    if def.isDayTotal && date >= model.today {
                        Text("Today's total is still growing, so it isn't in the chart or the average.")
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.tertiary)
                    }
                } else {
                    EmptyStateView(icon: def.icon, title: "No \(def.label.lowercased()) yet",
                                   message: "Nothing was recorded in the \(days) days ending \(Format.shortDay(date)).")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dayText(_ day: String, _ def: MetricDef) -> String {
        if day == date && def.isDayTotal && date >= model.today { return "So far today" }
        return Format.prettyDay(day, today: model.today)
    }
}
