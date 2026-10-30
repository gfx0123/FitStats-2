import SwiftUI

/// Home: the streaks from `model.stats?.streaks` (days in a row meeting a goal) next to the
/// longest run so far, in a compact two-column grid. Nothing is computed here: the server
/// works the streaks out as of `stats.today`, not as of the day shown, so the card says so when
/// the two differ. Step and zone-minute streaks only count full days (today's totals are still
/// growing), which a footnote spells out. Missing stats show an empty state, and a streak whose
/// metric was never recorded (and that never had a run) is hidden rather than shown as zero.
struct StreaksCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    /// The metric each known streak is built from (unknown keys from newer servers still show).
    private static let metricKeys: [String: String] = [
        "steps_goal": "steps",
        "sleep_7h": "sleep_asleep_min",
        "azm_22": "azm_total",
        "recovery_green": "recovery",
    ]

    /// Streaks of day totals: the server leaves today's still-growing total out of them.
    private static let fullDayNames: [String: String] = [
        "steps_goal": "step",
        "azm_22": "zone-minute",
    ]

    var body: some View {
        let stats = model.stats
        let items = stats.map { visibleItems($0.streaks) } ?? []
        Card {
            if let stats {
                SectionHeader(title: "Streaks",
                              subtitle: items.isEmpty ? nil : "Days in a row, as of \(dayPhrase(stats.today))")
                if items.isEmpty {
                    EmptyStateView(icon: "trophy", title: "No streaks yet",
                                   message: "Streaks appear once a few days have synced.")
                } else {
                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        ForEach(items) { item in
                            StreakTileView(item: item)
                        }
                    }
                    if let note = footnote(stats, items: items) {
                        Text(note)
                            .font(Font.fs(.caption2))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                SectionHeader(title: "Streaks")
                EmptyStateView(icon: "trophy", title: "No data yet", message: emptyMessage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("streaks")
    }

    // MARK: data

    private func visibleItems(_ streaks: [Streak]) -> [StreakTileItem] {
        streaks.compactMap { s -> StreakTileItem? in
            if let metric = Self.metricKeys[s.key], !model.recorded.contains(metric), s.current == 0, s.longest == 0 {
                return nil
            }
            return StreakTileItem(streak: s, tint: Self.tint(s.key), icon: Self.icon(s.key))
        }
    }

    private static func tint(_ key: String) -> Color {
        switch key {
        case "steps_goal": return Theme.strain
        case "sleep_7h": return Theme.sleep
        case "azm_22": return Theme.heart
        case "recovery_green": return Theme.recoveryGreen
        default: return Theme.recoveryYellow
        }
    }

    private static func icon(_ key: String) -> String {
        guard let metric = metricKeys[key], let def = MetricCatalog.def(metric) else { return "flame.fill" }
        return def.icon
    }

    // MARK: text

    /// "today", "yesterday" or "Sat, Oct 17".
    private func dayPhrase(_ ymd: String) -> String {
        if ymd == model.today { return "today" }
        if ymd == Format.addDays(model.today, -1) { return "yesterday" }
        return Format.shortDay(ymd)
    }

    private func footnote(_ stats: StatsPayload, items: [StreakTileItem]) -> String? {
        var parts: [String] = []
        let names = items.compactMap { item -> String? in Self.fullDayNames[item.streak.key] }
        if !names.isEmpty {
            let subject = names.joined(separator: " and ")
            let capitalized = subject.prefix(1).uppercased() + String(subject.dropFirst())
            let verb = names.count == 1 ? "streak counts" : "streaks count"
            let through = dayPhrase(Format.addDays(stats.today, -1))
            parts.append("\(capitalized) \(verb) full days only, through \(through).")
        }
        if date != stats.today {
            parts.append("Streaks are as of \(dayPhrase(stats.today)), not \(dayPhrase(date)).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private var emptyMessage: String {
        if model.days.isEmpty { return "Your history is still syncing. Streaks appear once a few days are in." }
        return "Streaks appear once your stats are ready. Pull down to refresh."
    }
}

// MARK: - Tile

private struct StreakTileItem: Identifiable {
    let streak: Streak
    let tint: Color
    let icon: String
    var id: String { streak.id }
}

/// One streak: the current run in days, a thin bar of the current run against the longest one,
/// and the longest run. The whole tile is one accessibility element.
private struct StreakTileView: View {
    let item: StreakTileItem

    var body: some View {
        let s = item.streak
        let matchesBest = s.current > 0 && s.current >= s.longest
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: item.icon)
                    .font(Font.fs(.caption2))
                    .foregroundStyle(item.tint)
                Text(s.label)
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2, reservesSpace: true)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: "\(s.current)")
                    .font(Font.fredoka(22))
                    .foregroundStyle(s.current > 0 ? Color.white : Theme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(s.current == 1 ? "day" : "days")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if matchesBest {
                    Image(systemName: "trophy.fill")
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.recoveryYellow)
                }
            }
            StreakProgressBar(fraction: fraction(s), tint: item.tint)
            Text(bestText(s, matchesBest: matchesBest))
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.label) streak")
        .accessibilityValue(spoken(s, matchesBest: matchesBest))
    }

    /// Current run as a share of the longest run (0 when there was never a run).
    private func fraction(_ s: Streak) -> Double {
        guard s.longest > 0 else { return 0 }
        return min(1, max(0, Double(s.current) / Double(s.longest)))
    }

    private func bestText(_ s: Streak, matchesBest: Bool) -> String {
        if s.longest == 0 { return "No streak yet" }
        if matchesBest { return "Matches your best" }
        return "Best \(Self.days(s.longest))"
    }

    private func spoken(_ s: Streak, matchesBest: Bool) -> String {
        if s.longest == 0 { return "No streak yet" }
        let current = s.current == 0 ? "No current streak" : "\(Self.days(s.current)) in a row"
        if matchesBest { return "\(current), matching your best" }
        var best = "Best \(Self.days(s.longest))"
        if let end = s.longestEnd {
            best += ", ended \(Format.longDay(end))"
        }
        return "\(current). \(best)"
    }

    private static func days(_ n: Int) -> String { n == 1 ? "1 day" : "\(n) days" }
}

/// Thin capsule bar, decorative: the tile's accessibility value carries the same numbers.
private struct StreakProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                if fraction > 0 {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(fraction)))
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
