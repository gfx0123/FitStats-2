import SwiftUI

/// A metric the calendar can show.
private enum HeatmapMetric: String, CaseIterable, Identifiable {
    case recovery, sleepScore, strain, stress, steps

    var id: String { rawValue }

    var key: String {
        switch self {
        case .recovery: return "recovery"
        case .sleepScore: return "sleep_score"
        case .strain: return "strain"
        case .stress: return "stress"
        case .steps: return "steps"
        }
    }

    /// Fits a five-way segmented control.
    var shortTitle: String {
        switch self {
        case .recovery: return "Recovery"
        case .sleepScore: return "Sleep"
        case .strain: return "Strain"
        case .stress: return "Stress"
        case .steps: return "Steps"
        }
    }

    var def: MetricDef { MetricCatalog.def(key)! }

    /// The colour the rest of the app uses for this metric.
    var color: Color {
        switch self {
        case .recovery: return Theme.recoveryGreen
        case .sleepScore: return Theme.sleep
        case .strain: return Theme.strain
        case .stress: return Theme.stress
        case .steps: return MetricCategory.activity.color
        }
    }

    func route(_ date: String) -> DetailRoute {
        switch self {
        case .recovery: return .recovery(date)
        case .sleepScore: return .sleep(date)
        case .strain: return .strain(date)
        case .stress: return .stress(date)
        case .steps: return .metric("steps")
        }
    }
}

private struct HeatmapDay: Identifiable {
    let date: String
    let value: Double?
    /// False for day totals that are still growing (today) or incomplete (low wear).
    let counts: Bool
    /// Between the first data day and today.
    let inRange: Bool
    var id: String { date }
}

private struct HeatmapWeek: Identifiable {
    /// Column position, oldest first.
    let index: Int
    let monday: String
    let days: [HeatmapDay]
    var id: String { monday }
}

/// Recovery's own bands, or four shades of the metric's colour cut at your quartiles.
private struct HeatmapScale {
    let metric: HeatmapMetric
    /// 25th, 50th and 75th percentiles of the counted values; nil with fewer than 4 values.
    let quartiles: [Double]?

    static let opacities: [Double] = [0.28, 0.5, 0.75, 1]

    init(metric: HeatmapMetric, values: [Double]) {
        self.metric = metric
        let sorted = values.sorted()
        quartiles = sorted.count >= 4 ? [0.25, 0.5, 0.75].map { Self.percentile(sorted, $0) } : nil
    }

    /// Linear interpolation between the closest ranks.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    func level(_ v: Double) -> Int {
        guard let q = quartiles else { return 2 }
        if v <= q[0] { return 0 }
        if v <= q[1] { return 1 }
        if v <= q[2] { return 2 }
        return 3
    }

    func color(_ v: Double) -> Color {
        if metric == .recovery { return Theme.recoveryColor(v) }
        return metric.color.opacity(Self.opacities[level(v)])
    }
}

/// Trends: one metric as a calendar, a column per week (Monday first) from the first day with
/// data, at most 53 weeks back, scrolled to the latest week. Recovery uses its green, yellow and
/// red bands (67 and 34); the other metrics use four shades of the metric's colour cut at your
/// own quartiles. Day totals that don't count yet (today, low-wear days; model.countsToward) are
/// drawn hollow and stay out of the quartiles. Tapping a day opens its detail.
struct CalendarHeatmapView: View {
    @EnvironmentObject var model: AppModel
    @State private var metric: HeatmapMetric = .recovery
    /// The card's inner width, for sizing the cells.
    @State private var gridWidth: CGFloat = 0

    private static let minCell: CGFloat = 16
    private static let maxCell: CGFloat = 30
    private static let gap: CGFloat = 3
    private static let monthRow: CGFloat = 14

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = Format.utc
        f.dateFormat = "MMM"
        return f
    }()

    var body: some View {
        let def = metric.def
        let weeks = buildWeeks(def)
        let counted = weeks.flatMap(\.days).filter { $0.counts }.compactMap(\.value)
        let scale = HeatmapScale(metric: metric, values: counted)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Metric", selection: $metric) {
                    ForEach(HeatmapMetric.allCases) { m in
                        Text(m.shortTitle).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                Card {
                    SectionHeader(title: def.label, subtitle: subtitle(weeks, counted: counted.count))
                    if weeks.isEmpty {
                        Text("No data yet. The calendar fills in after the first sync.")
                            .font(Font.fs(.footnote))
                            .foregroundStyle(Theme.secondary)
                    } else {
                        grid(weeks, scale: scale, cell: Self.cellSize(width: gridWidth, weeks: weeks.count))
                            .background {
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear { gridWidth = geo.size.width }
                                        .onChange(of: geo.size.width) { _, w in gridWidth = w }
                                }
                            }
                        legend(scale)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar-heatmap")

                Text(footnote(def))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: grid

    /// With a few months of data the cells grow to fill the card (up to 30 points); with more
    /// than 16 weeks they stay at 16 and the grid scrolls.
    static func cellSize(width: CGFloat, weeks: Int) -> CGFloat {
        guard width > 0, weeks > 0 else { return minCell }
        let columns = CGFloat(min(weeks, 16))
        let room = width - 10 - 6 - 24 // the weekday letters, their gap, the last month label
        return min(maxCell, max(minCell, ((room - gap * (columns - 1)) / columns).rounded(.down)))
    }

    private func grid(_ weeks: [HeatmapWeek], scale: HeatmapScale, cell size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            weekdayLabels(size)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Self.gap) {
                        ForEach(weeks) { week in
                            column(week, weeks: weeks, scale: scale, size: size)
                        }
                    }
                    .padding(.trailing, 24) // room for a month label in the last column
                }
                .onAppear {
                    guard let last = weeks.last?.id else { return }
                    DispatchQueue.main.async { proxy.scrollTo(last, anchor: .trailing) }
                }
            }
        }
    }

    private func weekdayLabels(_ size: CGFloat) -> some View {
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        return VStack(alignment: .leading, spacing: Self.gap) {
            Color.clear.frame(width: 10, height: Self.monthRow)
            ForEach(0..<7, id: \.self) { i in
                Text(letters[i])
                    .font(Font.fredoka(9, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: 10, height: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func column(_ week: HeatmapWeek, weeks: [HeatmapWeek], scale: HeatmapScale, size: CGFloat) -> some View {
        VStack(spacing: Self.gap) {
            Color.clear
                .frame(width: size, height: Self.monthRow)
                .overlay(alignment: .leading) {
                    if let month = monthLabel(week, weeks: weeks) {
                        Text(month)
                            .font(Font.fs(.caption2))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize()
                    }
                }
            ForEach(week.days) { day in
                cell(day, scale: scale, size: size)
            }
        }
        .id(week.id)
    }

    @ViewBuilder private func cell(_ day: HeatmapDay, scale: HeatmapScale, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        if !day.inRange {
            Color.clear.frame(width: size, height: size)
        } else if let value = day.value {
            NavigationLink(value: metric.route(day.date)) {
                Group {
                    if day.counts {
                        shape.fill(scale.color(value))
                    } else {
                        shape.strokeBorder(metric.color.opacity(0.8), lineWidth: 1.5)
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken(day, value: value))
        } else {
            shape.fill(Theme.track)
                .frame(width: size, height: size)
                .accessibilityLabel("\(Format.longDay(day.date)): no data")
        }
    }

    /// The month that starts in this week; the first column names its own month unless the next
    /// week starts one (the two labels would overlap).
    private func monthLabel(_ week: HeatmapWeek, weeks: [HeatmapWeek]) -> String? {
        if let first = week.days.first(where: { $0.date.hasSuffix("-01") }) { return monthName(first.date) }
        guard week.index == 0 else { return nil }
        if weeks.count > 1, weeks[1].days.contains(where: { $0.date.hasSuffix("-01") }) { return nil }
        return week.days.first(where: { $0.inRange }).map { monthName($0.date) }
    }

    private func monthName(_ ymd: String) -> String {
        guard let d = Format.date(ymd) else { return "" }
        return Self.monthFormatter.string(from: d)
    }

    // MARK: legend & text

    @ViewBuilder private func legend(_ scale: HeatmapScale) -> some View {
        let def = metric.def
        FlowLayout(spacing: 10) {
            if metric == .recovery {
                swatch(Theme.recoveryRed, "0–33")
                swatch(Theme.recoveryYellow, "34–66")
                swatch(Theme.recoveryGreen, "67–100")
            } else {
                HStack(spacing: 3) {
                    Text("Less").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                    ForEach(0..<HeatmapScale.opacities.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(metric.color.opacity(HeatmapScale.opacities[i]))
                            .frame(width: 12, height: 12)
                    }
                    Text("More").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                }
            }
            swatch(Theme.track, "No data")
            if def.isDayTotal {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(metric.color.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text("Not counted").font(Font.fs(.caption2)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        if metric != .recovery, let q = scale.quartiles {
            Text("Shades split at your quartiles: \(def.formatted(q[0])), \(def.formatted(q[1])) and \(def.formatted(q[2])).")
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func swatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 12, height: 12)
            Text(label).font(Font.fs(.caption2)).foregroundStyle(Theme.secondary)
        }
    }

    private func subtitle(_ weeks: [HeatmapWeek], counted: Int) -> String? {
        guard let first = weeks.first?.days.first(where: { $0.inRange })?.date else { return nil }
        return "\(counted == 1 ? "1 day" : "\(counted) days") with a value since \(Format.shortDay(first))"
    }

    private func footnote(_ def: MetricDef) -> String {
        var text = "Weeks run Monday to Sunday. Tap a day for its details."
        if def.isDayTotal {
            text += " Today and days you barely wore the band are hollow: their totals are incomplete, so they stay out of the shading."
        }
        return text
    }

    private func spoken(_ day: HeatmapDay, value: Double) -> String {
        let def = metric.def
        return "\(Format.longDay(day.date)): \(def.formatted(value))\(day.counts ? "" : ", not counted yet")"
    }

    // MARK: data

    /// Week columns from the Monday of the first data day (at most 52 weeks before this week's
    /// Monday) through this week. Days outside the data range stay blank.
    private func buildWeeks(_ def: MetricDef) -> [HeatmapWeek] {
        guard let first = model.days.map(\.date).min() else { return [] }
        let today = model.today
        let thisMonday = Self.monday(of: today)
        let start = Swift.max(Self.monday(of: first), Format.addDays(thisMonday, -52 * 7))
        var weeks: [HeatmapWeek] = []
        var monday = start
        while monday <= thisMonday {
            let days = (0..<7).map { i -> HeatmapDay in
                let date = Format.addDays(monday, i)
                let inRange = date >= first && date <= today
                let record = inRange ? model.daysByDate[date] : nil
                return HeatmapDay(
                    date: date,
                    value: record.flatMap { def.value($0) },
                    counts: record.map { model.countsToward(def, $0) } ?? false,
                    inRange: inRange
                )
            }
            weeks.append(HeatmapWeek(index: weeks.count, monday: monday, days: days))
            monday = Format.addDays(monday, 7)
        }
        return weeks
    }

    private static func monday(of ymd: String) -> String {
        guard let d = Format.date(ymd) else { return ymd }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Format.utc
        let weekday = cal.component(.weekday, from: d) // 1 = Sunday
        return Format.addDays(ymd, -((weekday + 5) % 7))
    }
}
