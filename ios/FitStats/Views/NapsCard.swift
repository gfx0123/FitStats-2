import SwiftUI

/// The day's naps: every sleep session except the one the night's numbers come from (the same
/// split as the server's nap_min). Each shows when it was, how long you slept, its stages and
/// your heart rate during it. Naps aren't part of the sleep score; they count as sleep in the
/// sleep debt, and today's take time off tonight's plan.
struct NapsCard: View {
    let naps: [SleepSession]
    /// The day's heart rate by minute of the local day, for each nap's average and lowest.
    let hr: [Int?]?
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: naps.count == 1 ? "Nap" : "Naps", subtitle: "Not part of the sleep score")
                Spacer(minLength: 8)
                // One nap's row already says it.
                if naps.count > 1 {
                    Text("\(Format.duration(Double(totalAsleep))) asleep")
                        .font(Font.fs(.subheadline, .semibold))
                        .foregroundStyle(Theme.sleep)
                }
            }
            ForEach(Array(naps.enumerated()), id: \.element.id) { item in
                if item.offset > 0 { Divider().overlay(Theme.track) }
                NapRow(nap: item.element, hr: hr, zone: model.zone)
            }
            Text("Naps count as sleep in your sleep debt, and today's take up to an hour off tonight's sleep need.")
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep-naps")
    }

    private var totalAsleep: Int {
        naps.reduce(0) { $0 + ($1.minutesAsleep ?? 0) }
    }
}

private struct NapRow: View {
    let nap: SleepSession
    let hr: [Int?]?
    let zone: TimeZone?

    var body: some View {
        let layout = nap.stages.map { HypnogramLayout(stages: $0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(timeRange)
                    .font(Font.fs(.subheadline, .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(Format.duration(nap.minutesAsleep.map(Double.init))) asleep")
                    .font(Font.fs(.subheadline))
                    .foregroundStyle(Theme.secondary)
            }
            if let layout, !layout.segments.isEmpty {
                NapStageStrip(layout: layout)
                stageMinutes(layout)
            }
            HStack(spacing: 16) {
                if let inBed = nap.minutesInPeriod {
                    Label("In bed \(Format.duration(Double(inBed)))", systemImage: "bed.double.fill")
                }
                if let heart = heartRate {
                    Label("\(heart.avg) bpm avg · \(heart.low) lowest", systemImage: "heart.fill")
                }
            }
            .font(Font.fs(.caption))
            .foregroundStyle(Theme.secondary)
            .labelStyle(NapDetailLabel())
        }
        .accessibilityElement(children: .combine)
    }

    private var start: Date? { Format.timestamp(nap.startTime) }
    private var end: Date? { Format.timestamp(nap.endTime) }

    private var timeRange: String {
        guard let start, let end else { return "Nap" }
        return "\(Format.time(start, zone: zone)) – \(Format.time(end, zone: zone))"
    }

    /// Minutes per stage, deepest first, in one wrapping line.
    private func stageMinutes(_ layout: HypnogramLayout) -> some View {
        let lanes = Array(layout.lanes.enumerated()).reversed()
        let parts = lanes.compactMap { lane -> Text? in
            let minutes = layout.segments.filter { layout.lane(of: $0.code) == lane.offset }.reduce(0) { $0 + $1.minutes }
            guard minutes >= 0.5 else { return nil }
            return Text("●").foregroundColor(lane.element.color) + Text(" \(lane.element.name) \(Format.duration(minutes))")
        }
        return parts.dropFirst().reduce(parts.first ?? Text("")) { $0 + Text("    ") + $1 }
            .font(Font.fs(.caption))
            .foregroundStyle(Theme.secondary)
    }

    /// Average and lowest heart rate over the nap's minutes, when the band recorded at least five.
    private var heartRate: (avg: Int, low: Int)? {
        guard let hr, let start, let end else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? .current
        let midnight = calendar.startOfDay(for: end)
        let first = max(0, Int(start.timeIntervalSince(midnight) / 60))
        let last = min(hr.count, Int(end.timeIntervalSince(midnight) / 60))
        guard first < last else { return nil }
        let bpm = hr[first..<last].compactMap { $0 }
        guard bpm.count >= 5, let low = bpm.min() else { return nil }
        return (bpm.reduce(0, +) / bpm.count, low)
    }
}

/// The nap's stages along its time, like a one-line hypnogram.
private struct NapStageStrip: View {
    let layout: HypnogramLayout

    var body: some View {
        GeometryReader { geo in
            let span = max(1, layout.end.timeIntervalSince(layout.start))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.06))
                ForEach(Array(layout.segments.enumerated()), id: \.offset) { item in
                    let s = item.element
                    Rectangle()
                        .fill(layout.color(of: s.code))
                        .frame(width: max(1.5, geo.size.width * CGFloat(s.end.timeIntervalSince(s.start) / span)))
                        .offset(x: geo.size.width * CGFloat(s.start.timeIntervalSince(layout.start) / span))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct NapDetailLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(Theme.tertiary)
            configuration.title
        }
    }
}
