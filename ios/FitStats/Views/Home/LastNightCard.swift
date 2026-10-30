import SwiftUI

/// Home: the main sleep that ended on `date` (the fs_days sleep columns): time asleep against
/// your previous 30 nights, sleep score, bedtime to wake time, stage composition, efficiency
/// and time in bed. Tapping opens the sleep detail.
struct LastNightCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        NavigationLink(value: DetailRoute.sleep(date)) {
            Card {
                header
                if let day, Self.hasSleep(day) {
                    content(day)
                } else {
                    EmptyStateView(icon: "moon.zzz", title: "No sleep recorded", message: emptyMessage)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary(day))
        .accessibilityHint("Opens sleep details")
        .accessibilityIdentifier("last-night")
    }

    // MARK: sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeader(title: "Last night", subtitle: subtitle)
            Spacer()
            Image(systemName: "chevron.right")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private func content(_ day: DayRecord) -> some View {
        let base = asleepBaseline
        let stages = stageParts(day)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Time asleep")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.duration(day.double("sleep_asleep_min")))
                        .font(Font.fredoka(34))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    DeltaBadge(change: asleepChange(day, base: base), better: .higher)
                }
                HStack(spacing: 6) {
                    Image(systemName: "bed.double.fill")
                    Text(window(day)).monospacedDigit()
                }
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            scoreView(day.double("sleep_score"))
        }
        if stages.isEmpty {
            Text("Sleep stages weren't recorded for this night.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        } else {
            LastNightStageBar(parts: stages)
            legend(stages)
        }
        if let why = ScoreBreakdown(day.json("score_details")?["sleep"]).sleepWhy { ScoreWhyLine(why: why) }
        HStack(alignment: .top) {
            stat("Efficiency", efficiencyText(day))
            Spacer(minLength: 8)
            stat("In bed", Format.duration(day.double("sleep_in_bed_min")))
            Spacer(minLength: 8)
            stat("30-night avg", Format.duration(base))
        }
    }

    private func scoreView(_ score: Double?) -> some View {
        VStack(spacing: 4) {
            RingGauge(progress: min(1, max(0, (score ?? 0) / 100)), color: Theme.sleep, lineWidth: 6) {
                Text(score.map { Format.number($0) } ?? "–")
                    .font(Font.fredoka(18))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(6)
            }
            .frame(width: 58, height: 58)
            Text(score == nil ? "No score" : "Sleep score")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
        }
    }

    private func legend(_ parts: [LastNightStage]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(parts) { part in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(part.color).frame(width: 7, height: 7)
                        Text(part.name)
                            .font(Font.fs(.caption2))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                    Text(Format.duration(part.minutes))
                        .font(Font.fredoka(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Text(value)
                .font(Font.fredoka(17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: data

    /// The fs_days sleep columns are all empty when no main sleep ended on this date.
    private static func hasSleep(_ day: DayRecord) -> Bool {
        day.double("sleep_asleep_min") != nil
            || day.double("sleep_bedtime_min") != nil
            || day.double("sleep_waketime_min") != nil
    }

    private var subtitle: String? {
        date == model.today ? nil : "Night ending \(Format.shortDay(date))"
    }

    private var emptyMessage: String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        if date == model.today { return "No sleep that ended today has reached FitStats yet. It appears after your band syncs." }
        return "No main sleep ended on \(Format.longDay(date))."
    }

    /// Mean time asleep over the 30 nights before this one (nil with fewer than 3).
    private var asleepBaseline: Double? {
        guard let def = MetricCatalog.def("sleep_asleep_min") else { return nil }
        return model.baseline(def, before: date)
    }

    private func asleepChange(_ day: DayRecord, base: Double?) -> Double? {
        guard let asleep = day.double("sleep_asleep_min"), let base, base > 0 else { return nil }
        return (asleep - base) / base * 100
    }

    private func window(_ day: DayRecord) -> String {
        let bed = day.double("sleep_bedtime_min")
        let wake = day.double("sleep_waketime_min")
        if bed == nil && wake == nil { return "Bedtime not recorded" }
        return "\(Format.clock(bed)) – \(Format.clock(wake))"
    }

    /// Stored as a fraction of time in bed.
    private func efficiencyText(_ day: DayRecord) -> String {
        guard let e = day.double("sleep_efficiency") else { return "–" }
        return "\(Int((e * 100).rounded()))%"
    }

    /// Deep, REM, light and awake minutes. Empty for a classic sleep (no stages recorded).
    private func stageParts(_ day: DayRecord) -> [LastNightStage] {
        let deep = day.double("sleep_deep_min")
        let rem = day.double("sleep_rem_min")
        let light = day.double("sleep_light_min")
        guard deep != nil || rem != nil || light != nil else { return [] }
        var parts: [LastNightStage] = []
        if let deep { parts.append(LastNightStage(name: "Deep", color: Theme.stageDeep, minutes: deep)) }
        if let rem { parts.append(LastNightStage(name: "REM", color: Theme.stageRem, minutes: rem)) }
        if let light { parts.append(LastNightStage(name: "Light", color: Theme.stageLight, minutes: light)) }
        if let awake = day.double("sleep_awake_min") {
            parts.append(LastNightStage(name: "Awake", color: Theme.stageAwake, minutes: awake))
        }
        let total = parts.reduce(0.0) { $0 + max(0, $1.minutes) }
        return total > 0 ? parts : []
    }

    private func accessibilitySummary(_ day: DayRecord?) -> String {
        let night = date == model.today ? "Last night" : "Night ending \(Format.longDay(date))"
        guard let day, Self.hasSleep(day) else { return "\(night). No sleep recorded." }
        var parts = [night]
        var asleep = "\(lastNightSpoken(day.double("sleep_asleep_min"))) asleep"
        if let change = asleepChange(day, base: asleepBaseline), abs(change) >= 0.5 {
            asleep += ", \(Int(abs(change).rounded())) percent \(change > 0 ? "more" : "less") than your 30-night average"
        }
        parts.append(asleep)
        if let score = day.double("sleep_score") { parts.append("Sleep score \(Format.number(score))") }
        let bed = day.double("sleep_bedtime_min")
        let wake = day.double("sleep_waketime_min")
        if bed != nil || wake != nil {
            parts.append("Bedtime \(Format.clock(bed)), woke at \(Format.clock(wake))")
        }
        let stages = stageParts(day)
        if stages.isEmpty {
            parts.append("Sleep stages not recorded")
        } else {
            parts.append(stages.map { "\($0.name) \(lastNightSpoken($0.minutes))" }.joined(separator: ", "))
        }
        if let e = day.double("sleep_efficiency") { parts.append("Efficiency \(Int((e * 100).rounded())) percent") }
        return parts.joined(separator: ". ")
    }
}

private struct LastNightStage: Identifiable {
    let name: String
    let color: Color
    let minutes: Double
    var id: String { name }
}

/// The night split by stage, widths proportional to minutes.
private struct LastNightStageBar: View {
    let parts: [LastNightStage]

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
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages")
        .accessibilityValue(visible.map { "\($0.name) \(lastNightSpoken($0.minutes))" }.joined(separator: ", "))
    }
}

/// 452 → "7 hours 32 minutes", for VoiceOver.
private func lastNightSpoken(_ minutes: Double?) -> String {
    guard let minutes, minutes.isFinite else { return "not recorded" }
    let total = max(0, Int(minutes.rounded()))
    let h = total / 60, m = total % 60
    var words: [String] = []
    if h > 0 { words.append(h == 1 ? "1 hour" : "\(h) hours") }
    if m > 0 || h == 0 { words.append(m == 1 ? "1 minute" : "\(m) minutes") }
    return words.joined(separator: " ")
}
