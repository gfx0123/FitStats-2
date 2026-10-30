import SwiftUI

// Small and medium Home cards: the headline numbers of each card at a fixed height, like iOS
// widgets. Large is the full card (HomeLargeCard). A glance reads the same data the full card
// does and never fills in a missing value. Tapping opens the card's detail screen, or the full
// card when it has none.

enum HomeGlanceMetrics {
    /// Height of a small or medium card at the default text size; a large one is as tall as its
    /// content.
    static let height: CGFloat = 170

    /// Small and medium cards grow with the iPhone's text size, so bigger text isn't cut off.
    /// Home caps text at `largestTextSize`, where a card is about 1.6 times as tall.
    static func height(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall, .small, .medium, .large: return height
        case .xLarge: return 186
        case .xxLarge: return 202
        case .xxxLarge: return 222
        default: return 270
        }
    }

    static let largestTextSize = DynamicTypeSize.accessibility1
}

/// Picks the small or medium version of a card.
struct HomeGlance: View {
    let spec: HomeCardSpec
    let size: CardSize
    let date: String

    var body: some View {
        switch spec.card {
        case .scores: ScoresGlance(date: date, size: size)
        case .tonight: TonightGlance(date: date, size: size)
        case .journal: JournalGlance(date: date, size: size)
        case .vitals: VitalsGlance(date: date, size: size, chosen: spec.options.metrics)
        case .activity: ActivityGlance(date: date, size: size, chosen: spec.options.metrics)
        case .heartRate: HeartRateGlance(date: date, size: size)
        case .workouts: WorkoutsGlance(date: date, size: size)
        case .lastNight: LastNightGlance(date: date, size: size)
        case .recoveryTrend: RecoveryTrendGlance(date: date, size: size, days: spec.days)
        case .hrvTrend:
            MetricTrendGlance(key: "hrv_rmssd", title: "HRV", icon: "waveform.path.ecg", tint: Theme.heart, date: date, size: size, days: spec.days)
        case .restingHrTrend:
            MetricTrendGlance(key: "rhr", title: "Resting HR", icon: "heart.text.square", tint: Theme.heart, date: date, size: size, days: spec.days)
        case .stressDay: StressGlance(date: date, size: size)
        case .thisWeek: ThisWeekGlance(date: date, size: size, chosen: spec.options.metrics)
        case .weeklyZoneMinutes: ZoneMinutesGlance(date: date, size: size)
        case .streaks: StreaksGlance(date: date, size: size)
        case .topInsight: InsightGlance(date: date, size: size)
        case .coachBrief: CoachGlance(date: date, size: size)
        case .body: BodyGlance(date: date, size: size)
        case .trainingLoad: LoadGlance(date: date, size: size)
        case .liveHeartRate: LiveHeartRateGlance(size: size)
        case .metric: MetricGlance(key: spec.metricKey, days: spec.days, date: date, size: size)
        case .stack: SmartStackView(entries: spec.options.stack ?? [], size: size, date: date, rotate: spec.options.rotate ?? true)
        }
    }
}

// MARK: - Building blocks

/// The card look at the glance height. Content that doesn't fit is clipped, never squeezed
/// into the next card.
struct GlanceFrame<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content
    /// Drawn inside a Home card's resize frame, which has the background already.
    @Environment(\.homeCardBare) private var bare
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: HomeGlanceMetrics.height(for: typeSize))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background { if !bare { Glass(cornerRadius: 22) } }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(bare ? Color.clear : Theme.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Opens `route` when there is one; otherwise just the content.
struct GlanceLink<Content: View>: View {
    let route: DetailRoute?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let route {
            NavigationLink(value: route) { content() }
                .buttonStyle(.plain)
        } else {
            content()
        }
    }
}

/// Icon, title and an optional note on the right. When they don't all fit (a small card), the
/// note gets shorter or goes, so the title is never cut off.
struct GlanceHeader: View {
    let title: String
    let icon: String
    let tint: Color
    var trailing: String? = nil
    var shortTrailing: String? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(trailing, fixed: true)
            if let shortTrailing { row(shortTrailing, fixed: true) }
            row(nil, fixed: false)
        }
    }

    private func row(_ note: String?, fixed: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(Font.fs(.caption2, .bold))
                .foregroundStyle(tint)
            Text(title.uppercased())
                .font(Font.fs(.caption2, .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(fixed ? 1 : 0.8)
                .fixedSize(horizontal: fixed, vertical: false)
            Spacer(minLength: 4)
            if let note {
                Text(note)
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

struct GlanceValue: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 30
    var color: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(Font.fredoka(size))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit, !unit.isEmpty {
                Text(unit)
                    .font(Font.fredoka(max(11, size * 0.42), weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct GlanceStat: View {
    let title: String
    /// Used when the title doesn't fit.
    var shortTitle: String? = nil
    let value: String
    var color: Color = .white
    var size: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FittingText(title, short: shortTitle ?? title)
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.secondary)
            Text(value)
                .font(Font.fredoka(size))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// An empty state that fits a glance.
struct GlanceMessage: View {
    var icon: String? = nil
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            if let icon {
                Image(systemName: icon)
                    .font(Font.fs(.title3))
                    .foregroundStyle(Theme.tertiary)
            }
            Text(text)
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An up or down arrow, green when the change is good and red when it's bad (DeltaBadge
/// without the number, for tight rows). Changes under half a percent show nothing.
struct TrendArrow: View {
    let change: Double?
    let better: Better?

    var body: some View {
        ZStack {
            if let change, change.isFinite, abs(change) >= 0.5 {
                Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(Font.fs(.caption2, .bold))
                    .foregroundStyle(color(up: change > 0))
            }
        }
        .frame(width: 12, height: 12)
    }

    private func color(up: Bool) -> Color {
        guard let better else { return Theme.secondary }
        return (better == .higher) == up ? Theme.recoveryGreen : Theme.recoveryRed
    }
}

/// A small line chart. Missing values break the line (nothing is drawn across a gap), and an
/// optional dashed line marks a baseline.
struct MiniLine: View {
    let values: [Double?]
    let color: Color
    var baseline: Double? = nil
    /// The y range; nil fits the values (and the baseline).
    var range: ClosedRange<Double>? = nil
    var fill = true

    var body: some View {
        GeometryReader { geo in
            let segs = segments(in: geo.size)
            ZStack(alignment: .topLeading) {
                if fill {
                    area(segs, height: geo.size.height)
                        .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                }
                if let y = yPosition(baseline, height: geo.size.height) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Theme.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                line(segs)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let last = segs.last?.last {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var bounds: ClosedRange<Double>? {
        if let range { return range }
        var all = values.compactMap { $0 }.filter(\.isFinite)
        if let baseline, baseline.isFinite { all.append(baseline) }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        let pad = max((hi - lo) * 0.12, 1)
        return (lo - pad)...(hi + pad)
    }

    private func yPosition(_ value: Double?, height: CGFloat) -> CGFloat? {
        guard let value, value.isFinite, let b = bounds, b.upperBound > b.lowerBound else { return nil }
        let t = (value - b.lowerBound) / (b.upperBound - b.lowerBound)
        return height * CGFloat(1 - min(1, max(0, t)))
    }

    private func segments(in size: CGSize) -> [[CGPoint]] {
        let count = values.count
        guard count > 0 else { return [] }
        let step = count > 1 ? size.width / CGFloat(count - 1) : 0
        var out: [[CGPoint]] = []
        var current: [CGPoint] = []
        for (index, value) in values.enumerated() {
            if let y = yPosition(value, height: size.height) {
                let x = count > 1 ? CGFloat(index) * step : size.width / 2
                current.append(CGPoint(x: x, y: y))
            } else if !current.isEmpty {
                out.append(current)
                current = []
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private func line(_ segs: [[CGPoint]]) -> Path {
        Path { p in
            for seg in segs {
                guard let first = seg.first else { continue }
                if seg.count == 1 {
                    p.addEllipse(in: CGRect(x: first.x - 1.5, y: first.y - 1.5, width: 3, height: 3))
                } else {
                    p.move(to: first)
                    for point in seg.dropFirst() { p.addLine(to: point) }
                }
            }
        }
    }

    private func area(_ segs: [[CGPoint]], height: CGFloat) -> Path {
        Path { p in
            for seg in segs where seg.count > 1 {
                p.move(to: CGPoint(x: seg[0].x, y: height))
                for point in seg { p.addLine(to: point) }
                p.addLine(to: CGPoint(x: seg[seg.count - 1].x, y: height))
                p.closeSubpath()
            }
        }
    }
}

/// Small bars, one per value. A missing value is a flat grey stub (never a zero bar).
struct MiniBars: View {
    let values: [Double?]
    var maxValue: Double? = nil
    var labels: [String]? = nil
    var color: (Double) -> Color

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let top = maxValue ?? max(values.compactMap { $0 }.max() ?? 1, 1)
                let count = max(values.count, 1)
                let gap: CGFloat = count > 16 ? 2 : 4
                let width = max(1, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        if let value, value.isFinite {
                            RoundedRectangle(cornerRadius: min(3, width / 2), style: .continuous)
                                .fill(color(value))
                                .frame(width: width, height: max(3, geo.size.height * CGFloat(min(1, max(0, value / top)))))
                        } else {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Theme.track)
                                .frame(width: width, height: 3)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            }
            if let labels {
                HStack(spacing: 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        Text(label)
                            .font(Font.fredoka(9, weight: .semibold))
                            .foregroundStyle(Theme.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct GlanceStage: Identifiable {
    let name: String
    let color: Color
    let minutes: Double
    var id: String { name }
}

/// The night split by stage, widths proportional to minutes.
struct MiniStageBar: View {
    let parts: [GlanceStage]

    var body: some View {
        let visible = parts.filter { $0.minutes > 0 }
        let total = visible.reduce(0.0) { $0 + $1.minutes }
        GeometryReader { geo in
            let usable = max(0, geo.size.width - CGFloat(max(0, visible.count - 1)) * 2)
            HStack(spacing: 2) {
                ForEach(visible) { part in
                    Rectangle()
                        .fill(part.color.gradient)
                        .frame(width: total > 0 ? usable * CGFloat(part.minutes / total) : 0)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// Percent change of `value` from `base`, nil when either is missing or the base is zero.
private func glanceChange(_ value: Double?, _ base: Double?) -> Double? {
    guard let value, let base, base != 0, value.isFinite, base.isFinite else { return nil }
    return (value - base) / abs(base) * 100
}

/// The `count` dates ending on `end`, oldest first.
private func glanceDates(_ count: Int, endingOn end: String) -> [String] {
    (0..<count).reversed().map { Format.addDays(end, -$0) }
}

// MARK: - Cards

struct ScoresGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let recovery = day?.double("recovery")
        if size == .small {
            GlanceLink(route: .recovery(date)) {
                GlanceFrame {
                    GlanceHeader(title: "Recovery", icon: "bolt.heart.fill", tint: Theme.recoveryColor(recovery))
                    HStack {
                        Spacer(minLength: 0)
                        RingGauge(progress: (recovery ?? 0) / 100, color: Theme.recoveryColor(recovery), lineWidth: 10) {
                            Text(recovery.map { "\(Format.number($0))%" } ?? "–")
                                .font(Font.fredoka(24))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(10)
                        }
                        .frame(width: 86, height: 86)
                        Spacer(minLength: 0)
                    }
                    Text(recoveryCaption(day))
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
            }
        } else {
            let stress = day?.double("stress")
            let target = strainTarget(day)
            GlanceFrame {
                GlanceHeader(title: "Scores", icon: "circle.circle", tint: Theme.recoveryGreen)
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 4) {
                    ring(.recovery(date), "Recovery", recovery, Theme.recoveryColor(recovery), nil, recoveryCaption(day), suffix: "%")
                    ring(.strain(date), "Strain", day?.double("strain"), Theme.strain, Theme.strainEnd,
                         target.map { "Goal \(Int($0.lowerBound))–\(Int($0.upperBound))" }, target: target)
                    ring(.sleep(date), "Sleep", day?.double("sleep_score"), Theme.sleep, nil, Format.duration(day?.double("sleep_asleep_min")))
                    ring(.stress(date), "Stress", stress, Theme.stressColor(stress), nil, Theme.stressLabel(stress))
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func recoveryCaption(_ day: DayRecord?) -> String {
        if let recovery = day?.double("recovery") { return Theme.recoveryLabel(recovery) }
        return ScoreBreakdown(day?.json("score_details")?["recovery"]).status == "calibrating" ? "Calibrating" : "No data"
    }

    private func strainTarget(_ day: DayRecord?) -> ClosedRange<Double>? {
        guard let arr = day?.json("score_details")?["strainTarget"]?.array, arr.count == 2,
              let lo = arr[0].double, let hi = arr[1].double, lo <= hi else { return nil }
        return lo...hi
    }

    private func ring(_ route: DetailRoute, _ title: String, _ value: Double?, _ color: Color, _ end: Color?,
                      _ caption: String?, target: ClosedRange<Double>? = nil, suffix: String = "") -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 5) {
                RingGauge(progress: (value ?? 0) / 100, color: color, endColor: end, lineWidth: 7,
                          target: target.map { ($0.lowerBound / 100)...($0.upperBound / 100) }) {
                    Text(value.map { Format.number($0) + suffix } ?? "–")
                        .font(Font.fredoka(16))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(8)
                }
                .frame(width: 62, height: 62)
                Text(title)
                    .font(Font.fs(.caption2, .semibold))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Text(caption ?? " ")
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TonightGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let plan = model.sleepPlan
        let bed = plan.bedtimeMin.map { Format.clock($0) } ?? "–"
        let wake = plan.wakeMin.map { Format.clock($0) } ?? "–"
        GlanceLink(route: .homeCard(HomeCardSpec(.tonight), date)) {
            GlanceFrame {
                GlanceHeader(title: "Tonight", icon: "moon.stars.fill", tint: Theme.sleep)
                Spacer(minLength: 0)
                if size == .small {
                    Text("In bed by").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                    GlanceValue(value: bed, size: 30)
                    Text("Need \(Format.duration(plan.needMin))")
                        .font(Font.fs(.caption, .semibold))
                        .foregroundStyle(Theme.sleep)
                        .lineLimit(1)
                    Text("Wake at \(wake)")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                } else {
                    HStack(alignment: .top) {
                        GlanceStat(title: "Need tonight", value: Format.duration(plan.needMin), size: 24)
                        Spacer(minLength: 8)
                        GlanceStat(title: "In bed by", value: bed, size: 24)
                        Spacer(minLength: 8)
                        GlanceStat(title: "Wake at", value: wake, size: 24)
                    }
                    Spacer(minLength: 0)
                    Text(parts(plan))
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.sleep)
                        .lineLimit(2)
                }
            }
        }
    }

    private func parts(_ plan: SleepPlan) -> String {
        var parts = ["Base \(Format.duration(plan.baseMin))"]
        if plan.strainMin > 0 { parts.append("+\(Format.duration(plan.strainMin)) for strain") }
        if plan.debtMin > 0 { parts.append("+\(Format.duration(plan.debtMin)) for debt") }
        if plan.napMin > 0 { parts.append("−\(Format.duration(plan.napMin)) naps") }
        return parts.joined(separator: " · ")
    }
}

struct JournalGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel
    @State private var editing = false

    var body: some View {
        let entry = model.journal[date]
        Button {
            editing = true
        } label: {
            GlanceFrame {
                GlanceHeader(title: "Journal", icon: "square.and.pencil", tint: Theme.stress, trailing: entry == nil ? nil : "Edit")
                if let entry, !entry.tags.isEmpty || !(entry.note ?? "").isEmpty {
                    logged(entry)
                } else if entry != nil {
                    GlanceMessage(text: "Nothing to note.")
                } else {
                    Spacer(minLength: 0)
                    Image(systemName: "plus.circle.fill")
                        .font(Font.fs(.title2))
                        .foregroundStyle(Theme.stress)
                    Text(date == model.today ? "Log today" : "Log this day")
                        .font(Font.fs(.subheadline, .semibold))
                        .foregroundStyle(.white)
                    Text(loggedDaysText ?? "Tag caffeine, alcohol, a late meal and more.")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journal-edit")
        .sheet(isPresented: $editing) { JournalSheet(date: date).environmentObject(model) }
    }

    @ViewBuilder private func logged(_ entry: JournalEntry) -> some View {
        let note = entry.note ?? ""
        let limit = size == .small ? 3 : 7
        if !entry.tags.isEmpty {
            FlowLayout(spacing: 5) {
                ForEach(Array(entry.tags.prefix(limit)), id: \.self) { tag in
                    TagChip(label: model.tagLabel(tag), icon: model.tagIcon(tag), compact: true)
                }
                if entry.tags.count > limit {
                    Text("+\(entry.tags.count - limit)")
                        .font(Font.fs(.caption, .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
        if !note.isEmpty {
            Text(note)
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
        }
        Spacer(minLength: 0)
        if size == .medium {
            ForEach(Array(impactLines(entry).prefix(2)), id: \.self) { line in
                Label(line, systemImage: "arrow.turn.down.right")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// For the day's tags, the clearest effect found so far on the morning after (the
    /// server's tag impacts): "Caffeine after 2 pm: Time asleep −24m (9 days)". Tags without
    /// enough logged days have none.
    private func impactLines(_ entry: JournalEntry) -> [String] {
        let impacts = model.stats?.journal ?? []
        return entry.tags.compactMap { tag -> String? in
            guard let impact = impacts.first(where: { $0.tag == tag }) else { return nil }
            let effects = impact.effects.filter { $0.diff.isFinite && MetricCatalog.def($0.metric) != nil }
            guard let best = effects.filter(\.clear).max(by: { abs($0.t ?? 0) < abs($1.t ?? 0) })
                    ?? effects.max(by: { abs($0.t ?? 0) < abs($1.t ?? 0) }),
                  let def = MetricCatalog.def(best.metric) else { return nil }
            return "\(impact.label): \(def.shortLabel) \(Self.signed(best.diff, def)) (\(impact.days) days)"
        }
    }

    private static func signed(_ diff: Double, _ def: MetricDef) -> String {
        let sign = diff < 0 ? "−" : "+"
        switch def.format {
        case .duration: return sign + Format.duration(abs(diff))
        default: return sign + def.formatted(abs(diff))
        }
    }

    /// "Logged 4 of the last 7 days" for a day not logged yet.
    private var loggedDaysText: String? {
        guard size == .medium else { return nil }
        let logged = glanceDates(7, endingOn: date).filter { model.journal[$0] != nil }.count
        return logged == 0 ? nil : "Logged \(logged) of the last 7 days. Tag caffeine, alcohol, a late meal and more."
    }
}

struct VitalsGlance: View {
    let date: String
    let size: CardSize
    /// The metrics picked in the card's settings, in order; nil shows every vital.
    var chosen: [String]? = nil
    @EnvironmentObject var model: AppModel

    static let keys = ["rhr", "hrv_rmssd", "spo2_avg", "resp_rate", "skin_temp_dev", "vo2max"]
    /// Names that fit next to the value in a small card.
    private static let tinyLabels = [
        "rhr": "RHR", "hrv_rmssd": "HRV", "spo2_avg": "SpO₂", "resp_rate": "Breath", "skin_temp_dev": "Skin", "vo2max": "VO₂",
    ]
    private static let columns = [
        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
    ]

    var body: some View {
        let defs = (chosen ?? Self.keys).filter(model.recorded.contains).compactMap { MetricCatalog.def($0) }
        let day = model.daysByDate[date]
        GlanceFrame(spacing: 6) {
            GlanceHeader(title: "Vitals", icon: "stethoscope", tint: Theme.stress, trailing: size == .medium ? "vs 30-day average" : nil)
            if let day, !defs.isEmpty {
                if size == .small {
                    ForEach(Array(defs.prefix(3)), id: \.key) { def in
                        row(def, day)
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(defs.prefix(6)), id: \.key) { def in
                            cell(def, day)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                GlanceMessage(icon: "stethoscope", text: "No vitals recorded yet.")
            }
        }
    }

    /// As the full card: day totals and incomplete days aren't compared, nor clock times and
    /// the skin temperature (already a difference from your baseline).
    private func change(_ def: MetricDef, _ day: DayRecord) -> Double? {
        guard model.countsToward(def, day), def.format != .clock, def.key != "skin_temp_dev" else { return nil }
        return glanceChange(def.value(day), model.baseline(def, before: date))
    }

    private func row(_ def: MetricDef, _ day: DayRecord) -> some View {
        NavigationLink(value: DetailRoute.metric(def.key)) {
            HStack(spacing: 6) {
                Image(systemName: def.icon)
                    .font(Font.fs(.caption2))
                    .foregroundStyle(def.category.color)
                    .frame(width: 14)
                Text(Self.tinyLabels[def.key] ?? def.shortLabel)
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(def.formatted(def.value(day)))
                    .font(Font.fredoka(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TrendArrow(change: change(def, day), better: def.better)
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cell(_ def: MetricDef, _ day: DayRecord) -> some View {
        NavigationLink(value: DetailRoute.metric(def.key)) {
            VStack(alignment: .leading, spacing: 2) {
                FittingText(def.shortLabel, short: def.compactLabel)
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.secondary)
                HStack(spacing: 3) {
                    Text(def.formatted(def.value(day)))
                        .font(Font.fredoka(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    TrendArrow(change: change(def, day), better: def.better)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ActivityGlance: View {
    let date: String
    let size: CardSize
    /// The numbers picked in the card's settings, in order; nil shows the first three defaults.
    var chosen: [String]? = nil
    @EnvironmentObject var model: AppModel

    static let keys = ["calories_total", "calories_active", "azm_total", "distance_km", "floors", "active_min_total"]
    static let defaultKeys = ["calories_total", "azm_total", "distance_km"]

    var body: some View {
        let day = model.daysByDate[date]
        let steps = day?.double("steps")
        let goal = Double(model.status?.settings.stepGoal ?? 10000)
        let progress = min(1, (steps ?? 0) / max(goal, 1))
        GlanceLink(route: .metric("steps")) {
            GlanceFrame {
                GlanceHeader(title: "Activity", icon: "figure.walk", tint: Theme.strain,
                             trailing: date >= model.today ? "So far today" : nil, shortTrailing: date >= model.today ? "So far" : nil)
                if size == .small {
                    HStack {
                        Spacer(minLength: 0)
                        RingGauge(progress: progress, color: Theme.strain, endColor: Theme.strainEnd, lineWidth: 9) {
                            VStack(spacing: 0) {
                                Text(Format.number(steps))
                                    .font(Font.fredoka(18))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text("steps")
                                    .font(Font.fs(.caption2))
                                    .foregroundStyle(Theme.secondary)
                            }
                            .padding(10)
                        }
                        .frame(width: 90, height: 90)
                        Spacer(minLength: 0)
                    }
                    Text("Goal \(Format.number(goal))")
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    let keys = Array((chosen ?? Self.defaultKeys).filter(model.recorded.contains).prefix(3))
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            GlanceValue(value: Format.number(steps), unit: "steps", size: 30)
                            ProgressView(value: progress)
                                .tint(Theme.strain)
                            Text("Goal \(Format.number(goal))")
                                .font(Font.fs(.caption2))
                                .foregroundStyle(Theme.tertiary)
                            if let day { comparison(day) }
                        }
                        if !keys.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(keys, id: \.self) { key in
                                    if let def = MetricCatalog.def(key), let day {
                                        GlanceStat(title: def.shortLabel, shortTitle: def.compactLabel, value: def.formatted(def.value(day)), size: 15)
                                    }
                                }
                            }
                            .frame(width: 96, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    /// As the full card: today against what you usually have by this time, other days against
    /// the 30-day average, never for a low-wear day.
    @ViewBuilder private func comparison(_ day: DayRecord) -> some View {
        if let steps = day.double("steps"), day.bool("low_wear") != true {
            if date == model.today {
                let minute = model.lastDataMinute(date) ?? model.localMinuteNow
                if let typical = model.typicalSteps(before: date, atMinute: minute) {
                    line("Usually \(Format.number(typical)) by \(Format.clock(Double(minute)))", glanceChange(steps, typical))
                }
            } else if let def = MetricCatalog.def("steps"), let base = model.baseline(def, before: date) {
                line("30-day avg \(Format.number(base))", glanceChange(steps, base))
            }
        }
    }

    private func line(_ text: String, _ change: Double?) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            DeltaBadge(change: change, better: .higher)
        }
    }
}

struct HeartRateGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let detail = model.dayDetails[date]
        let hr = detail?.intraday?.hr ?? []
        let series = Self.quarterHours(hr)
        let rhr = day?.double("rhr")
        let range = "\(Format.number(day?.double("hr_min")))–\(Format.number(day?.double("hr_max")))"
        GlanceLink(route: .homeCard(HomeCardSpec(.heartRate), date)) {
            GlanceFrame {
                GlanceHeader(title: "Heart rate", icon: "heart.fill", tint: Theme.heart, trailing: size == .medium ? "\(range) bpm" : nil)
                if size == .small {
                    GlanceValue(value: range, unit: "bpm", size: 22)
                    Text("Resting \(Format.number(rhr))")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                } else {
                    HStack {
                        Text("Resting \(Format.number(rhr)) bpm")
                        Spacer(minLength: 8)
                        if let latest = Self.latest(hr) {
                            Text("\(latest.bpm) bpm at \(Format.clock(Double(latest.minute)))")
                        }
                    }
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                }
                if series.compactMap({ $0 }).count >= 2 {
                    MiniLine(values: series, color: Theme.heart, baseline: rhr)
                        .frame(maxHeight: .infinity)
                } else if series.contains(where: { $0 != nil }) {
                    // One quarter-hour so far draws as a lone dot.
                    GlanceMessage(text: "The line fills in as your band syncs.")
                } else if detail == nil && !model.failedDays.contains(date) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GlanceMessage(text: "No minute heart rate for this day.")
                }
            }
        }
    }

    /// The day's 1,440 minutes as 96 quarter-hour means; nil where nothing was measured.
    static func quarterHours(_ hr: [Int?]) -> [Double?] {
        guard !hr.isEmpty else { return [] }
        return stride(from: 0, to: hr.count, by: 15).map { start -> Double? in
            let measured = hr[start..<min(hr.count, start + 15)].compactMap { $0 }
            guard !measured.isEmpty else { return nil }
            return Double(measured.reduce(0, +)) / Double(measured.count)
        }
    }

    private static func latest(_ hr: [Int?]) -> (minute: Int, bpm: Int)? {
        guard let index = hr.lastIndex(where: { $0 != nil }), let bpm = hr[index] else { return nil }
        return (index, bpm)
    }
}

struct WorkoutsGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let detail = model.dayDetails[date]
        let exercises = detail?.exercises ?? []
        GlanceFrame(spacing: 6) {
            GlanceHeader(title: "Workouts", icon: "figure.run", tint: Theme.strain, trailing: exercises.count > 1 ? "\(exercises.count)" : nil)
            if detail == nil && !model.failedDays.contains(date) {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if exercises.isEmpty {
                if size == .medium, let day = model.daysByDate[date], !dayStats(day).isEmpty {
                    Text(date == model.today ? "No workouts yet today." : "No workouts this day.")
                        .font(Font.fs(.footnote))
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                    statRow(dayStats(day), title: date == model.today ? "Today so far" : "That day")
                } else {
                    GlanceMessage(icon: "figure.run", text: date == model.today ? "No workouts yet today." : "No workouts this day.")
                }
            } else if size == .small, let last = exercises.last {
                NavigationLink(value: DetailRoute.workout(date, last.id)) {
                    smallWorkout(last, more: exercises.count - 1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout-row")
            } else {
                ForEach(Array(exercises.suffix(2))) { x in
                    NavigationLink(value: DetailRoute.workout(date, x.id)) {
                        WorkoutRow(exercise: x, zone: model.zone)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-row")
                }
                if exercises.count == 1, let only = exercises.first {
                    let stats = effortStats(only)
                    if !stats.isEmpty {
                        statRow(stats, title: nil)
                    } else if let day = model.daysByDate[date], !dayStats(day).isEmpty {
                        Spacer(minLength: 0)
                        statRow(dayStats(day), title: date == model.today ? "Today so far" : "That day")
                    }
                }
                if exercises.count > 2 {
                    NavigationLink(value: DetailRoute.homeCard(HomeCardSpec(.workouts), date)) {
                        Text("+\(exercises.count - 2) more")
                            .font(Font.fs(.caption, .semibold))
                            .foregroundStyle(Theme.strain)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Strain, average and peak heart rate and zone minutes, the ones recorded. Without a strain
    /// the row already shows the average heart rate, so it isn't repeated.
    private func effortStats(_ x: Exercise) -> [(String, String)] {
        var stats: [(String, String)] = []
        if let v = x.strain { stats.append(("Strain", Format.number(v, decimals: 1))) }
        if x.strain != nil, let v = x.avgHr { stats.append(("Avg HR", "\(Int(v.rounded()))")) }
        if let v = x.hrMax { stats.append(("Max HR", "\(Int(v.rounded()))")) }
        if let v = x.azm, v > 0 { stats.append(("Zone min", "\(Int(v.rounded()))")) }
        return stats
    }

    /// The day's own effort: strain, active minutes, zone minutes and active calories.
    private func dayStats(_ day: DayRecord) -> [(String, String)] {
        ["strain", "active_min_total", "azm_total", "calories_active"].compactMap { key -> (String, String)? in
            guard model.recorded.contains(key), let def = MetricCatalog.def(key), let v = def.value(day) else { return nil }
            return (def.shortLabel, def.formatted(v))
        }
    }

    private func statRow(_ stats: [(String, String)], title: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title.uppercased())
                    .font(Font.fs(.caption2, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.tertiary)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stats.prefix(4).enumerated()), id: \.offset) { _, stat in
                    GlanceStat(title: stat.0, value: stat.1, size: 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }

    private func smallWorkout(_ x: Exercise, more: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: x.symbol)
                .font(Font.fs(.title3))
                .foregroundStyle(Theme.strain)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.strain.opacity(0.18)))
            Text(x.displayName)
                .font(Font.fs(.subheadline, .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(x.durationText)
                    .font(Font.fredoka(18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let strain = x.strain {
                    Text("strain \(Format.number(strain, decimals: 1))")
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                }
            }
            if more > 0 {
                Text("+\(more) more")
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct LastNightGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        GlanceLink(route: .sleep(date)) {
            GlanceFrame {
                GlanceHeader(title: "Last night", icon: "bed.double.fill", tint: Theme.sleep,
                             trailing: date == model.today ? nil : Format.shortDay(date))
                if let day, Self.hasSleep(day) {
                    content(day)
                } else {
                    GlanceMessage(icon: "moon.zzz", text: "No sleep recorded.")
                }
            }
        }
    }

    @ViewBuilder private func content(_ day: DayRecord) -> some View {
        let asleep = day.double("sleep_asleep_min")
        let score = day.double("sleep_score")
        let parts = stages(day)
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    GlanceValue(value: Format.duration(asleep), size: size == .small ? 24 : 30)
                    if size == .medium { DeltaBadge(change: change(asleep), better: .higher) }
                }
                Text(window(day))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if size == .small {
                    Text(score.map { "Sleep score \(Format.number($0))" } ?? "No sleep score")
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            if size == .medium {
                Spacer(minLength: 8)
                RingGauge(progress: min(1, max(0, (score ?? 0) / 100)), color: Theme.sleep, lineWidth: 6) {
                    Text(score.map { Format.number($0) } ?? "–")
                        .font(Font.fredoka(17))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(6)
                }
                .frame(width: 56, height: 56)
            }
        }
        Spacer(minLength: 0)
        if !parts.isEmpty {
            MiniStageBar(parts: parts)
            if size == .medium {
                HStack(spacing: 10) {
                    ForEach(parts) { part in
                        HStack(spacing: 3) {
                            Circle().fill(part.color).frame(width: 6, height: 6)
                            Text("\(part.name) \(Format.duration(part.minutes))")
                                .font(Font.fs(.caption2))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
    }

    private static func hasSleep(_ day: DayRecord) -> Bool {
        day.double("sleep_asleep_min") != nil || day.double("sleep_bedtime_min") != nil || day.double("sleep_waketime_min") != nil
    }

    private func change(_ asleep: Double?) -> Double? {
        guard let def = MetricCatalog.def("sleep_asleep_min") else { return nil }
        return glanceChange(asleep, model.baseline(def, before: date))
    }

    private func window(_ day: DayRecord) -> String {
        let bed = day.double("sleep_bedtime_min")
        let wake = day.double("sleep_waketime_min")
        if bed == nil && wake == nil { return "Bedtime not recorded" }
        return "\(Format.clock(bed)) – \(Format.clock(wake))"
    }

    private func stages(_ day: DayRecord) -> [GlanceStage] {
        var parts: [GlanceStage] = []
        if let v = day.double("sleep_deep_min") { parts.append(GlanceStage(name: "Deep", color: Theme.stageDeep, minutes: v)) }
        if let v = day.double("sleep_rem_min") { parts.append(GlanceStage(name: "REM", color: Theme.stageRem, minutes: v)) }
        if let v = day.double("sleep_light_min") { parts.append(GlanceStage(name: "Light", color: Theme.stageLight, minutes: v)) }
        guard !parts.isEmpty else { return [] }
        if let v = day.double("sleep_awake_min") { parts.append(GlanceStage(name: "Awake", color: Theme.stageAwake, minutes: v)) }
        return parts.reduce(0.0) { $0 + max(0, $1.minutes) } > 0 ? parts : []
    }
}

struct RecoveryTrendGlance: View {
    let date: String
    let size: CardSize
    var days = 14
    @EnvironmentObject var model: AppModel

    var body: some View {
        let values: [Double?] = glanceDates(days, endingOn: date).map { model.daysByDate[$0]?.double("recovery") }
        let scored = values.compactMap { $0 }
        let average: Double? = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let latest: Double? = values.last ?? nil
        GlanceLink(route: .recovery(date)) {
            GlanceFrame {
                GlanceHeader(title: "Recovery trend", icon: "chart.line.uptrend.xyaxis", tint: Theme.recoveryGreen, trailing: "\(days) days")
                if scored.isEmpty {
                    GlanceMessage(icon: "bolt.heart", text: "No recovery yet.")
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            GlanceValue(value: Format.number(average), unit: "%", size: 28)
                            Text("average")
                                .font(Font.fs(.caption2))
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 4)
                        if size == .medium {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(latest.map { "\(Format.number($0))%" } ?? "–")
                                    .font(Font.fredoka(20, weight: .semibold))
                                    .foregroundStyle(Theme.recoveryColor(latest))
                                Text(Format.prettyDay(date, today: model.today))
                                    .font(Font.fs(.caption2))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                    MiniBars(values: values, maxValue: 100) { Theme.recoveryColor($0) }
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

/// HRV or resting heart rate: the value on the day against the 30-day average, with the last
/// 30 days as a line.
struct MetricTrendGlance: View {
    let key: String
    let title: String
    let icon: String
    let tint: Color
    let date: String
    let size: CardSize
    var days = 30
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let def = MetricCatalog.def(key) {
            content(def)
        }
    }

    @ViewBuilder private func content(_ def: MetricDef) -> some View {
        let values: [Double?] = glanceDates(days, endingOn: date).map { d -> Double? in
            guard let day = model.daysByDate[d], model.countsToward(def, day) else { return nil }
            return def.value(day)
        }
        let latest: Double? = values.last ?? nil
        let base = model.baseline(def, before: date)
        GlanceLink(route: .metric(key)) {
            GlanceFrame {
                GlanceHeader(title: title, icon: icon, tint: tint, trailing: "\(days) days")
                if values.allSatisfy({ $0 == nil }) {
                    GlanceMessage(icon: icon, text: "No \(def.shortLabel) yet.")
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        GlanceValue(value: def.formatted(latest, withUnit: false), unit: latest == nil ? nil : def.unit, size: 28)
                        DeltaBadge(change: glanceChange(latest, base), better: def.better)
                        Spacer(minLength: 0)
                        if size == .medium, let base {
                            Text("30-day avg \(def.formatted(base))")
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                    }
                    if size == .small {
                        Text(base.map { "Avg \(def.formatted($0))" } ?? "Building your average")
                            .font(Font.fs(.caption2))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    MiniLine(values: values, color: tint, baseline: base)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

struct StressGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let score = day?.double("stress")
        let hourly = Self.hourly(day)
        GlanceLink(route: .stress(date)) {
            GlanceFrame {
                GlanceHeader(title: "Stress", icon: "brain.head.profile", tint: Theme.stress, trailing: date >= model.today ? "So far" : nil)
                if score == nil && hourly.allSatisfy({ $0 == nil }) {
                    GlanceMessage(icon: "brain.head.profile", text: "No stress score yet.")
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        GlanceValue(value: Format.number(score), size: 30, color: Theme.stressColor(score))
                        Text(Theme.stressLabel(score))
                            .font(Font.fs(.caption, .semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if size == .medium, let peak = Self.peak(hourly) {
                            Text("Highest \(Format.clock(Double(peak * 60)))–\(Format.clock(Double(peak * 60 + 60)))")
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                        }
                    }
                    if hourly.contains(where: { $0 != nil }) {
                        MiniBars(values: hourly, maxValue: 100) { Theme.stressColor($0) }
                            .frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// 24 hourly averages, index = local hour; nil for an hour without enough still minutes.
    private static func hourly(_ day: DayRecord?) -> [Double?] {
        let raw = day?.json("intraday_details")?["stressHourly"]?.array ?? []
        guard !raw.isEmpty else { return [] }
        return (0..<24).map { hour -> Double? in
            guard hour < raw.count, let v = raw[hour].double, v.isFinite else { return nil }
            return v
        }
    }

    /// The highest hour; the earliest one on a tie.
    private static func peak(_ hourly: [Double?]) -> Int? {
        var best: (hour: Int, value: Double)?
        for (hour, value) in hourly.enumerated() {
            guard let value else { continue }
            if best == nil || value > best!.value { best = (hour, value) }
        }
        return best?.hour
    }
}

struct ThisWeekGlance: View {
    let date: String
    let size: CardSize
    /// The metrics picked in the card's settings, in order; nil shows the default five.
    var chosen: [String]? = nil
    @EnvironmentObject var model: AppModel

    static let keys = ["sleep_asleep_min", "recovery", "strain", "steps", "azm_total"]
    /// Counted days each week needs before the two weeks are compared (as ThisWeekCard).
    private static let minDays = 3
    private static let columns = [
        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
        GridItem(.flexible(), spacing: 8, alignment: .topLeading),
    ]

    var body: some View {
        let defs = Array((chosen ?? Self.keys).filter(model.recorded.contains).compactMap { MetricCatalog.def($0) }.prefix(6))
        GlanceLink(route: .homeCard(HomeCardSpec(.thisWeek, CardOptions(metrics: chosen)), date)) {
            GlanceFrame(spacing: 6) {
                GlanceHeader(title: "This week", icon: "calendar", tint: Theme.strain,
                             trailing: "daily avg vs last week", shortTrailing: "vs last week")
                if defs.isEmpty {
                    GlanceMessage(icon: "calendar", text: "No data yet.")
                } else if size == .small {
                    ForEach(Array(defs.prefix(3)), id: \.key) { def in
                        let week = summary(def)
                        HStack(spacing: 6) {
                            Text(def.shortLabel)
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(def.formatted(week.value))
                                .font(Font.fredoka(14, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            TrendArrow(change: week.change, better: def.better)
                        }
                        .padding(.vertical, 4)
                    }
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 10) {
                        ForEach(defs, id: \.key) { def in
                            let week = summary(def)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(def.shortLabel)
                                    .font(Font.fs(.caption2))
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                                HStack(spacing: 3) {
                                    Text(def.formatted(week.value))
                                        .font(Font.fredoka(16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    TrendArrow(change: week.change, better: def.better)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// This week's daily average and its change from last week's; today's still-growing day
    /// totals and low-wear days are left out (model.countsToward), missing days never count.
    private func summary(_ def: MetricDef) -> (value: Double?, change: Double?) {
        let current = average(def, endingOn: date)
        let previous = average(def, endingOn: Format.addDays(date, -7))
        guard current.count >= Self.minDays, previous.count >= Self.minDays else { return (current.mean, nil) }
        return (current.mean, glanceChange(current.mean, previous.mean))
    }

    private func average(_ def: MetricDef, endingOn end: String) -> (mean: Double?, count: Int) {
        let values = glanceDates(7, endingOn: end).compactMap { d -> Double? in
            guard let day = model.daysByDate[d], model.countsToward(def, day), let v = def.value(day), v.isFinite else { return nil }
            return v
        }
        guard !values.isEmpty else { return (nil, 0) }
        return (values.reduce(0, +) / Double(values.count), values.count)
    }
}

struct ZoneMinutesGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    /// Fitbit's default weekly Active Zone Minutes goal (as WeeklyZoneMinutesCard).
    private static let target = 150.0

    var body: some View {
        let dates = glanceDates(7, endingOn: date)
        let def = MetricCatalog.def("azm_total")
        let values: [Double?] = dates.map { d -> Double? in
            guard let def, let day = model.daysByDate[d], let v = def.value(day), v.isFinite, v >= 0 else { return nil }
            return v
        }
        let total = values.compactMap { $0 }.reduce(0, +)
        let progress = min(1, total / Self.target)
        GlanceLink(route: .metric("azm_total")) {
            GlanceFrame {
                GlanceHeader(title: "Zone minutes", icon: "flame.fill", tint: Theme.heart,
                             trailing: date >= model.today ? "7 days so far" : "7 days", shortTrailing: "7 days")
                if values.allSatisfy({ $0 == nil }) {
                    GlanceMessage(icon: "flame", text: "No zone minutes yet.")
                } else if size == .small {
                    HStack {
                        Spacer(minLength: 0)
                        RingGauge(progress: progress, color: Theme.heart, lineWidth: 9) {
                            VStack(spacing: 0) {
                                Text(Format.number(total))
                                    .font(Font.fredoka(22))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text("of \(Format.number(Self.target))")
                                    .font(Font.fs(.caption2))
                                    .foregroundStyle(Theme.secondary)
                            }
                            .padding(10)
                        }
                        .frame(width: 92, height: 92)
                        Spacer(minLength: 0)
                    }
                } else {
                    let scale = max(values.compactMap { $0 }.max() ?? 0, Self.target / 7)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            GlanceValue(value: Format.number(total), unit: "min", size: 30)
                            Text("of \(Format.number(Self.target)) a week")
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(Font.fs(.caption, .semibold))
                                .foregroundStyle(total >= Self.target ? Theme.recoveryGreen : Theme.heart)
                        }
                        MiniBars(values: values, maxValue: scale, labels: dates.map { Format.weekdayLetter($0) }) { _ in Theme.heart }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

struct StreaksGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    private static let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .topLeading),
        GridItem(.flexible(), spacing: 10, alignment: .topLeading),
    ]

    var body: some View {
        let streaks = (model.stats?.streaks ?? [])
            .filter { $0.current > 0 || $0.longest > 0 }
            .sorted { $0.current > $1.current }
        GlanceLink(route: .homeCard(HomeCardSpec(.streaks), date)) {
            GlanceFrame {
                GlanceHeader(title: "Streaks", icon: "trophy.fill", tint: Theme.recoveryYellow)
                if streaks.isEmpty {
                    GlanceMessage(icon: "trophy", text: model.stats == nil ? "Streaks appear once a few days have synced." : "No streaks yet.")
                } else if size == .small, let top = streaks.first {
                    Spacer(minLength: 0)
                    GlanceValue(value: "\(top.current)", unit: top.current == 1 ? "day" : "days", size: 34, color: Theme.recoveryYellow)
                    Text(top.label)
                        .font(Font.fs(.caption, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text("Best \(top.longest)")
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                    if streaks.count > 1 {
                        Text("+\(streaks.count - 1) more")
                            .font(Font.fs(.caption2))
                            .foregroundStyle(Theme.tertiary)
                    }
                } else {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(streaks.prefix(4))) { s in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.label)
                                    .font(Font.fs(.caption2))
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text("\(s.current)")
                                        .font(Font.fredoka(20))
                                        .foregroundStyle(s.current > 0 ? Theme.recoveryYellow : Theme.tertiary)
                                    Text(s.current == 1 ? "day" : "days")
                                        .font(Font.fs(.caption2))
                                        .foregroundStyle(Theme.secondary)
                                    Spacer(minLength: 2)
                                    Text("best \(s.longest)")
                                        .font(Font.fs(.caption2))
                                        .foregroundStyle(Theme.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct InsightGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let insights = model.stats?.insights ?? []
        let first = insights.first
        GlanceLink(route: route(first)) {
            GlanceFrame {
                GlanceHeader(title: "Insights", icon: "sparkles", tint: Theme.recoveryYellow,
                             trailing: moreText(insights.count))
                if first != nil, size == .medium, insights.count > 1 {
                    ForEach(Array(insights.prefix(2))) { insight in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(Font.fs(.subheadline, .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(insight.body)
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                } else if let first {
                    Text(first.title)
                        .font(Font.fs(.subheadline, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(first.body)
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(4)
                    Spacer(minLength: 0)
                } else {
                    GlanceMessage(icon: "sparkles", text: model.stats == nil ? "Insights appear once a few days have synced." : "No insights yet.")
                }
            }
        }
    }

    /// How many insights the card leaves out (a medium card shows two).
    private func moreText(_ count: Int) -> String? {
        let shown = size == .medium ? 2 : 1
        return count > shown ? "+\(count - shown) more" : nil
    }

    private func route(_ insight: Insight?) -> DetailRoute {
        if let key = insight?.metric, MetricCatalog.def(key) != nil { return .metric(key) }
        return .homeCard(HomeCardSpec(.topInsight), date)
    }
}

struct CoachGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var coach: CoachStore
    @Environment(\.homeCardPreview) private var isPreview

    var body: some View {
        let brief: CoachBrief? = coach.brief.flatMap { $0.date == date ? $0 : nil }
        GlanceLink(route: .homeCard(HomeCardSpec(.coachBrief), date)) {
            GlanceFrame {
                GlanceHeader(title: "Coach briefing", icon: "text.bubble.fill", tint: Theme.strainEnd)
                if date != model.today {
                    GlanceMessage(text: "The coach writes a briefing for today only.")
                } else if coach.isBriefing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Writing today's briefing…")
                            .font(Font.fs(.footnote))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)
                } else if let brief {
                    Text(Self.preview(brief.text))
                        .font(Font.fs(.footnote))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(size == .small ? 7 : 5)
                    Spacer(minLength: 0)
                } else {
                    GlanceMessage(icon: "sparkles", text: coach.isConfigured
                                  ? "Tap to write today's briefing."
                                  : "Add a Claude API key to get a daily briefing.")
                }
            }
        }
        .task(id: date) { await loadIfNeeded() }
    }

    /// As CoachBriefCard: fetch the coach status, and with it today's briefing, when it's missing
    /// or from another day.
    @MainActor private func loadIfNeeded() async {
        guard date == model.today, !coach.isBriefing, !isPreview else { return }
        let stale = coach.brief.map { $0.date != date } ?? false
        if coach.status == nil || stale {
            await coach.refresh()
        }
    }

    /// The briefing as plain lines with inline bold and italics: headings and list markers go.
    private static func preview(_ text: String) -> AttributedString {
        let lines = text.split(separator: "\n").map { raw -> String in
            var s = raw.trimmingCharacters(in: .whitespaces)
            while s.hasPrefix("#") { s.removeFirst() }
            if s.hasPrefix("- ") || s.hasPrefix("* ") { s = "• " + String(s.dropFirst(2)) }
            return s.trimmingCharacters(in: .whitespaces)
        }
        let joined = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: joined, options: options)) ?? AttributedString(joined)
    }
}

struct BodyGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    private static let windowDays = 90

    var body: some View {
        let weightDef = MetricCatalog.def("weight_kg")
        let fatDef = MetricCatalog.def("body_fat_pct")
        let weights = weightDef.map { readings($0) } ?? []
        let weight = weightDef.flatMap { latest($0) }
        let fat = fatDef.flatMap { latest($0) }
        GlanceLink(route: .metric("weight_kg")) {
            GlanceFrame {
                GlanceHeader(title: "Body", icon: "scalemass.fill", tint: Theme.body, trailing: weight.map { dayLabel($0.day) })
                if let weightDef, weight != nil || fat != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        GlanceValue(value: weightDef.formatted(weight?.value, withUnit: false), unit: weight == nil ? nil : weightDef.unit, size: 28)
                        if size == .medium, let fatDef, let fat {
                            GlanceValue(value: fatDef.formatted(fat.value, withUnit: false), unit: fatDef.unit, size: 22)
                        }
                        Spacer(minLength: 0)
                    }
                    if size == .small, let fatDef, let fat {
                        Text("Body fat \(fatDef.formatted(fat.value))")
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    if weights.count > 1 {
                        MiniLine(values: weights.map { Optional($0.value) }, color: Theme.body)
                            .frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 0)
                    }
                } else {
                    GlanceMessage(icon: "scalemass", text: "No weight logged yet.")
                }
            }
        }
    }

    private struct Reading {
        let day: String
        let value: Double
    }

    /// A real reading (as BodyCard): missing, zero and excluded days don't count.
    private func reading(_ def: MetricDef, _ day: DayRecord) -> Double? {
        guard model.countsToward(def, day), let v = def.value(day), v.isFinite, v > 0 else { return nil }
        return v
    }

    /// The newest reading on or before `date`, however old.
    private func latest(_ def: MetricDef) -> Reading? {
        var newest: Reading?
        for day in model.days where day.date <= date {
            if let current = newest, current.day >= day.date { continue }
            guard let v = reading(def, day) else { continue }
            newest = Reading(day: day.date, value: v)
        }
        return newest
    }

    /// Readings in the 90 days ending on `date`, oldest first, joined into one line.
    private func readings(_ def: MetricDef) -> [Reading] {
        let from = Format.addDays(date, -(Self.windowDays - 1))
        return model.days
            .filter { $0.date >= from && $0.date <= date }
            .sorted { $0.date < $1.date }
            .compactMap { day in reading(def, day).map { Reading(day: day.date, value: $0) } }
    }

    private func dayLabel(_ day: String) -> String {
        day == date ? Format.prettyDay(day, today: model.today) : Format.shortDay(day)
    }
}

struct LoadGlance: View {
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        let load = model.stats?.load
        GlanceLink(route: .homeCard(HomeCardSpec(.trainingLoad), date)) {
            GlanceFrame {
                GlanceHeader(title: "Training load", icon: "speedometer", tint: Theme.strain)
                if let load, let latest = load.latest {
                    if size == .small {
                        LoadStatusPill(status: load.status)
                        GlanceValue(value: Format.signed(latest.form, decimals: 1), unit: "form", size: 26)
                        Text("Fitness \(Format.number(latest.ctl, decimals: 1)) · Fatigue \(Format.number(latest.atl, decimals: 1))")
                            .font(Font.fs(.caption2))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(2)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            GlanceStat(title: "Form", value: Format.signed(latest.form, decimals: 1))
                            GlanceStat(title: "Fitness", value: Format.number(latest.ctl, decimals: 1), color: TrainingLoadChart.fitnessColor)
                            GlanceStat(title: "Fatigue", value: Format.number(latest.atl, decimals: 1), color: TrainingLoadChart.fatigueColor)
                            Spacer(minLength: 0)
                            LoadStatusPill(status: load.status)
                        }
                        lines(load)
                            .frame(maxHeight: .infinity)
                    }
                } else {
                    GlanceMessage(icon: "speedometer", text: "No training load yet.")
                }
            }
        }
    }

    /// Fitness and fatigue over the last 42 days on one scale.
    private func lines(_ load: TrainingLoad) -> some View {
        let recent = Array(load.series.suffix(42))
        let all = recent.flatMap { [$0.ctl, $0.atl] }
        let lo = all.min() ?? 0
        let hi = all.max() ?? 1
        let pad = max((hi - lo) * 0.12, 1)
        let range = (lo - pad)...(hi + pad)
        return ZStack {
            MiniLine(values: recent.map { Optional($0.ctl) }, color: TrainingLoadChart.fitnessColor, range: range, fill: false)
            MiniLine(values: recent.map { Optional($0.atl) }, color: TrainingLoadChart.fatigueColor, range: range, fill: false)
        }
    }
}

struct LiveHeartRateGlance: View {
    let size: CardSize
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveHeartRateMonitor
    @Environment(\.homeCardPreview) private var isPreview

    var body: some View {
        GlanceLink(route: .liveHeartRate) {
            GlanceFrame {
                GlanceHeader(title: "Live heart rate", icon: "heart.circle", tint: Theme.heart)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(isLive ? Theme.heart : Theme.tertiary)
                                .symbolEffect(.bounce, value: live.samples.last?.id ?? 0)
                            Text(bpmText)
                                .font(Font.fredoka(38))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("bpm")
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                        }
                        Text(caption)
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(size == .small ? 3 : 2)
                    }
                    if size == .medium {
                        let recent = recentValues
                        if recent.count > 1 {
                            MiniLine(values: recent, color: Theme.heart)
                                .frame(height: 64)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { if !isPreview { live.start() } }
        .onDisappear { if !isPreview { live.stop() } }
    }

    private var isLive: Bool {
        guard case .connected = live.state, let at = live.lastUpdate else { return false }
        return Date().timeIntervalSince(at) < 10 && live.latest?.contact != false
    }

    private var bpmText: String {
        guard isLive, let bpm = live.latest?.bpm, bpm > 0 else { return "–" }
        return "\(bpm)"
    }

    /// The last two minutes of readings.
    private var recentValues: [Double?] {
        let cutoff = Date().addingTimeInterval(-120)
        return live.samples.filter { $0.date >= cutoff }.map { Optional(Double($0.bpm)) }
    }

    private var caption: String {
        if isPreview && !isLive { return "Connects to your band while Today is open." }
        if isLive, let bpm = live.latest?.bpm {
            return LiveZone(bpm: bpm, rhr: model.liveRestingHr, maxHr: model.liveMaxHr).name
        }
        switch live.state {
        case .connected:
            return live.latest?.contact == false ? "The band isn't on your wrist." : "Waiting for a reading…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .scanning: return "Looking for your Fitbit Air. Turn on Always visible in Google Health → Share heart rate."
        case .poweredOff: return "Turn on Bluetooth."
        case .unauthorized: return "Allow Bluetooth for FitStats in Settings."
        case .unsupported: return "Bluetooth isn't available."
        case .idle: return live.enabled ? "Starting…" : "Live heart rate is off in Settings."
        }
    }
}

// MARK: - Metric card

/// What a Metric card shows for the `days` days ending on `date`. Nothing is filled in: a day
/// without a value stays empty, and today's still-growing day total is drawn but never averaged
/// (model.countsToward).
struct MetricSummary {
    let def: MetricDef
    let days: Int
    /// One value per day, oldest first.
    let values: [Double?]
    /// The day's own value, else the newest one in the window (weight isn't measured daily).
    let shown: (day: String, value: Double)?
    let average: Double?
    let low: Double?
    let high: Double?
    /// Days that went into the average.
    let counted: Int
    /// Change of the day's own value from the average of the days before it, as the Today
    /// tiles compare: only a complete value, never clock times or skin temperature.
    let change: Double?

    /// Reads the model, which lives on the main actor (as every view does).
    @MainActor init(def: MetricDef, model: AppModel, date: String, days: Int) {
        self.def = def
        self.days = days
        let dates = glanceDates(days, endingOn: date)
        let daily = dates.map { d -> Double? in
            guard let day = model.daysByDate[d], let v = def.value(day), v.isFinite else { return nil }
            return v
        }
        values = daily
        let complete = dates.compactMap { d -> Double? in
            guard let day = model.daysByDate[d], model.countsToward(def, day), let v = def.value(day), v.isFinite else { return nil }
            return v
        }
        average = complete.isEmpty ? nil : complete.reduce(0, +) / Double(complete.count)
        low = complete.min()
        high = complete.max()
        counted = complete.count
        var newest: (day: String, value: Double)?
        for (d, v) in zip(dates, daily).reversed() {
            if let v {
                newest = (d, v)
                break
            }
        }
        shown = newest
        if let newest, newest.day == date, let day = model.daysByDate[date], model.countsToward(def, day),
           def.format != .clock, def.key != "skin_temp_dev" {
            change = glanceChange(newest.value, model.baseline(def, before: date, days: days))
        } else {
            change = nil
        }
    }
}

/// Any metric from the catalog, chosen in the card's settings: the latest value against the
/// average of the days before, and the trend (bars for day totals, a line for the rest).
struct MetricGlance: View {
    let key: String
    let days: Int
    let date: String
    let size: CardSize
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let def = MetricCatalog.def(key) ?? MetricCatalog.def("steps") {
            content(MetricSummary(def: def, model: model, date: date, days: days))
        }
    }

    @ViewBuilder private func content(_ m: MetricSummary) -> some View {
        let def = m.def
        let tint = def.category.color
        GlanceLink(route: .metric(def.key)) {
            GlanceFrame {
                GlanceHeader(title: def.shortLabel, icon: def.icon, tint: tint, trailing: "\(days) days", shortTrailing: "\(days)d")
                if let shown = m.shown {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        GlanceValue(value: def.formatted(shown.value, withUnit: false), unit: def.unit, size: 28)
                        DeltaBadge(change: m.change, better: def.better)
                        Spacer(minLength: 0)
                        if size == .medium {
                            HStack(alignment: .top, spacing: 14) {
                                GlanceStat(title: "Average", value: def.formatted(m.average), size: 15)
                                GlanceStat(title: "Low", value: def.formatted(m.low), size: 15)
                                GlanceStat(title: "High", value: def.formatted(m.high), size: 15)
                            }
                        }
                    }
                    Text(caption(m, day: shown.day))
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    chart(m, tint: tint)
                        .frame(maxHeight: .infinity)
                } else {
                    GlanceMessage(icon: def.icon, text: "No \(def.label.lowercased()) in the last \(days) days.")
                }
            }
        }
    }

    @ViewBuilder private func chart(_ m: MetricSummary, tint: Color) -> some View {
        if m.def.isDayTotal {
            MiniBars(values: m.values) { _ in tint }
        } else {
            MiniLine(values: m.values, color: tint, baseline: m.average)
        }
    }

    private func caption(_ m: MetricSummary, day: String) -> String {
        var parts: [String] = []
        if day != date {
            parts.append(Format.shortDay(day))
        } else if m.def.isDayTotal && date >= model.today {
            parts.append("So far today")
        }
        if size == .small, let avg = m.average { parts.append("avg \(m.def.formatted(avg))") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

// MARK: - Smart Stack

/// Several cards in one spot, like an iOS Smart Stack: swipe sideways between them, the dots
/// show which one is up. With rotate on it opens on the card that fits the time of day
/// (last night and recovery in the morning, activity in the day, tonight in the evening).
struct SmartStackView: View {
    let entries: [StackEntry]
    let size: CardSize
    let date: String
    var rotate = true
    @State private var current: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// No stack inside a stack.
    private var cards: [StackEntry] { entries.filter { $0.card != .stack } }

    var body: some View {
        let shown: CardSize = size == .small ? .small : .medium
        if cards.isEmpty {
            GlanceFrame {
                GlanceHeader(title: "Smart Stack", icon: HomeCard.stack.icon, tint: Theme.recoveryGreen)
                GlanceMessage(text: "No cards in this stack yet. Tap it while editing Home to add some.")
            }
        } else {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(cards) { entry in
                        HomeGlance(spec: entry.spec, size: shown, date: date)
                            .containerRelativeFrame(.horizontal)
                            .id(entry.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $current)
            .frame(height: HomeGlanceMetrics.height(for: typeSize))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottom) { dots }
            .onAppear {
                if current == nil || !cards.contains(where: { $0.id == current }) { current = startID }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Smart Stack, \(cards.count) cards"))
            .accessibilityHint(Text("Swipe left or right for the next card"))
        }
    }

    @ViewBuilder private var dots: some View {
        if cards.count > 1 {
            let up = current ?? cards.first?.id
            HStack(spacing: 5) {
                ForEach(cards) { entry in
                    Circle()
                        .fill(entry.id == up ? Color.white : Color.white.opacity(0.28))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.bottom, 5)
            .allowsHitTesting(false)
        }
    }

    private var startID: String? {
        guard rotate else { return cards.first?.id }
        let hour = Calendar.current.component(.hour, from: Date())
        let fits: Set<HomeCard>
        switch hour {
        case 4..<11: fits = [.lastNight, .scores, .recoveryTrend, .hrvTrend, .restingHrTrend, .coachBrief, .vitals]
        case 11..<18: fits = [.activity, .stressDay, .heartRate, .workouts, .weeklyZoneMinutes, .liveHeartRate, .metric, .trainingLoad]
        default: fits = [.tonight, .journal, .thisWeek, .streaks, .topInsight, .body]
        }
        return (cards.first { fits.contains($0.card) } ?? cards.first)?.id
    }
}
