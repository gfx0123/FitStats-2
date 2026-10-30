import SwiftUI

/// Home: the 7 days ending on `date` against the 7 days before them, as daily averages of time
/// asleep, recovery, strain, steps and Active Zone Minutes (workouts only live in the day
/// details, so zone minutes stand in for training). Every value goes through
/// `model.countsToward`: today's still-growing day totals and low-wear days show faded in the
/// bars but are never averaged. Days without data stay empty (nothing is filled in), and two
/// weeks are only compared when each has at least `ThisWeekRow.minDays` counted days. Metrics
/// never recorded are hidden. Each row opens its detail.
struct ThisWeekCard: View {
    let date: String
    /// Metric keys to show (a Home card setting); nil shows the default five.
    var keys: [String]? = nil
    @EnvironmentObject var model: AppModel

    /// Seven slots of about 11pt with 3pt gaps: wide enough for a caption2 "W" in semibold.
    private static let barsWidth: CGFloat = 98
    private static let barSpacing: CGFloat = 3
    private static let barsHeight: CGFloat = 28
    private static let deltaWidth: CGFloat = 54

    private static let specs: [ThisWeekSpec] = [
        ThisWeekSpec(key: "sleep_asleep_min", tint: Theme.sleep),
        ThisWeekSpec(key: "recovery", tint: Theme.recoveryGreen, bandColors: true),
        ThisWeekSpec(key: "strain", tint: Theme.strainEnd),
        ThisWeekSpec(key: "steps", tint: Theme.strain),
        ThisWeekSpec(key: "azm_total", tint: Theme.heart),
    ]

    var body: some View {
        let current = Self.dates(endingOn: date)
        let previous = Self.dates(endingOn: Format.addDays(date, -7))
        let rows = buildRows(current: current, previous: previous)
        let hasData = rows.contains { $0.hasAnyData }
        Card {
            SectionHeader(title: "This week", subtitle: subtitle(current: current, previous: previous))
            if rows.isEmpty || !hasData {
                EmptyStateView(icon: "calendar", title: "No data yet", message: emptyMessage(previous: previous))
            } else {
                columnHeader(current)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider().overlay(Theme.cardBorder)
                        }
                        NavigationLink(value: row.route) {
                            rowView(row)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(rowSummary(row))
                        .accessibilityValue(spokenDays(row))
                        .accessibilityHint("Opens \(row.def.label.lowercased()) details")
                    }
                }
                if let note = footnote(current: current, previous: previous, rows: rows) {
                    Text(note)
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("this-week")
    }

    // MARK: sections

    private func columnHeader(_ current: [String]) -> some View {
        HStack(spacing: 10) {
            Text("Daily average")
            Spacer(minLength: 4)
            HStack(spacing: Self.barSpacing) {
                ForEach(current, id: \.self) { d in
                    Text(Format.weekdayLetter(d))
                        .fontWeight(d == date ? .semibold : .regular)
                        .foregroundStyle(d == date ? Color.white : Theme.tertiary)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: Self.barsWidth)
            Text("vs prev")
                .frame(minWidth: Self.deltaWidth, alignment: .trailing)
        }
        .font(Font.fs(.caption2))
        .foregroundStyle(Theme.tertiary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private func rowView(_ row: ThisWeekRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: row.def.icon)
                        .font(Font.fs(.caption2))
                        .foregroundStyle(row.tint)
                    Text(row.def.shortLabel)
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Text(row.current.value.map { row.def.formatted($0) } ?? "–")
                    .font(Font.fredoka(18, weight: .semibold))
                    .foregroundStyle(row.current.value == nil ? Theme.tertiary : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption(row))
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            ThisWeekBars(days: row.days, tint: row.tint, bandColors: row.bandColors,
                         scaleMax: row.scaleMax, height: Self.barsHeight, spacing: Self.barSpacing)
                .frame(width: Self.barsWidth, height: Self.barsHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.def.label) bar chart, 7 days ending \(Format.longDay(date))")
                .accessibilityValue(spokenDays(row))
            delta(row)
                .frame(minWidth: Self.deltaWidth, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func delta(_ row: ThisWeekRow) -> some View {
        if let change = row.change {
            if abs(change) >= 0.5 {
                DeltaBadge(change: change, better: row.def.better)
            } else {
                Text(verbatim: "≈ 0%")
                    .font(Font.fs(.caption2, .semibold))
                    .foregroundStyle(Theme.secondary)
            }
        } else {
            Text("–")
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: data

    /// The 7 days ending on `end`, oldest first.
    private static func dates(endingOn end: String) -> [String] {
        (0..<7).map { offset -> String in Format.addDays(end, offset - 6) }
    }

    /// The metrics picked in the card's Home settings, in their order, else the default five.
    private var shownSpecs: [ThisWeekSpec] {
        guard let keys, !keys.isEmpty else { return Self.specs }
        return keys.compactMap { key -> ThisWeekSpec? in
            if let spec = Self.specs.first(where: { $0.key == key }) { return spec }
            return MetricCatalog.def(key).map { ThisWeekSpec(key: key, tint: $0.category.color) }
        }
    }

    private func buildRows(current: [String], previous: [String]) -> [ThisWeekRow] {
        shownSpecs.compactMap { spec -> ThisWeekRow? in
            guard model.recorded.contains(spec.key), let def = MetricCatalog.def(spec.key) else { return nil }
            let days = current.map { d -> ThisWeekDay in dayValue(def, on: d) }
            let before = previous.map { d -> ThisWeekDay in dayValue(def, on: d) }
            return ThisWeekRow(def: def, route: route(spec.key), tint: spec.tint, bandColors: spec.bandColors,
                               days: days, current: ThisWeekAverage(days), previous: ThisWeekAverage(before))
        }
    }

    /// One day's value; `counted` is false when `model.countsToward` leaves it out of averages.
    private func dayValue(_ def: MetricDef, on d: String) -> ThisWeekDay {
        guard let day = model.daysByDate[d], let v = def.value(day), v.isFinite else {
            return ThisWeekDay(date: d, value: nil, counted: false, partial: false, lowWear: false)
        }
        let counts = model.countsToward(def, day)
        let partial = !counts && d >= model.today
        let lowWear = !counts && !partial && day.bool("low_wear") == true
        return ThisWeekDay(date: d, value: v, counted: counts, partial: partial, lowWear: lowWear)
    }

    private func route(_ key: String) -> DetailRoute {
        switch key {
        case "sleep_asleep_min": return .sleep(date)
        case "recovery": return .recovery(date)
        case "strain": return .strain(date)
        default: return .metric(key)
        }
    }

    // MARK: text

    private func subtitle(current: [String], previous: [String]) -> String {
        guard let cs = current.first, let ce = current.last, let ps = previous.first, let pe = previous.last else { return "" }
        return "Daily averages, \(Self.range(cs, ce)) vs \(Self.range(ps, pe))"
    }

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = Format.utc
        f.dateFormat = "MMM d"
        return f
    }()

    private static func monthDay(_ ymd: String) -> String {
        guard let d = Format.date(ymd) else { return ymd }
        return monthDayFormatter.string(from: d)
    }

    /// "Oct 12–18", or "Sep 29 – Oct 5" across a month boundary.
    private static func range(_ start: String, _ end: String) -> String {
        if start.prefix(7) == end.prefix(7) {
            return "\(monthDay(start))–\(Format.dayNumber(end))"
        }
        return "\(monthDay(start)) – \(monthDay(end))"
    }

    private func caption(_ row: ThisWeekRow) -> String {
        var parts: [String] = []
        if row.current.count == 0 {
            let anyValue = row.days.contains { $0.value != nil }
            parts.append(anyValue ? "No full day yet" : "No data yet")
        } else if row.current.count < 7 {
            parts.append("\(row.current.count) of 7 days")
        }
        if let p = row.previous.value {
            let prev = "prev \(row.def.formatted(p))"
            parts.append(row.previous.count < ThisWeekRow.minDays ? "\(prev) (\(daysText(row.previous.count)))" : prev)
        } else {
            parts.append("no prev data")
        }
        return parts.joined(separator: " · ")
    }

    /// Explains the faded bars and the days left out of the day-total averages.
    private func footnote(current: [String], previous: [String], rows: [ThisWeekRow]) -> String? {
        let names = rows.filter { $0.def.isDayTotal }.map { $0.def.shortLabel.lowercased() }
        guard !names.isEmpty else { return nil }
        var parts: [String] = []
        if current.contains(model.today) {
            parts.append("Today's \(Self.list(names)) are still growing: shown faded, not averaged.")
        }
        let lowWear = (previous + current).filter { d -> Bool in
            d < model.today && model.daysByDate[d]?.bool("low_wear") == true
        }.count
        if lowWear == 1 {
            parts.append("1 low-wear day is left out of the day totals.")
        } else if lowWear > 1 {
            parts.append("\(lowWear) low-wear days are left out of the day totals.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "a", "a and b", "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        if items.count == 1 { return last }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    private func daysText(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    private func emptyMessage(previous: [String]) -> String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        let start = previous.first ?? date
        return "Nothing recorded between \(Format.shortDay(start)) and \(Format.shortDay(date))."
    }

    // MARK: accessibility

    private func spoken(_ def: MetricDef, _ v: Double) -> String {
        if def.format == .duration {
            let total = Int(v.rounded())
            let hours = total / 60
            let minutes = total % 60
            if hours == 0 { return "\(minutes) minutes" }
            return minutes == 0 ? "\(hours) hours" : "\(hours) hours \(minutes) minutes"
        }
        let number = Format.number(v, decimals: def.decimals)
        if def.unit == "%" { return "\(number) percent" }
        if def.unit == "min" { return "\(number) minutes" }
        return def.formatted(v)
    }

    private func rowSummary(_ row: ThisWeekRow) -> String {
        var parts: [String] = [row.def.label]
        if let v = row.current.value {
            parts.append("Daily average \(spoken(row.def, v)) over \(daysText(row.current.count)), \(Self.range(row.days.first?.date ?? date, date))")
        } else {
            parts.append("No counted days this week")
        }
        if let p = row.previous.value {
            parts.append("Previous 7 days \(spoken(row.def, p)) over \(daysText(row.previous.count))")
        } else {
            parts.append("No data the previous 7 days")
        }
        if let change = row.change {
            if abs(change) < 0.5 {
                parts.append("About the same")
            } else {
                let direction = change > 0 ? "Up" : "Down"
                parts.append("\(direction) \(Format.number(abs(change))) percent")
            }
        } else if !row.comparable && row.current.count > 0 && row.previous.count > 0 {
            parts.append("Too few days to compare")
        }
        return parts.joined(separator: ". ")
    }

    private func spokenDays(_ row: ThisWeekRow) -> String {
        let items = row.days.map { d -> String in
            let day = Format.longDay(d.date)
            guard let v = d.value else { return "\(day), no data" }
            let value = spoken(row.def, v)
            if d.partial { return "\(day), \(value) so far, not averaged" }
            if d.lowWear { return "\(day), \(value), low wear, not averaged" }
            return "\(day), \(value)"
        }
        return items.joined(separator: ". ")
    }
}

// MARK: - Data

private struct ThisWeekSpec {
    let key: String
    let tint: Color
    var bandColors: Bool = false
}

private struct ThisWeekDay: Identifiable {
    let date: String
    let value: Double?
    /// False for a still-growing (today) or low-wear day total: shown faded, never averaged.
    let counted: Bool
    let partial: Bool
    let lowWear: Bool
    var id: String { date }
}

/// Mean of the counted days only (nil when none): missing days are never counted as zero.
private struct ThisWeekAverage {
    let value: Double?
    let count: Int

    init(_ days: [ThisWeekDay]) {
        let values = days.filter { $0.counted }.compactMap { $0.value }
        count = values.count
        value = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

private struct ThisWeekRow: Identifiable {
    /// Counted days each week needs before the two weeks are compared.
    static let minDays = 3

    let def: MetricDef
    let route: DetailRoute
    let tint: Color
    let bandColors: Bool
    let days: [ThisWeekDay]
    let current: ThisWeekAverage
    let previous: ThisWeekAverage

    var id: String { def.key }

    var hasAnyData: Bool {
        current.count > 0 || previous.count > 0 || days.contains { $0.value != nil }
    }

    var comparable: Bool { current.count >= Self.minDays && previous.count >= Self.minDays }

    /// Percent change of this week's average against the week before; nil without enough days.
    var change: Double? {
        guard comparable, let c = current.value, let p = previous.value, p != 0 else { return nil }
        return (c - p) / abs(p) * 100
    }

    /// Top of the bar scale: 100 for recovery, otherwise the week's highest value.
    var scaleMax: Double {
        if bandColors { return 100 }
        return days.compactMap { $0.value }.max() ?? 0
    }
}

// MARK: - Bars

/// Seven small bars, oldest first. Faded bars are days shown but not averaged (today's partial
/// totals, low-wear days); a flat dash is a day without data.
private struct ThisWeekBars: View {
    let days: [ThisWeekDay]
    let tint: Color
    let bandColors: Bool
    let scaleMax: Double
    let height: CGFloat
    /// Same gap as the weekday letters above, so each bar sits under its letter.
    let spacing: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(days) { day in
                bar(day)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder private func bar(_ day: ThisWeekDay) -> some View {
        if let v = day.value {
            let fraction = scaleMax > 0 ? min(1, max(0, v / scaleMax)) : 0
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color(v).opacity(day.counted ? 1 : 0.3))
                .frame(height: max(3, height * CGFloat(fraction)))
        } else {
            Capsule()
                .fill(Theme.track)
                .frame(height: 3)
        }
    }

    private func color(_ v: Double) -> Color {
        bandColors ? Theme.recoveryColor(v) : tint
    }
}
