import SwiftUI

/// Stages of the main sleep: hypnogram, night composition and one row per stage,
/// each compared with your own previous 30 nights.
struct SleepStagesCard: View {
    let date: String
    let layout: HypnogramLayout
    let day: DayRecord?
    @EnvironmentObject var model: AppModel
    @State var scrubbed: HypnogramSegment?

    var body: some View {
        let stages = stageInfos
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Stages")
                Spacer()
                readout
            }
            HypnogramView(layout: layout, zone: model.zone) { scrubbed = $0 }
            CompositionBar(parts: stages.compactMap { s in s.minutes.map { (s.color, $0) } })
            if !layout.classic, let restorative = restorativeText {
                Text(restorative).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 14) {
                ForEach(stages) { StageRow(info: $0) }
            }
            .padding(.top, 2)
            Text("Shares are of time asleep; the white tick is your average over the previous 30 nights. Tap the chart to read a stage.")
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
        }
        .sensoryFeedback(.selection, trigger: scrubbed)
    }

    @ViewBuilder private var readout: some View {
        if let s = scrubbed {
            HStack(spacing: 5) {
                Circle().fill(layout.color(of: s.code)).frame(width: 7, height: 7)
                Text("\(layout.name(of: s.code)) · \(Format.time(s.start, zone: model.zone))–\(Format.time(s.end, zone: model.zone)) · \(Format.duration(s.minutes))")
            }
            .font(Font.fs(.caption, .semibold).monospacedDigit())
        } else {
            Text("\(Format.time(layout.start, zone: model.zone)) – \(Format.time(layout.end, zone: model.zone))")
                .font(Font.fs(.caption).monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
    }

    private var asleepMinutes: Double {
        if let v = day?.double("sleep_asleep_min"), v > 0 { return v }
        return layout.segments.filter { $0.code != 0 }.reduce(0) { $0 + $1.minutes }
    }

    private var restorativeText: String? {
        let deep = day?.double("sleep_deep_min") ?? layout.minutes(2)
        let rem = day?.double("sleep_rem_min") ?? layout.minutes(3)
        guard asleepMinutes > 0, deep + rem > 0 else { return nil }
        let share = Int(((deep + rem) / asleepMinutes * 100).rounded())
        return "Restorative sleep (deep + REM): \(Format.duration(deep + rem)) · \(share)%"
    }

    private var stageInfos: [StageInfo] {
        let asleep = max(1, asleepMinutes)
        func info(_ name: String, _ color: Color, key: String?, code: Int) -> StageInfo {
            let fromSegments: Double? = layout.segments.contains(where: { $0.code == code }) ? layout.minutes(code) : nil
            let minutes = key.flatMap { day?.double($0) } ?? fromSegments
            return StageInfo(name: name, color: color, minutes: minutes, share: minutes.map { $0 / asleep },
                             average: key.flatMap { averageShare($0) }, note: nil)
        }
        let awakeMinutes = day?.double("sleep_awake_min") ?? layout.minutes(0)
        let awake = StageInfo(name: "Awake", color: Theme.stageAwake, minutes: awakeMinutes, share: nil, average: nil, note: awakeNote)
        if layout.classic {
            return [
                awake,
                info("Restless", Theme.stageRestless, key: nil, code: 5),
                info("Asleep", Theme.stageLight, key: nil, code: 4),
            ]
        }
        return [
            awake,
            info("REM", Theme.stageRem, key: "sleep_rem_min", code: 3),
            info("Light", Theme.stageLight, key: "sleep_light_min", code: 1),
            info("Deep", Theme.stageDeep, key: "sleep_deep_min", code: 2),
        ]
    }

    private var awakeNote: String {
        var parts: [String] = []
        if let n = day?.double("sleep_awakenings") {
            parts.append(n == 1 ? "1 time awake" : "\(Int(n)) times awake")
        }
        if let avg = previousNights.compactMap({ $0.double("sleep_awake_min") }).averageIfEnough {
            parts.append("30-night avg \(Format.duration(avg))")
        }
        return parts.joined(separator: " · ")
    }

    private var previousNights: [DayRecord] {
        let from = Format.addDays(date, -30)
        return model.days.filter { $0.date >= from && $0.date < date }
    }

    private func averageShare(_ key: String) -> Double? {
        previousNights.compactMap { d -> Double? in
            guard let m = d.double(key), let a = d.double("sleep_asleep_min"), a > 0 else { return nil }
            return m / a
        }
        .averageIfEnough
    }
}

private struct StageInfo: Identifiable {
    let name: String
    let color: Color
    let minutes: Double?
    let share: Double?    // of time asleep
    let average: Double?  // same share, previous 30 nights
    let note: String?
    var id: String { name }
}

private extension Array where Element == Double {
    /// Mean of at least three values, else nil.
    var averageIfEnough: Double? { count >= 3 ? reduce(0, +) / Double(count) : nil }
}

/// The night split by stage, in hypnogram order.
private struct CompositionBar: View {
    let parts: [(Color, Double)]

    var body: some View {
        let visible = parts.filter { $0.1 > 0 }
        let total = max(1, visible.reduce(0) { $0 + $1.1 })
        GeometryReader { geo in
            let usable = geo.size.width - CGFloat(max(0, visible.count - 1)) * 2
            HStack(spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { item in
                    Rectangle()
                        .fill(item.element.0.gradient)
                        .frame(width: max(0, usable * CGFloat(item.element.1 / total)))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

private struct StageRow: View {
    let info: StageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(info.color).frame(width: 8, height: 8)
                Text(info.name).font(Font.fs(.subheadline, .medium))
                Spacer()
                Text(Format.duration(info.minutes)).font(Font.fredoka(16, weight: .semibold))
            }
            if let share = info.share {
                HStack(spacing: 10) {
                    ShareTrack(value: share, average: info.average, color: info.color)
                    Text("\(Int((share * 100).rounded()))%")
                        .font(Font.fs(.caption, .semibold).monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                    Text(info.average.map { "avg \(Int(($0 * 100).rounded()))%" } ?? "")
                        .font(Font.fs(.caption2).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: 50, alignment: .trailing)
                }
            } else if let note = info.note, !note.isEmpty {
                Text(note).font(Font.fs(.caption)).foregroundStyle(Theme.secondary).padding(.leading, 16)
            }
        }
    }
}

/// Share of time asleep on a 0–60 % scale, with a tick at your 30-night average.
private struct ShareTrack: View {
    let value: Double
    let average: Double?
    let color: Color

    private let scale = 0.6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: value > 0 ? max(6, width * CGFloat(min(1, value / scale))) : 0)
                if let average {
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: 12)
                        .offset(x: width * CGFloat(min(1, average / scale)) - 1)
                }
            }
        }
        .frame(height: 6)
        .padding(.leading, 16)
    }
}
