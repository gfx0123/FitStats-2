import SwiftUI

/// Home: Active Zone Minutes ("azm_total": fat burn + cardio + peak) summed over the 7 days
/// ending on `date`, against Fitbit's default weekly target of 150 minutes, with one small bar
/// per day. The total only adds up minutes that were actually recorded: a day without data
/// stays empty and is never counted as zero. Today's minutes are still growing, so they are
/// marked "so far", and today and low-wear days (whose totals are incomplete) are drawn as
/// outlined bars. Nothing is averaged or compared with other days. Tapping opens the Active
/// Zone Minutes detail.
struct WeeklyZoneMinutesCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    /// Fitbit's default weekly Active Zone Minutes goal.
    private static let weeklyTarget = 150.0
    private static let windowDays = 7
    private static let barAreaHeight: CGFloat = 52
    private static let barWidth: CGFloat = 16

    var body: some View {
        let week = weekDays()
        let counted = week.filter { $0.minutes != nil }
        let total = counted.reduce(0.0) { sum, d in sum + (d.minutes ?? 0) }.rounded()
        let soFar = date == model.today
        NavigationLink(value: DetailRoute.metric("azm_total")) {
            Card {
                header(week, soFar: soFar)
                if counted.isEmpty {
                    EmptyStateView(
                        icon: "heart.circle",
                        title: soFar ? "No zone minutes yet" : "No zone minutes",
                        message: emptyMessage(soFar: soFar)
                    )
                } else {
                    summary(total: total, soFar: soFar)
                    progressBar(total: total)
                    dailyBars(week)
                    footnotes(week, countedDays: counted.count)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary(week, total: total, countedDays: counted.count, soFar: soFar))
        .accessibilityValue(counted.isEmpty ? "" : spokenDays(week))
        .accessibilityHint("Opens Active Zone Minutes details")
        .accessibilityIdentifier("weekly-zone-minutes")
    }

    // MARK: sections

    private func header(_ week: [ZoneMinutesDay], soFar: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionHeader(title: "Weekly Zone Minutes", subtitle: rangeText(week))
            Spacer(minLength: 8)
            if soFar {
                Text("so far")
                    .font(Font.fs(.caption2, .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.heart.opacity(0.16)))
                    .foregroundStyle(Theme.heart)
            }
            Image(systemName: "chevron.right")
                .font(Font.fs(.caption2, .semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private func summary(total: Double, soFar: Bool) -> some View {
        let reached = total >= Self.weeklyTarget
        let remaining = Self.weeklyTarget - total
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.number(total))
                        .font(Font.fredoka(30))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("/ \(Format.number(Self.weeklyTarget)) min")
                        .font(Font.fredoka(16, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Text(soFar ? "Last 7 days, today so far" : "7-day total")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if reached {
                    Label("Target reached", systemImage: "checkmark.circle.fill")
                        .font(Font.fs(.subheadline, .semibold))
                        .foregroundStyle(Theme.recoveryGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("\(Format.number(remaining)) min")
                        .font(Font.fredoka(20, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(targetCaption(total: total, reached: reached, soFar: soFar))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func progressBar(total: Double) -> some View {
        let fraction = CGFloat(Swift.min(1, Swift.max(0, total / Self.weeklyTarget)))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if fraction > 0 {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.heart.opacity(0.8), Theme.heart],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: Swift.max(8, geo.size.width * fraction))
                }
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress toward the weekly target of \(Format.number(Self.weeklyTarget)) minutes")
        .accessibilityValue("\(percentText(total)) percent")
    }

    @ViewBuilder private func dailyBars(_ week: [ZoneMinutesDay]) -> some View {
        let scale = barScale(week)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(week) { d in
                dayColumn(d, scale: scale)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily zone minutes bar chart, \(Self.windowDays) days ending \(Format.longDay(date))")
        .accessibilityValue(spokenDays(week))
    }

    private func dayColumn(_ d: ZoneMinutesDay, scale: Double) -> some View {
        let selected = d.date == date
        return VStack(spacing: 4) {
            Text(d.minutes.map { Format.number($0) } ?? "–")
                .font(Font.fs(.caption2, .medium))
                .monospacedDigit()
                .foregroundStyle(d.minutes == nil ? Theme.tertiary : Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            bar(d, scale: scale)
                .frame(height: Self.barAreaHeight, alignment: .bottom)
            Text(Format.weekdayLetter(d.date))
                .font(Font.fs(.caption2, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Theme.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// Solid for a complete day, outlined for today (still counting) and low-wear days, and a
    /// flat grey stub for a day without data.
    @ViewBuilder private func bar(_ d: ZoneMinutesDay, scale: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        if let minutes = d.minutes {
            let length = barLength(minutes, scale: scale)
            if d.isIncomplete {
                shape
                    .fill(Theme.heart.opacity(0.3))
                    .overlay(shape.strokeBorder(Theme.heart, lineWidth: 1))
                    .frame(width: Self.barWidth, height: length)
            } else {
                shape
                    .fill(Theme.heart.gradient)
                    .frame(width: Self.barWidth, height: length)
            }
        } else {
            Capsule()
                .fill(Theme.track)
                .frame(width: Self.barWidth, height: 3)
        }
    }

    @ViewBuilder private func footnotes(_ week: [ZoneMinutesDay], countedDays: Int) -> some View {
        let hasToday = week.contains { $0.isToday && $0.minutes != nil }
        let lowWear = week.filter { $0.lowWear && $0.minutes != nil }
        let missing = week.count - countedDays
        if hasToday || !lowWear.isEmpty {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.heart.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Theme.heart, lineWidth: 1))
                    .frame(width: 8, height: 11)
                Text(outlineLegend(hasToday: hasToday, hasLowWear: !lowWear.isEmpty))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .font(Font.fs(.caption2))
            .foregroundStyle(Theme.tertiary)
            .accessibilityHidden(true)
        }
        if !lowWear.isEmpty {
            Label(lowWearText(lowWear), systemImage: "exclamationmark.circle")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.recoveryYellow)
        }
        if missing > 0 {
            Text(missingText(missing))
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: data

    /// The 7 days ending on `date`, oldest first; `minutes` is nil for a day without data.
    private func weekDays() -> [ZoneMinutesDay] {
        let def = MetricCatalog.def("azm_total")
        return (0..<Self.windowDays).reversed().map { offset -> ZoneMinutesDay in
            let d = Format.addDays(date, -offset)
            let day = model.daysByDate[d]
            var minutes: Double? = nil
            if let def, let day, let v = def.value(day), v.isFinite, v >= 0 {
                minutes = v
            }
            let isToday = d == model.today
            // The server only flags finished days; today is marked "so far" instead.
            let lowWear = !isToday && day?.bool("low_wear") == true
            return ZoneMinutesDay(date: d, minutes: minutes, isToday: isToday, lowWear: lowWear)
        }
    }

    /// Bars share one scale: the week's highest day, but at least the daily pace of the target
    /// (150 / 7, about 22 min), so a light week does not look like a full one.
    private func barScale(_ week: [ZoneMinutesDay]) -> Double {
        let peak = week.compactMap { $0.minutes }.max() ?? 0
        let pace = (Self.weeklyTarget / Double(Self.windowDays)).rounded(.up)
        return Swift.max(peak, pace)
    }

    private func barLength(_ minutes: Double, scale: Double) -> CGFloat {
        guard minutes > 0, scale > 0 else { return 3 }
        let fraction = Swift.min(1, minutes / scale)
        return Swift.max(4, Self.barAreaHeight * CGFloat(fraction))
    }

    // MARK: text

    private func rangeText(_ week: [ZoneMinutesDay]) -> String? {
        guard let first = week.first?.date else { return nil }
        return "\(Format.shortDay(first)) – \(Format.shortDay(date))"
    }

    private func percentText(_ total: Double) -> String {
        Format.number(total / Self.weeklyTarget * 100)
    }

    private func targetCaption(total: Double, reached: Bool, soFar: Bool) -> String {
        if reached {
            let over = total - Self.weeklyTarget
            return over >= 1 ? "\(Format.number(over)) min over target" : "\(percentText(total))% of target"
        }
        return soFar ? "to go · \(percentText(total))%" : "under target · \(percentText(total))%"
    }

    private func outlineLegend(hasToday: Bool, hasLowWear: Bool) -> String {
        if hasToday && hasLowWear { return "Outlined: today so far, or band worn less than usual" }
        if hasToday { return "Outlined: today, still counting" }
        return "Outlined: band worn less than usual"
    }

    private func lowWearText(_ days: [ZoneMinutesDay]) -> String {
        if days.count == 1, let d = days.first {
            return "Band worn less than usual on \(Format.shortDay(d.date)), so its zone minutes may be incomplete."
        }
        return "Band worn less than usual on \(days.count) days, so their zone minutes may be incomplete."
    }

    private func missingText(_ missing: Int) -> String {
        let days = missing == 1 ? "1 day" : "\(missing) days"
        return "No data for \(days) of \(Self.windowDays); the total only counts recorded days."
    }

    private func emptyMessage(soFar: Bool) -> String {
        if model.days.isEmpty { return "Your history is still syncing. Pull down to refresh in a minute." }
        if !model.recorded.contains("azm_total") {
            return "No Active Zone Minutes have synced yet. You earn them in your fat burn, cardio and peak heart-rate zones."
        }
        if soFar { return "No Active Zone Minutes have synced for the last 7 days yet." }
        return "No Active Zone Minutes were recorded in the 7 days ending \(Format.shortDay(date))."
    }

    // MARK: accessibility

    private func accessibilitySummary(_ week: [ZoneMinutesDay], total: Double, countedDays: Int, soFar: Bool) -> String {
        var parts = ["Weekly Zone Minutes, \(Self.windowDays) days ending \(Format.longDay(date))"]
        guard countedDays > 0 else {
            parts.append("No zone minutes recorded")
            return parts.joined(separator: ". ")
        }
        let target = Format.number(Self.weeklyTarget)
        parts.append("\(spokenMinutes(total)) of the \(target) minute weekly target\(soFar ? " so far" : ""), \(percentText(total)) percent")
        if total >= Self.weeklyTarget {
            parts.append("Target reached")
        } else {
            let remaining = spokenMinutes(Self.weeklyTarget - total)
            parts.append(soFar ? "\(remaining) to go" : "\(remaining) short")
        }
        let missing = week.count - countedDays
        if missing > 0 {
            parts.append(missing == 1 ? "No data for 1 day" : "No data for \(missing) days")
        }
        let lowWear = week.filter { $0.lowWear && $0.minutes != nil }.count
        if lowWear > 0 {
            parts.append(lowWear == 1
                ? "Band worn less than usual on 1 day, so its minutes may be incomplete"
                : "Band worn less than usual on \(lowWear) days, so their minutes may be incomplete")
        }
        return parts.joined(separator: ". ")
    }

    private func spokenDays(_ week: [ZoneMinutesDay]) -> String {
        week.map { d -> String in
            let day = d.isToday ? "Today so far" : Format.longDay(d.date)
            guard let minutes = d.minutes else { return "\(day), no data" }
            var text = "\(day), \(spokenMinutes(minutes))"
            if d.lowWear { text += ", low band wear" }
            return text
        }
        .joined(separator: ". ")
    }

    private func spokenMinutes(_ minutes: Double) -> String {
        minutes.rounded() == 1 ? "1 minute" : "\(Format.number(minutes)) minutes"
    }
}

private struct ZoneMinutesDay: Identifiable {
    let date: String
    let minutes: Double?
    let isToday: Bool
    let lowWear: Bool
    var id: String { date }

    /// Today's total is still growing and a low-wear day's total misses minutes.
    var isIncomplete: Bool { isToday || lowWear }
}
