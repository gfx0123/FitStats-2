import SwiftUI

/// Insights: mean sleep score after each bedtime window, from the server's stats.bedtime (the last
/// 180 nights with a sleep score). Windows with fewer than 3 nights have no means and stay grey.
/// The best window is highlighted only when the server marks its difference from your other
/// nights as clear (Welch's t of 2 or more).
struct BedtimeCard: View {
    let bedtime: BedtimeStats?

    var body: some View {
        Card {
            SectionHeader(title: "Best bedtime", subtitle: subtitle)
            if let bedtime, bedtime.buckets.contains(where: { $0.sleepScore != nil }) {
                Text(headline(bedtime))
                    .font(Font.fs(.subheadline))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("Went to bed")
                    Spacer()
                    Text("sleep score")
                    Text("nights").frame(width: 58, alignment: .trailing)
                }
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
                .accessibilityHidden(true)
                VStack(spacing: 10) {
                    ForEach(bedtime.buckets) { bucket in
                        BedtimeRow(bucket: bucket, highlighted: isHighlighted(bucket, bedtime))
                    }
                }
                if let best = clearBest(bedtime), let detail = bestDetail(best) {
                    Text(detail)
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                }
            } else {
                Text("Needs at least 3 nights with a sleep score in two different bedtime windows.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
            Text("Bedtime is when your main sleep started. Grey windows have fewer than 3 nights, too few for an average.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
            Text("A pattern in your data, not proof that the bedtime itself causes better sleep.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bedtime-card")
    }

    private var subtitle: String {
        guard let nights = bedtime?.nights, nights > 0 else { return "Sleep score by when you went to bed" }
        return "Sleep score by when you went to bed, last \(nights == 1 ? "night" : "\(nights) nights") with a score"
    }

    /// The best bucket, only when its difference is clear.
    private func clearBest(_ bedtime: BedtimeStats) -> BedtimeBucket? {
        guard let best = bedtime.best, best.clear else { return nil }
        return bedtime.buckets.first { $0.label == best.label }
    }

    private func isHighlighted(_ bucket: BedtimeBucket, _ bedtime: BedtimeStats) -> Bool {
        clearBest(bedtime)?.label == bucket.label
    }

    private func headline(_ bedtime: BedtimeStats) -> String {
        guard let best = bedtime.best else {
            return "Not enough nights to compare yet: at least two windows need 3 or more nights."
        }
        let match = bedtime.buckets.first { $0.label == best.label }
        let window = match.map { Self.phrase($0) } ?? best.label
        guard best.clear, let bucket = match else {
            return "No bedtime stands out clearly yet. Nights you went to bed \(window) scored highest, but within your usual night-to-night variation."
        }
        let others = Swift.max(0, bedtime.nights - bucket.nights)
        let size = Format.number(abs(best.diff))
        let points = size == "1" ? "point" : "points"
        return "Nights you went to bed \(window) scored \(size) \(points) \(best.diff >= 0 ? "higher" : "lower") than your other nights (\(nightsText(bucket.nights)) against \(nightsText(others)))."
    }

    /// The best window's other means, when the server sent them.
    private func bestDetail(_ bucket: BedtimeBucket) -> String? {
        var parts: [String] = []
        if let asleep = bucket.asleepMin { parts.append("\(Format.duration(asleep)) asleep") }
        if let recovery = bucket.recovery { parts.append("\(Format.number(recovery))% recovery the next morning") }
        guard !parts.isEmpty else { return nil }
        return "Those nights averaged " + parts.joined(separator: " and ") + "."
    }

    private func nightsText(_ n: Int) -> String {
        n == 1 ? "1 night" : "\(n) nights"
    }

    /// "between 23:00 and 23:30", "before 22:30" or "after 01:00", in the device's clock style.
    static func phrase(_ bucket: BedtimeBucket) -> String {
        if let from = bucket.from, let to = bucket.to { return "between \(Format.clock(from)) and \(Format.clock(to))" }
        if let to = bucket.to { return "before \(Format.clock(to))" }
        if let from = bucket.from { return "after \(Format.clock(from))" }
        return bucket.label
    }

    /// "23:00–23:30", "Before 22:30" or "After 01:00", in the device's clock style.
    static func windowLabel(_ bucket: BedtimeBucket) -> String {
        if let from = bucket.from, let to = bucket.to { return "\(Format.clock(from))–\(Format.clock(to))" }
        if let to = bucket.to { return "Before \(Format.clock(to))" }
        if let from = bucket.from { return "After \(Format.clock(from))" }
        return bucket.label
    }
}

/// One bedtime window: its mean sleep score on a 0–100 bar and its night count.
private struct BedtimeRow: View {
    let bucket: BedtimeBucket
    let highlighted: Bool

    private var barColor: Color { highlighted ? Theme.recoveryGreen : Theme.sleep }

    var body: some View {
        let score = bucket.sleepScore
        HStack(spacing: 8) {
            Text(BedtimeCard.windowLabel(bucket))
                .font(Font.fs(.caption).monospacedDigit())
                .foregroundStyle(score == nil ? Theme.tertiary : (highlighted ? Color.white : Theme.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 116, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    if let score {
                        Capsule()
                            .fill(barColor)
                            .frame(width: Swift.max(6, geo.size.width * CGFloat(Swift.min(100, Swift.max(0, score)) / 100)))
                    }
                }
            }
            .frame(height: 8)
            Text(score.map { Format.number($0) } ?? "–")
                .font(Font.fs(.caption, .semibold).monospacedDigit())
                .foregroundStyle(score == nil ? Theme.tertiary : (highlighted ? Theme.recoveryGreen : Color.white))
                .frame(width: 30, alignment: .trailing)
            Text("\(bucket.nights)")
                .font(Font.fs(.caption).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let nights = bucket.nights == 1 ? "1 night" : "\(bucket.nights) nights"
        let score = bucket.sleepScore.map { "average sleep score \(Format.number($0))" } ?? "too few nights for an average"
        return "\(BedtimeCard.windowLabel(bucket)): \(nights), \(score)\(highlighted ? ", best bedtime" : "")"
    }
}
