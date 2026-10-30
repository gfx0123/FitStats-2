import SwiftUI

/// Home: the latest weight (`weight_kg`) and body fat (`body_fat_pct`) readings on or before
/// `date`, each labelled with the day it was measured, and a sparkline of every weigh-in in the
/// 90 days ending on `date`. Only real readings are shown: a metric you never recorded gets no
/// tile, one with no reading by `date` shows "–", and the sparkline needs two weigh-ins in the
/// window. Neither is a day total, but readings still go through `countsToward` like every
/// other compared value. Each tile opens that metric's detail.
struct BodyCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    private static let windowDays = 90
    private static let weightKey = "weight_kg"
    private static let fatKey = "body_fat_pct"

    var body: some View {
        let hasWeight = model.recorded.contains(Self.weightKey)
        let hasFat = model.recorded.contains(Self.fatKey)
        Card {
            SectionHeader(title: "Body", subtitle: hasWeight || hasFat ? subtitle : nil)
            if hasWeight || hasFat {
                HStack(spacing: 10) {
                    if hasWeight { tile(Self.weightKey) }
                    if hasFat { tile(Self.fatKey) }
                }
                if hasWeight { weightTrend }
            } else {
                emptyState
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("body-card")
    }

    // MARK: sections

    @ViewBuilder private func tile(_ key: String) -> some View {
        if let def = MetricCatalog.def(key) {
            let latest = latestReading(def)
            NavigationLink(value: DetailRoute.metric(key)) {
                MetricTile(
                    title: def.shortLabel,
                    shortTitle: def.compactLabel,
                    value: latest.map { def.formatted($0.value) } ?? "–",
                    sub: latest.map { dayLabel($0.day) } ?? "No reading yet",
                    icon: def.icon,
                    color: def.category.color
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenTile(def, latest))
            .accessibilityHint("Opens \(def.label.lowercased()) details")
        }
    }

    @ViewBuilder private var weightTrend: some View {
        if let def = MetricCatalog.def(Self.weightKey) {
            let points = trendReadings(def)
            if points.count >= 2, let first = points.first, let last = points.last {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Weight · \(Self.windowDays) days")
                        Spacer(minLength: 8)
                        Text(changeText(def, first: first, last: last))
                            .monospacedDigit()
                    }
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .accessibilityHidden(true)
                    SparklineView(values: points.map(\.value), color: Theme.body)
                        .frame(height: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Weight sparkline, \(Self.windowDays) days ending \(spokenLongDay(date))")
                        .accessibilityValue(spokenTrend(def, points))
                    Text(rangeText(def, points))
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityHidden(true)
                }
            } else {
                Text(sparseText(points.count))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emptyState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scalemass")
                .font(Font.fs(.title3))
                .foregroundStyle(Theme.tertiary)
                .accessibilityHidden(true)
            Text("No weigh-ins yet. A smart scale or weights logged in the Google Health app appear here.")
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: data

    /// A real reading for `day`, or nil (missing, not finite, zero or excluded).
    private func reading(_ def: MetricDef, _ day: DayRecord) -> Double? {
        guard model.countsToward(def, day), let v = def.value(day), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// The newest reading on or before `date`, however old.
    private func latestReading(_ def: MetricDef) -> BodyReading? {
        var newest: BodyReading? = nil
        for day in model.days where day.date <= date {
            if let current = newest, current.day >= day.date { continue }
            guard let v = reading(def, day) else { continue }
            newest = BodyReading(day: day.date, value: v)
        }
        return newest
    }

    /// Every reading in the 90 days ending on `date`, oldest first.
    private func trendReadings(_ def: MetricDef) -> [BodyReading] {
        let from = Format.addDays(date, -(Self.windowDays - 1))
        let inWindow = model.days.filter { $0.date >= from && $0.date <= date }
        let readings = inWindow.compactMap { day -> BodyReading? in
            guard let v = reading(def, day) else { return nil }
            return BodyReading(day: day.date, value: v)
        }
        return readings.sorted { $0.day < $1.day }
    }

    /// Rounded to the shown decimals, so the change always matches the numbers on screen.
    private func roundedTo(_ value: Double, places: Int) -> Double {
        let scales: [Double] = [1, 10, 100, 1000]
        let scale = scales[Swift.min(Swift.max(places, 0), scales.count - 1)]
        return (value * scale).rounded() / scale
    }

    // MARK: text

    private var subtitle: String {
        date == model.today ? "Latest weigh-ins" : "Latest weigh-ins up to \(Format.shortDay(date))"
    }

    /// "Today", "Yesterday", "Mon, Oct 12", with the year when it differs from `date`'s.
    private func dayLabel(_ day: String) -> String {
        let pretty = Format.prettyDay(day, today: model.today)
        if day == model.today || day == Format.addDays(model.today, -1) || day.prefix(4) == date.prefix(4) {
            return pretty
        }
        return "\(pretty), \(day.prefix(4))"
    }

    private func changeText(_ def: MetricDef, first: BodyReading, last: BodyReading) -> String {
        let change = roundedTo(last.value, places: def.decimals) - roundedTo(first.value, places: def.decimals)
        let since = dayLabel(first.day)
        if abs(change) < 0.05 { return "Unchanged since \(since)" }
        return "\(Format.signed(change, decimals: def.decimals)) \(def.unit) since \(since)"
    }

    private func rangeText(_ def: MetricDef, _ points: [BodyReading]) -> String {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        return "\(points.count) weigh-ins · low \(def.formatted(low, withUnit: false)) · high \(def.formatted(high))"
    }

    private func sparseText(_ count: Int) -> String {
        let window = "the \(Self.windowDays) days up to \(Format.shortDay(date))"
        if count == 0 { return "No weigh-ins in \(window), so no weight trend yet." }
        return "Only one weigh-in in \(window), so no weight trend yet."
    }

    // MARK: accessibility

    private func spokenLongDay(_ day: String) -> String {
        day.prefix(4) == date.prefix(4) ? Format.longDay(day) : "\(Format.longDay(day)), \(day.prefix(4))"
    }

    private func spokenDay(_ day: String) -> String {
        if day == model.today { return "today" }
        if day == Format.addDays(model.today, -1) { return "yesterday" }
        return "on \(spokenLongDay(day))"
    }

    private func spokenTile(_ def: MetricDef, _ latest: BodyReading?) -> String {
        guard let latest else { return "\(def.label), no reading yet" }
        return "\(def.label), \(def.formatted(latest.value)), measured \(spokenDay(latest.day))"
    }

    private func spokenTrend(_ def: MetricDef, _ points: [BodyReading]) -> String {
        guard let first = points.first, let last = points.last,
              let low = points.min(by: { $0.value < $1.value }),
              let high = points.max(by: { $0.value < $1.value }) else { return "No weigh-ins" }
        let count = "\(points.count) weigh-ins."
        let from = "From \(def.formatted(first.value)) on \(spokenLongDay(first.day))"
        let to = "to \(def.formatted(last.value)) on \(spokenLongDay(last.day))."
        let lowest = "Lowest \(def.formatted(low.value)) on \(spokenLongDay(low.day)),"
        let highest = "highest \(def.formatted(high.value)) on \(spokenLongDay(high.day))."
        return [count, from, to, lowest, highest].joined(separator: " ")
    }
}

private struct BodyReading: Identifiable {
    let day: String
    let value: Double
    var id: String { day }
}
