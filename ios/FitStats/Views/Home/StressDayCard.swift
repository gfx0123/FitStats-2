import SwiftUI

/// Home: stress on `date`. The day score (FitStats' estimate from still, awake minutes, see
/// StressDetailView) with its label, and the average stress per hour from
/// fs_days.intraday_details.stressHourly. Hours without enough still minutes are null on the
/// server and stay empty here (nothing is filled in). Today's numbers are still growing, so
/// they are marked "so far"; the card never compares the day with other days. Tapping opens
/// the stress detail.
struct StressDayCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let score = stressScore(day)
        let hourly = hourlyValues(day)
        let hours = recordedHours(hourly)
        let soFar = date == model.today
        NavigationLink(value: DetailRoute.stress(date)) {
            Card {
                header(soFar: soFar)
                if score != nil || !hours.isEmpty {
                    summary(score: score, peak: peakHour(hours), soFar: soFar)
                    chart(hourly: hourly, hours: hours, soFar: soFar)
                    footnote(day, soFar: soFar)
                } else {
                    EmptyStateView(
                        icon: "brain.head.profile",
                        title: soFar ? "No stress data yet" : "No stress data",
                        message: emptyMessage(day, soFar: soFar)
                    )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary(day, score: score, hours: hours, soFar: soFar))
        .accessibilityValue(spokenRange(hours))
        .accessibilityHint("Opens stress details")
        .accessibilityIdentifier("stress-day")
    }

    // MARK: sections

    private func header(soFar: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionHeader(title: "Stress through the day", subtitle: subtitle)
            Spacer(minLength: 8)
            if soFar {
                Text("so far")
                    .font(Font.fs(.caption2, .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.stress.opacity(0.16)))
                    .foregroundStyle(Theme.stress)
            }
            Image(systemName: "chevron.right")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func summary(score: Double?, peak: StressDayHour?, soFar: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.number(score))
                        .font(Font.fredoka(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(scoreLabel(score, soFar: soFar))
                        .font(Font.fs(.subheadline, .semibold))
                        .foregroundStyle(Theme.stressColor(score))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(soFar ? "Day score so far" : "Day score")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let peak {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.number(peak.value))
                        .font(Font.fredoka(20, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Peak \(hourRange(peak.hour))")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }

    @ViewBuilder private func chart(hourly: [Double?], hours: [StressDayHour], soFar: Bool) -> some View {
        if hours.isEmpty {
            Text(soFar ? "No hourly stress yet today." : "No hourly breakdown for this day.")
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.tertiary)
        } else {
            HourlyBarsChart(values: hourly, colorFor: { Theme.stressColor($0) })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartLabel(soFar: soFar))
                .accessibilityValue(spokenHours(hours))
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Self.levels, id: \.self) { level in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.stressColor(level))
                        .frame(width: 7, height: 7)
                    Text(Theme.stressLabel(level))
                }
            }
            Spacer(minLength: 0)
        }
        .font(Font.fs(.caption2))
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityHidden(true)
    }

    /// How many minutes the score rests on, and a warning when the band was barely worn
    /// (the server only flags finished days).
    @ViewBuilder private func footnote(_ day: DayRecord?, soFar: Bool) -> some View {
        if let day {
            if let minutes = day.double("stress_minutes"), minutes.isFinite, minutes > 0 {
                Text(minutesText(minutes, soFar: soFar))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            }
            if !soFar, day.bool("low_wear") == true {
                Label(lowWearText(day), systemImage: "exclamationmark.circle")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.recoveryYellow)
            }
        }
    }

    // MARK: data

    private static let levels: [Double] = [0, 25, 50, 75]

    private func stressScore(_ day: DayRecord?) -> Double? {
        guard let v = day?.double("stress"), v.isFinite else { return nil }
        return v
    }

    /// Up to 24 hourly averages, index = local hour; nil for an hour without enough still minutes.
    private func hourlyValues(_ day: DayRecord?) -> [Double?] {
        guard let raw = day?.json("intraday_details")?["stressHourly"]?.array else { return [] }
        return raw.prefix(24).map { value -> Double? in
            guard let v = value.double, v.isFinite else { return nil }
            return v
        }
    }

    private func recordedHours(_ hourly: [Double?]) -> [StressDayHour] {
        hourly.enumerated().compactMap { item -> StressDayHour? in
            guard let v = item.element else { return nil }
            return StressDayHour(hour: item.offset, value: v)
        }
    }

    /// The highest hour; the earliest one on a tie.
    private func peakHour(_ hours: [StressDayHour]) -> StressDayHour? {
        var best: StressDayHour? = nil
        for h in hours {
            if let current = best, current.value >= h.value { continue }
            best = h
        }
        return best
    }

    /// The lowest hour; the earliest one on a tie.
    private func lowestHour(_ hours: [StressDayHour]) -> StressDayHour? {
        var best: StressDayHour? = nil
        for h in hours {
            if let current = best, current.value <= h.value { continue }
            best = h
        }
        return best
    }

    // MARK: text

    private var subtitle: String {
        "\(Format.prettyDay(date, today: model.today)) · average stress per hour"
    }

    private func scoreLabel(_ score: Double?, soFar: Bool) -> String {
        if score != nil { return Theme.stressLabel(score) }
        return soFar ? "Not enough data yet" : "No day score"
    }

    private func hourRange(_ hour: Int) -> String {
        "\(Format.clock(Double(hour * 60)))–\(Format.clock(Double((hour + 1) * 60)))"
    }

    private func minutesText(_ minutes: Double, soFar: Bool) -> String {
        let base = "Based on \(Format.duration(minutes)) of still, awake time"
        return soFar ? base + " so far" : base
    }

    private func lowWearText(_ day: DayRecord) -> String {
        if let wear = day.double("wear_min") {
            return "Band worn only \(Format.duration(wear)) this day, so the score covers fewer minutes than usual."
        }
        return "Band worn less than usual this day, so the score covers fewer minutes than usual."
    }

    private func emptyMessage(_ day: DayRecord?, soFar: Bool) -> String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        if day == nil { return "Nothing was recorded on \(Format.longDay(date))." }
        if soFar { return "Stress is estimated from still, awake minutes. It appears once enough of today has synced." }
        return "Not enough still, awake heart-rate minutes were recorded on \(Format.longDay(date)) to estimate stress."
    }

    // MARK: accessibility

    private var spokenDay: String {
        date == model.today ? "today so far" : Format.longDay(date)
    }

    private func accessibilitySummary(_ day: DayRecord?, score: Double?, hours: [StressDayHour], soFar: Bool) -> String {
        var parts = ["Stress through the day, \(spokenDay)"]
        if let score {
            parts.append("Day score \(Format.number(score)) out of 100, \(Theme.stressLabel(score))")
        } else if hours.isEmpty {
            parts.append("No stress data")
        } else {
            parts.append(soFar ? "Not enough data for a day score yet" : "No day score")
        }
        if !hours.isEmpty {
            parts.append("Recorded in \(hours.count) of 24 hours")
        }
        if !soFar, day?.bool("low_wear") == true {
            parts.append("Band worn less than usual, so the score covers fewer minutes")
        }
        return parts.joined(separator: ". ")
    }

    private func spokenRange(_ hours: [StressDayHour]) -> String {
        guard let low = lowestHour(hours), let high = peakHour(hours) else { return "" }
        return "Lowest \(Format.number(low.value)) \(spokenHour(low.hour)), highest \(Format.number(high.value)) \(spokenHour(high.hour))"
    }

    private func spokenHour(_ hour: Int) -> String {
        "between \(Format.clock(Double(hour * 60))) and \(Format.clock(Double((hour + 1) * 60)))"
    }

    private func chartLabel(soFar: Bool) -> String {
        let when = soFar ? "today so far" : Format.longDay(date)
        return "Hourly stress bar chart, \(when), on a scale of 0 to 100"
    }

    private func spokenHours(_ hours: [StressDayHour]) -> String {
        hours.map { h -> String in
            "\(Format.clock(Double(h.hour * 60))), \(Format.number(h.value)), \(Theme.stressLabel(h.value))"
        }
        .joined(separator: ". ")
    }
}

private struct StressDayHour: Identifiable {
    let hour: Int
    let value: Double
    var id: Int { hour }
}
