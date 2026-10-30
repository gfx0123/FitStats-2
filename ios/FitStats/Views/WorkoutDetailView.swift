import Charts
import SwiftUI

extension Exercise {
    /// Google generates displayName from exercise_type for every type but OTHER, in varying case
    /// ("Strength Training" and "Strength training"), so the label comes from the type. Only a
    /// custom OTHER (or untyped) workout keeps Google's name.
    var displayName: String {
        let kind = exerciseType ?? ""
        if kind.isEmpty || kind == "OTHER" || kind == "EXERCISE_TYPE_UNSPECIFIED" {
            if let name, !name.isEmpty { return name }
            return "Workout"
        }
        switch kind {
        case "HIIT", "TRX": return kind
        default: return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbol: String {
        switch exerciseType ?? "" {
        case "RUNNING", "TREADMILL", "TRAIL_RUN", "INCLINE_RUN": return "figure.run"
        case "WALKING", "HIKING", "POWER_WALKING", "TREADMILL_WALK", "INCLINE_WALK": return "figure.walk"
        case "BIKING", "OUTDOOR_BIKE", "STATIONARY_BIKE", "SPINNING", "MOUNTAIN_BIKE": return "figure.outdoor.cycle"
        case "SWIMMING", "SWIMMING_POOL", "SWIMMING_OPEN_WATER": return "figure.pool.swim"
        case "STRENGTH_TRAINING", "WEIGHTLIFTING", "WEIGHTS", "FREE_WEIGHTS", "POWERLIFTING": return "dumbbell.fill"
        case "YOGA", "PILATES", "STRETCHING": return "figure.yoga"
        case "HIIT", "CROSSFIT", "CIRCUIT_TRAINING", "TABATA_WORKOUT": return "bolt.heart.fill"
        default: return "figure.mixed.cardio"
        }
    }

    /// Active time (Google's activeDuration, else the whole session) in seconds.
    var activeSeconds: Double? { activeDurationS ?? durationS }

    var minutes: Double? { activeSeconds.map { $0 / 60 } }

    /// "16s" for a fragment under a minute, otherwise "1h 35m".
    var durationText: String { Format.duration(seconds: activeSeconds) }

    /// Running and walking pace, "5:24" per km. Hidden when the implied speed is implausible for
    /// the type (under 3 km/h for runs, 1.5 km/h for walks), such as a 248 m "run" over 16 minutes.
    var pace: String? {
        let slowest: Double
        switch symbol {
        case "figure.run": slowest = 3
        case "figure.walk": slowest = 1.5
        default: return nil
        }
        guard let m = distanceM, m > 100, let mins = minutes, mins > 0 else { return nil }
        let km = m / 1000
        guard km / (mins / 60) >= slowest else { return nil }
        let perKm = Int((mins / km * 60).rounded())
        return "\(perKm / 60):\(String(format: "%02d", perKm % 60))"
    }

    /// Google's workout step count is sometimes far too low (853 steps for a 5.8 km game) while
    /// its distance comes from the full count. The minute steps summed over the workout window
    /// replace it when it is missing or 0, or when it implies over 1 m per step and the minute
    /// steps are higher. They are approximate: the partial first and last minutes count in full.
    var usesMinuteSteps: Bool {
        guard let minute = stepsMinute, minute > 0 else { return false }
        guard let steps, steps > 0 else { return true }
        guard let m = distanceM else { return false }
        return m / steps > 1.0 && minute > steps
    }

    var shownSteps: Double? {
        if usesMinuteSteps { return stepsMinute }
        guard let steps, steps > 0 else { return nil }
        return steps
    }

    /// How Google says the workout was recorded (DataSource.recordingMethod); nil when it does not say.
    var originLabel: String? {
        switch recordingMethod ?? "" {
        case "PASSIVELY_MEASURED": return "Auto-detected"
        case "ACTIVELY_MEASURED": return "Tracked"
        case "MANUAL": return "Logged manually"
        case "DERIVED": return "Derived"
        default: return nil
        }
    }

    /// The server's workout window (lib/transform.ts minutesBetween): from the start's minute for
    /// ceil((end − that minute) / 60 s) minutes, so partial first and last minutes count.
    var windowStart: Date? {
        guard let start = Format.timestamp(startTime) else { return nil }
        let ms = (start.timeIntervalSince1970 * 1000).rounded()
        return Date(timeIntervalSince1970: (ms / 60_000).rounded(.down) * 60)
    }

    var windowMinutes: Int? {
        guard let start = windowStart, let end = Format.timestamp(endTime) else { return nil }
        let ms = (end.timeIntervalSince(start) * 1000).rounded()
        return max(0, Int((ms / 60_000).rounded(.up)))
    }
}

private struct StatTile: Hashable {
    let title: String
    let value: String
    let icon: String
    var sub: String? = nil
}

private struct ZoneTime: Identifiable {
    let name: String
    let seconds: Double?
    var id: String { name }
}

/// One workout's heart-rate drop after 1 minute, for the recovery history chart.
private struct RecoveryPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let current: Bool
}

/// How much of the workout window has minute heart rate.
private struct HRCoverage {
    let minutes: Int
    let window: Int

    /// Under 70 %: strain and zones describe only part of the workout.
    var partial: Bool { window > 0 && Double(minutes) < 0.7 * Double(window) }
}

struct WorkoutDetailView: View {
    let date: String
    let exerciseId: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let detail = model.dayDetails[date]
        let exercise = detail?.exercises.first { $0.id == exerciseId }
        ScrollView {
            VStack(spacing: 14) {
                if let exercise {
                    let series = minuteSeries(exercise, hr: detail?.intraday?.hr)
                    let coverage = hrCoverage(exercise, series: series)
                    header(exercise)
                    statsGrid(exercise, coverage: coverage)
                    heartRateCard(exercise, series: series, coverage: coverage)
                    recoveryCard(exercise)
                    zonesCard(exercise, coverage: coverage)
                    loadCard(exercise, coverage: coverage)
                } else if detail == nil {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Card { EmptyStateView(icon: "questionmark", title: "Workout not found", message: "It may have been deleted in the Google Health app.") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(Format.shortDay(date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let exercise {
                    AskCoachButton(text: "About my band workout “\(exercise.displayName)” on \(Format.longDay(date)): how hard was it, and how should I recover?")
                }
            }
        }
        .task { await model.loadDay(date) }
    }

    private func header(_ x: Exercise) -> some View {
        let range = timeRange(x)
        return Card {
            HStack(spacing: 14) {
                Image(systemName: x.symbol)
                    .font(Font.fs(.title2))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.strain.opacity(0.18)))
                    .foregroundStyle(Theme.strain)
                VStack(alignment: .leading, spacing: 4) {
                    Text(x.displayName).font(Font.fs(.title3, .semibold))
                    Text(range.isEmpty ? Format.longDay(date) : range).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                    if x.originLabel != nil || !(x.sourceDevice ?? "").isEmpty {
                        origin(x)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func origin(_ x: Exercise) -> some View {
        HStack(spacing: 6) {
            if let label = x.originLabel {
                Text(label)
                    .font(Font.fs(.caption2, .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.strain.opacity(0.16)))
                    .foregroundStyle(Theme.strain)
            }
            if let device = x.sourceDevice, !device.isEmpty {
                Text(device).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func timeRange(_ x: Exercise) -> String {
        guard let start = Format.timestamp(x.startTime), let end = Format.timestamp(x.endTime) else { return "" }
        return "\(Format.time(start, zone: model.zone))–\(Format.time(end, zone: model.zone))"
    }

    private func statsGrid(_ x: Exercise, coverage: HRCoverage?) -> some View {
        let partial = coverage?.partial == true
        var tiles = [StatTile(title: "Duration", value: x.durationText, icon: "clock")]
        if let s = x.strain {
            tiles.append(StatTile(title: "Strain", value: Format.number(s, decimals: 1), icon: "flame.fill", sub: partial ? "partial" : nil))
        }
        if let hr = x.avgHr { tiles.append(StatTile(title: "Average HR", value: "\(Int(hr)) bpm", icon: "heart")) }
        if let hr = x.hrMax { tiles.append(StatTile(title: "Peak minute HR", value: "\(Int(hr)) bpm", icon: "arrow.up.heart")) }
        if let kcal = x.calories { tiles.append(StatTile(title: "Calories", value: "\(Format.number(kcal)) kcal", icon: "flame")) }
        if let m = x.distanceM, m > 0 { tiles.append(StatTile(title: "Distance", value: "\(Format.number(m / 1000, decimals: 2)) km", icon: "map")) }
        if let pace = x.pace { tiles.append(StatTile(title: "Pace", value: "\(pace) /km", icon: "speedometer")) }
        if let azm = x.azm, azm > 0 {
            let value = MetricCatalog.def("azm_total")?.formatted(azm) ?? "\(Format.number(azm)) min"
            tiles.append(StatTile(title: "Zone Minutes", value: value, icon: "heart.circle"))
        }
        if let steps = x.shownSteps {
            let approximate = x.usesMinuteSteps
            tiles.append(StatTile(title: "Steps", value: (approximate ? "≈ " : "") + Format.number(steps), icon: "figure.walk",
                                  sub: approximate ? "from minute steps" : nil))
        }
        return TwoColumnTiles(items: tiles) { t in
            MetricTile(title: t.title, value: t.value, sub: t.sub, icon: t.icon, color: Theme.strain)
        }
    }

    /// The workout's minute heart rate over the server's window, from the day's minutes (local
    /// minutes in the server's time zone). Nil without the day's minutes.
    private func minuteSeries(_ x: Exercise, hr: [Int?]?) -> [Double?]? {
        guard let hr, let start = x.windowStart, let count = x.windowMinutes else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = model.zone ?? .current
        let c = cal.dateComponents([.hour, .minute], from: start)
        let first = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return (0..<count).map { i -> Double? in
            let m = first + i
            guard m < hr.count, let bpm = hr[m] else { return nil }
            return Double(bpm)
        }
    }

    /// Minutes with heart rate in the window: the server's count, else counted from the day's minutes.
    private func hrCoverage(_ x: Exercise, series: [Double?]?) -> HRCoverage? {
        guard let window = x.windowMinutes, window > 0 else { return nil }
        if let stored = x.hrMinutes { return HRCoverage(minutes: Int(stored.rounded()), window: window) }
        guard let series else { return nil }
        return HRCoverage(minutes: series.compactMap { $0 }.count, window: window)
    }

    /// A minute more than 30 bpm above both neighbours becomes their mean, as on the server, so a
    /// one-minute optical spike does not peak above the Peak minute HR tile.
    private static func smoothedSpikes(_ s: [Double?]) -> [Double?] {
        guard s.count >= 3 else { return s }
        var out = s
        for i in 1..<(s.count - 1) {
            if let a = s[i - 1], let v = s[i], let b = s[i + 1], v - a > 30, v - b > 30 {
                out[i] = (a + b) / 2
            }
        }
        return out
    }

    private func chartPoints(_ series: [Double?]) -> [MinuteValue] {
        var out: [MinuteValue] = []
        for (i, v) in Self.smoothedSpikes(series).enumerated() {
            if let v { out.append(MinuteValue(minute: i, value: v)) }
        }
        return out
    }

    @ViewBuilder private func heartRateCard(_ x: Exercise, series: [Double?]?, coverage: HRCoverage?) -> some View {
        let points = chartPoints(series ?? [])
        // The whole workout on the x axis, so minutes without heart rate show as a gap.
        let window = max(1, x.windowMinutes ?? 1)
        Card {
            SectionHeader(title: "Heart rate", subtitle: "Minute by minute; the dashed line is this workout's average")
            if points.count >= 2 {
                let minuteAvg = points.map(\.value).reduce(0, +) / Double(points.count)
                // At the Average HR tile's value when Google sends one, so the two agree.
                let avg = x.avgHr ?? minuteAvg
                let lowest = points.map(\.value).min() ?? 0
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Minute", p.minute), yStart: .value("Base", lowest), yEnd: .value("BPM", p.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.heart.opacity(0.35), Theme.heart.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Minute", p.minute), y: .value("BPM", p.value))
                            .foregroundStyle(Theme.heart)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(Int(avg.rounded()))").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                        }
                }
                .chartXScale(domain: 0...window)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(Theme.track)
                        AxisValueLabel {
                            if let m = value.as(Int.self) { Text("\(m) min").foregroundStyle(Theme.tertiary) }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Theme.track)
                        AxisValueLabel().foregroundStyle(Theme.tertiary)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartTapBubble(points.map { p in
                    ChartPoint(x: p.minute, y: p.value, title: "\(Int(p.value.rounded())) bpm", subtitle: "minute \(p.minute)")
                }, tint: Theme.heart)
                .frame(height: 180)
            } else {
                Text("No minute heart rate for this workout.").font(Font.fs(.footnote)).foregroundStyle(Theme.tertiary)
            }
            if let coverage, coverage.partial, coverage.minutes > 0 {
                Label("Heart rate recorded for \(coverage.minutes) of \(coverage.window) min, so strain and zones cover only those minutes.",
                      systemImage: "exclamationmark.circle")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.recoveryYellow)
            }
        }
    }

    // MARK: heart-rate recovery

    /// How far heart rate fell 1 and 2 minutes after the workout (server: hrr_1min, hrr_2min), against
    /// your average for the same exercise type from the stats (stats.hrr) once there are 3 earlier
    /// sessions, with that type's history.
    private func recoveryCard(_ x: Exercise) -> some View {
        Card {
            SectionHeader(title: "Heart-rate recovery", subtitle: "How fast your heart rate fell once the workout ended")
            if let hrr1 = x.hrr1min {
                let history = recoveryHistory(x)
                let earlier = history.filter { $0.date < x.date && $0.id != x.id }
                let charted = history.count + (history.contains(where: { $0.id == x.id }) ? 0 : 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(recoveryText(hrr1, x.hrr2min))
                        .font(Font.fredoka(20))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let end = x.endHr {
                        Text("From \(Int(end.rounded())) bpm at the end of the workout")
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                comparison(x, hrr1: hrr1, earlier: earlier)
                if charted >= 2 {
                    recoveryChart(x, hrr1: hrr1, history: history, earlier: earlier)
                }
                Text("A bigger drop usually goes with better fitness. It also depends on how hard you finished and whether you kept moving, so compare similar workouts.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            } else {
                Text("Heart-rate recovery needs a hard finish and heart rate for the 2 minutes after the workout.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hr-recovery")
    }

    /// Workouts of the same type with a recovery, oldest first.
    private func recoveryHistory(_ x: Exercise) -> [HrrPoint] {
        (model.stats?.hrr ?? []).filter { $0.exerciseType == x.exerciseType }
    }

    /// A drop in heart rate as a change: 24 → "−24"; a rise (negative drop) reads "+3".
    private static func dropText(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n >= 0 ? "−\(n)" : "+\(-n)"
    }

    /// "−24 bpm after 1 min, −38 after 2 min".
    private func recoveryText(_ hrr1: Double, _ hrr2: Double?) -> String {
        var text = "\(Self.dropText(hrr1)) bpm after 1 min"
        if let hrr2 { text += ", \(Self.dropText(hrr2)) after 2 min" }
        return text
    }

    @ViewBuilder private func comparison(_ x: Exercise, hrr1: Double, earlier: [HrrPoint]) -> some View {
        if earlier.count >= 3 {
            let average = earlier.map(\.hrr1).reduce(0, +) / Double(earlier.count)
            let delta = (hrr1 - average).rounded()
            let size = Int(abs(delta))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Your \(x.displayName) average: \(Self.dropText(average)) bpm after 1 min over \(earlier.count) earlier sessions")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(delta == 0 ? "as usual" : "\(size) bpm \(delta > 0 ? "bigger" : "smaller") drop")
                    .font(Font.fs(.caption, .semibold))
                    .foregroundStyle(delta == 0 ? Theme.secondary : (delta > 0 ? Theme.recoveryGreen : Theme.recoveryYellow))
            }
        } else {
            let left = 3 - earlier.count
            Text("Your \(x.displayName) average shows once 3 earlier sessions have a recovery (\(left) more to go).")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func recoveryChart(_ x: Exercise, hrr1: Double, history: [HrrPoint], earlier: [HrrPoint]) -> some View {
        var points = history.compactMap { p -> RecoveryPoint? in
            guard let date = Format.chartDate(p.date) else { return nil }
            return RecoveryPoint(id: p.id, date: date, value: p.hrr1, current: p.id == x.id)
        }
        // The stats are rebuilt after a sync, so a brand-new workout may not be in them yet.
        if !history.contains(where: { $0.id == x.id }), let date = Format.chartDate(x.date) {
            points.append(RecoveryPoint(id: x.id, date: date, value: hrr1, current: true))
            points.sort { $0.date < $1.date }
        }
        let data = points
        let average: Double? = earlier.count >= 3 ? earlier.map(\.hrr1).reduce(0, +) / Double(earlier.count) : nil
        let dates = data.map(\.date)
        let ticks = ChartAxis.dayTicks(dates)
        let label = ChartAxis.dayLabel(ChartAxis.spansYears(dates))
        let domain = ChartAxis.paddedDomain(data.map(\.value) + (average.map { [$0] } ?? []), includeZero: false)
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(x.displayName): drop after 1 min, last 12 months").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
            Chart {
                ForEach(data) { p in
                    LineMark(x: .value("Day", p.date), y: .value("Drop", p.value))
                        .foregroundStyle(Theme.heart.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("Day", p.date), y: .value("Drop", p.value))
                        .foregroundStyle(p.current ? Color.white : Theme.heart)
                        .symbolSize(p.current ? 60 : 22)
                }
                if let average {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
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
            .chartTapBubble(data.map { p in
                ChartPoint(x: p.date, y: p.value, title: "Drop \(Int(p.value.rounded())) bpm",
                           subtitle: p.date.formatted(.dateTime.month(.abbreviated).day().year()))
            }, tint: Theme.heart)
            .frame(height: 120)
            .accessibilityLabel("\(x.displayName) heart-rate recovery history, \(data.count) workouts")
        }
    }

    @ViewBuilder private func zonesCard(_ x: Exercise, coverage: HRCoverage?) -> some View {
        let hrr = (x.hrrZoneMin ?? []).map { $0 ?? 0 }
        let fitbit = [
            ZoneTime(name: "Light", seconds: x.zoneLightS), ZoneTime(name: "Moderate", seconds: x.zoneModerateS),
            ZoneTime(name: "Vigorous", seconds: x.zoneVigorousS), ZoneTime(name: "Peak", seconds: x.zonePeakS),
        ]
        let hasFitbit = fitbit.contains(where: { $0.seconds != nil })
        if hrr.count == 5 || hasFitbit {
            Card {
                if hrr.count == 5 {
                    SectionHeader(title: "Heart-rate reserve zones", subtitle: "Time in each zone, as % of heart-rate reserve")
                    // The other heart-rate minutes, so the rows add up to every minute with heart rate.
                    ZoneBars(minutes: hrr, below: coverage.map { max(0, Double($0.minutes) - hrr.reduce(0, +)) })
                }
                if hasFitbit {
                    if hrr.count == 5 { Divider().overlay(Theme.track) }
                    SectionHeader(title: "Fitbit zones")
                    ForEach(fitbit) { zone in
                        KeyValueRow(key: zone.name, value: Format.duration(seconds: zone.seconds))
                    }
                }
                if hrr.count == 5 {
                    Text(zonesNote(fitbitShown: hasFitbit))
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    /// Names the max heart rate the day's scores used (intraday_details.maxHr) when it is saved.
    private func zonesNote(fitbitShown: Bool) -> String {
        let maxHr = model.daysByDate[date]?.json("intraday_details")?["maxHr"]?.double
        let used = maxHr.map { " (\(Int($0.rounded())) bpm)" } ?? ""
        return "FitStats zones use your max heart rate\(used)" + (fitbitShown ? "; Fitbit zones are Google's own." : ".")
    }

    @ViewBuilder private func loadCard(_ x: Exercise, coverage: HRCoverage?) -> some View {
        if let strain = x.strain, let trimp = x.trimp {
            let dayTrimp = model.daysByDate[date]?.double("trimp")
            let partial = coverage?.partial == true
            Card {
                SectionHeader(title: "Training load")
                KeyValueRow(key: "Workout strain", value: Format.number(strain, decimals: 1) + (partial ? " (partial)" : ""))
                KeyValueRow(key: "TRIMP", value: Format.number(trimp))
                if let dayTrimp, dayTrimp > 0 {
                    KeyValueRow(key: "Share of the day's load", value: "\(Int((min(1, trimp / dayTrimp) * 100).rounded()))%")
                }
                Text("Workout strain is what this workout alone scores on the 0\u{2060}–\u{2060}100 day scale. Strain does not add up, so the day's strain is computed from the whole day's TRIMP.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}
