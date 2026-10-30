import SwiftUI

private enum ComparePreset: String, CaseIterable, Identifiable {
    case week, month30, calendarMonth, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Last 7 days vs the 7 before"
        case .month30: return "Last 30 days vs the 30 before"
        case .calendarMonth: return "This month vs last month"
        case .custom: return "Custom"
        }
    }

    /// Fits a four-way segmented control.
    var shortTitle: String {
        switch self {
        case .week: return "7 days"
        case .month30: return "30 days"
        case .calendarMonth: return "Month"
        case .custom: return "Custom"
        }
    }
}

/// An inclusive range of calendar days.
private struct ComparePeriod {
    let from: String
    let to: String

    /// The same range whichever way round the ends were picked.
    init(_ a: String, _ b: String) {
        from = Swift.min(a, b)
        to = Swift.max(a, b)
    }

    var text: String {
        from == to ? Format.shortDay(from) : "\(Format.shortDay(from)) – \(Format.shortDay(to))"
    }
}

/// One metric over both periods.
private struct CompareRow: Identifiable {
    let def: MetricDef
    let a: [Double]
    let b: [Double]
    var id: String { def.key }

    var meanA: Double? { ComparePeriodsView.mean(a) }
    var meanB: Double? { ComparePeriodsView.mean(b) }

    /// Welch's t of 2 or more, with at least 3 days on each side (as the journal's tag effects).
    var clear: Bool {
        guard a.count >= 3, b.count >= 3, let t = ComparePeriodsView.welchT(a, b) else { return false }
        return abs(t) >= 2
    }
}

/// Trends: ten metrics' means over two periods side by side, with each side's day count and the
/// change: absolute for clock times (MetricDef.comparesAbsolute), otherwise a percentage. A
/// change is coloured only when it is clear (Welch's t of 2 or more with 3+ days per side); the
/// rest stay grey. Day totals go through model.countsToward, so today and low-wear days are left
/// out.
struct ComparePeriodsView: View {
    @EnvironmentObject var model: AppModel
    @State private var preset: ComparePreset = .month30
    @State private var aFrom = Date()
    @State private var aTo = Date()
    @State private var bFrom = Date()
    @State private var bTo = Date()
    @State private var customReady = false

    private static let keys = [
        "recovery", "sleep_score", "sleep_asleep_min", "hrv_rmssd", "rhr",
        "strain", "stress", "steps", "azm_total", "sleep_bedtime_min",
    ]

    /// DatePicker dates are local midnights (Format.chartDate), so they convert back in the device's zone.
    private static let localDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        let periods = currentPeriods()
        let rows = Self.keys.compactMap { key -> CompareRow? in
            guard let def = MetricCatalog.def(key) else { return nil }
            return CompareRow(def: def, a: values(def, periods[0]), b: values(def, periods[1]))
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Periods", selection: $preset) {
                    ForEach(ComparePreset.allCases) { p in
                        Text(p.shortTitle).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("compare-preset")

                Card {
                    SectionHeader(title: preset.title)
                    periodLine("A", periods[0], color: .white)
                    periodLine("B", periods[1], color: Theme.secondary)
                    if preset == .custom { customPickers }
                }

                Card {
                    HStack(spacing: 8) {
                        SectionHeader(title: "Averages")
                        Spacer()
                        Text("A vs B").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                        Text("change").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    ForEach(rows) { row in
                        CompareRowView(row: row)
                        if row.id != rows.last?.id { Divider().overlay(Theme.track) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("compare-periods")

                Text("Each side is the mean of its days with data. A change is coloured when it is larger than the day-to-day variation (Welch's t of 2 or more, with at least 3 days on each side); grey changes may be chance. Today and days you barely wore the band are left out of day totals such as steps.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Compare periods")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setUpCustom)
    }

    // MARK: periods

    /// Period A (the recent one) and period B.
    private func currentPeriods() -> [ComparePeriod] {
        let today = model.today
        switch preset {
        case .week:
            return [ComparePeriod(Format.addDays(today, -6), today), ComparePeriod(Format.addDays(today, -13), Format.addDays(today, -7))]
        case .month30:
            return [ComparePeriod(Format.addDays(today, -29), today), ComparePeriod(Format.addDays(today, -59), Format.addDays(today, -30))]
        case .calendarMonth:
            let firstOfMonth = String(today.prefix(8)) + "01"
            let lastOfPrevious = Format.addDays(firstOfMonth, -1)
            let firstOfPrevious = String(lastOfPrevious.prefix(8)) + "01"
            return [ComparePeriod(firstOfMonth, today), ComparePeriod(firstOfPrevious, lastOfPrevious)]
        case .custom:
            return [ComparePeriod(Self.ymd(aFrom), Self.ymd(aTo)), ComparePeriod(Self.ymd(bFrom), Self.ymd(bTo))]
        }
    }

    /// Custom starts as the last 14 days against the 14 before.
    private func setUpCustom() {
        guard !customReady else { return }
        customReady = true
        let today = model.today
        aFrom = Format.chartDate(Format.addDays(today, -13)) ?? Date()
        aTo = Format.chartDate(today) ?? Date()
        bFrom = Format.chartDate(Format.addDays(today, -27)) ?? Date()
        bTo = Format.chartDate(Format.addDays(today, -14)) ?? Date()
    }

    private static func ymd(_ date: Date) -> String { localDay.string(from: date) }

    private var latestDate: Date { Format.chartDate(model.today) ?? Date() }

    private var customPickers: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Theme.track)
            Text("Period A").font(Font.fs(.caption, .semibold)).foregroundStyle(Theme.secondary)
            DatePicker("From", selection: $aFrom, in: ...latestDate, displayedComponents: .date)
            DatePicker("To", selection: $aTo, in: ...latestDate, displayedComponents: .date)
            Text("Period B").font(Font.fs(.caption, .semibold)).foregroundStyle(Theme.secondary).padding(.top, 6)
            DatePicker("From", selection: $bFrom, in: ...latestDate, displayedComponents: .date)
            DatePicker("To", selection: $bTo, in: ...latestDate, displayedComponents: .date)
        }
        .font(Font.fs(.subheadline))
    }

    private func periodLine(_ name: String, _ period: ComparePeriod, color: Color) -> some View {
        let days = Format.daysBetween(period.from, period.to) + 1
        return HStack(spacing: 8) {
            Text(name)
                .font(Font.fs(.caption, .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Text(period.text).font(Font.fs(.subheadline)).foregroundStyle(color)
            Spacer()
            Text(days == 1 ? "1 day" : "\(days) days").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: data

    private func values(_ def: MetricDef, _ period: ComparePeriod) -> [Double] {
        model.days.compactMap { day -> Double? in
            guard day.date >= period.from, day.date <= period.to, model.countsToward(def, day) else { return nil }
            return def.value(day)
        }
    }

    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (n − 1), as the server's.
    static func sampleSD(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let squares = xs.reduce(0.0) { sum, x in sum + (x - m) * (x - m) }
        return (squares / Double(xs.count - 1)).squareRoot()
    }

    /// Welch's t, as the server's journal tag effects (lib/stats.ts welchT).
    static func welchT(_ a: [Double], _ b: [Double]) -> Double? {
        guard let ma = mean(a), let mb = mean(b) else { return nil }
        let va = pow(sampleSD(a) ?? 0, 2) / Double(a.count)
        let vb = pow(sampleSD(b) ?? 0, 2) / Double(b.count)
        let diff = ma - mb
        if va + vb == 0 { return diff == 0 ? 0 : nil }
        return diff / (va + vb).squareRoot()
    }
}

private struct CompareRowView: View {
    let row: CompareRow

    var body: some View {
        let def = row.def
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(def.shortLabel).font(Font.fs(.subheadline, .medium)).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(def.formatted(row.meanA)) vs \(def.formatted(row.meanB))")
                    .font(Font.fs(.caption).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(changeText ?? "–")
                    .font(Font.fs(.caption, .semibold).monospacedDigit())
                    .foregroundStyle(changeColor)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            Text("\(daysText(row.a.count)) vs \(daysText(row.b.count))")
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func daysText(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }

    /// meanA − meanB.
    private var diff: Double? {
        guard let a = row.meanA, let b = row.meanB else { return nil }
        return a - b
    }

    /// The change rounded as shown, so a rounded zero reads "±0" and is never coloured.
    private var shownChange: Double? {
        guard let d = diff, let b = row.meanB else { return nil }
        if row.def.comparesAbsolute {
            if row.def.format == .clock || row.def.format == .duration { return d.rounded() }
            let scale = pow(10, Double(row.def.decimals))
            return (d * scale).rounded() / scale
        }
        guard b != 0 else { return nil }
        return (d / abs(b) * 100).rounded()
    }

    private var changeText: String? {
        guard let change = shownChange else { return nil }
        let sign = change > 0 ? "+" : change < 0 ? "−" : "±"
        let size = abs(change)
        guard row.def.comparesAbsolute else { return "\(sign)\(Format.number(size))%" }
        switch row.def.format {
        case .clock:
            if change == 0 { return "±0m" }
            return "\(Format.duration(size)) \(change > 0 ? "later" : "earlier")"
        case .duration:
            return sign + Format.duration(size)
        case .number, .signed, .percent:
            let number = Format.number(size, decimals: row.def.decimals)
            return row.def.unit.isEmpty ? sign + number : "\(sign)\(number) \(row.def.unit)"
        }
    }

    /// Clear changes: green or red where higher or lower is better, white where neither is.
    private var changeColor: Color {
        guard row.clear, let change = shownChange, change != 0 else { return Theme.tertiary }
        guard let better = row.def.better else { return .white }
        return (better == .higher) == (change > 0) ? Theme.recoveryGreen : Theme.recoveryRed
    }

    private var spoken: String {
        let def = row.def
        let change = changeText.map { ", change \($0)" } ?? ""
        return "\(def.label): \(def.formatted(row.meanA)) over \(daysText(row.a.count)) against \(def.formatted(row.meanB)) over \(daysText(row.b.count))\(change), \(row.clear ? "clear" : "not clear") difference"
    }
}
