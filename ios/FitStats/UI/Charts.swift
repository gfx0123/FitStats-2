import Charts
import SwiftUI

struct DayPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Axis helpers. Swift Charts draws an x label starting at its tick, so a tick close to the
/// right edge gets its label clipped ("Oct 18" → "O"). Ticks stop `room` before the end.
enum ChartAxis {
    static func ticks(from start: Date, to end: Date, room: TimeInterval, every step: (Date) -> Date?) -> [Date] {
        var out: [Date] = []
        var t = start
        while end.timeIntervalSince(t) >= room {
            out.append(t)
            guard let next = step(t), next > t else { break }
            t = next
        }
        return out.isEmpty ? [start] : out
    }

    /// About four evenly spaced day ticks for daily charts.
    static func dayTicks(_ dates: [Date]) -> [Date] {
        guard let first = dates.min(), let last = dates.max() else { return [] }
        let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? 0
        let step = max(1, Int((Double(span) / 4).rounded(.up)))
        // A label is ~12% of the plot width ("Oct 2025" ~17%).
        let room = last.timeIntervalSince(first) * (spansYears(dates) ? 0.18 : 0.13)
        return ticks(from: first, to: last, room: room) { Calendar.current.date(byAdding: .day, value: step, to: $0) }
    }

    static func spansYears(_ dates: [Date]) -> Bool {
        guard let first = dates.min(), let last = dates.max() else { return false }
        return last.timeIntervalSince(first) > 200 * 86_400
    }

    /// Whole-hour ticks (every 2 h for long nights) in the account's time zone.
    static func hourTicks(from start: Date, to end: Date, zone: TimeZone?) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone ?? .current
        let hours = end.timeIntervalSince(start) / 3600
        let step = hours > 6 ? 2 : 1
        guard var first = cal.nextDate(after: start.addingTimeInterval(-1), matching: DateComponents(minute: 0, second: 0),
                                       matchingPolicy: .nextTime) else { return [] }
        if step == 2, cal.component(.hour, from: first) % 2 == 1 { first = first.addingTimeInterval(3600) }
        return ticks(from: first, to: end, room: end.timeIntervalSince(start) * 0.12) {
            cal.date(byAdding: .hour, value: step, to: $0)
        }
    }

    /// Y range with breathing room, so a flat series still gets a readable axis.
    static func paddedDomain(_ values: [Double], includeZero: Bool) -> ClosedRange<Double> {
        guard var lo = values.min(), var hi = values.max() else { return 0...1 }
        if includeZero {
            lo = min(lo, 0)
            hi = max(hi, 0)
        }
        let pad = max((hi - lo) * 0.08, abs(hi) * 0.02, 0.5)
        return (includeZero && lo == 0 ? 0 : lo - pad)...(hi + pad)
    }

    /// Fewer decimals on axis labels than in values: "75" rather than "75.0".
    static func decimals(for domain: ClosedRange<Double>, limit: Int) -> Int {
        let span = domain.upperBound - domain.lowerBound
        return min(limit, span >= 4 ? 0 : span >= 0.4 ? 1 : 2)
    }

    static func dayLabel(_ yearly: Bool) -> Date.FormatStyle {
        yearly ? .dateTime.month(.abbreviated).year() : .dateTime.month(.abbreviated).day()
    }
}

/// Daily values for one metric: bars for day totals, line for averages.
struct DailyMetricChart: View {
    let points: [DayPoint]
    let def: MetricDef
    var average: Double? = nil
    var color: Color
    var height: CGFloat = 200

    var body: some View {
        let dates = points.map(\.date)
        let ticks = ChartAxis.dayTicks(dates)
        let label = ChartAxis.dayLabel(ChartAxis.spansYears(dates))
        let domain = ChartAxis.paddedDomain(points.map(\.value) + (average.map { [$0] } ?? []), includeZero: def.isDayTotal)
        let axisDecimals = ChartAxis.decimals(for: domain, limit: def.decimals)
        Chart {
            ForEach(points) { p in
                if def.isDayTotal {
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value(def.label, p.value))
                        .foregroundStyle(color.gradient)
                        .cornerRadius(3)
                } else {
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value(def.label, p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.monotone)
                    if points.count <= 45 {
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value(def.label, p.value))
                            .foregroundStyle(color)
                            .symbolSize(18)
                    }
                }
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXAxis {
            AxisMarks(values: ticks) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel(format: label, centered: false)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(def.formatted(v, withUnit: false, decimals: axisDecimals)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYScale(domain: domain)
        .frame(height: height)
    }
}

struct SparklineView: View {
    let values: [Double]
    var color: Color

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                LineMark(x: .value("i", item.offset), y: .value("v", item.element))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

struct MinuteValue: Identifiable {
    let minute: Int
    let value: Double
    var id: Int { minute }
}

/// Heart rate across one local day, averaged into 5-minute buckets.
struct HeartRateDayChart: View {
    let hr: [Int?]
    var rhr: Double? = nil
    var color: Color = Theme.heart
    var height: CGFloat = 170

    private var buckets: [MinuteValue] {
        var out: [MinuteValue] = []
        var m = 0
        while m < hr.count {
            let slice = hr[m..<min(m + 5, hr.count)].compactMap { $0 }
            if !slice.isEmpty {
                out.append(MinuteValue(minute: m, value: Double(slice.reduce(0, +)) / Double(slice.count)))
            }
            m += 5
        }
        return out
    }

    /// Under half an hour measured (just after midnight, or before the band's first sync of the
    /// day) draws as a lone dot on an empty day, which looks broken: a note instead.
    static let minimumBuckets = 6

    var body: some View {
        let data = buckets
        if data.count < Self.minimumBuckets {
            Label("The line fills in as your band syncs through the day.", systemImage: "waveform.path.ecg")
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.tertiary)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else {
            chart(data)
        }
    }

    private func chart(_ data: [MinuteValue]) -> some View {
        Chart {
            ForEach(data) { p in
                LineMark(x: .value("Time", p.minute), y: .value("BPM", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let rhr {
                // Labelled at the right end: the overnight trace runs along it on the left.
                RuleMark(y: .value("Resting", rhr))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("resting \(Int(rhr.rounded()))").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                    }
            }
        }
        .chartXScale(domain: 0...1440)
        .chartXAxis {
            AxisMarks(values: [0, 360, 720, 1080]) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let m = value.as(Int.self) {
                        Text(Format.clock(Double(m))).foregroundStyle(Theme.tertiary)
                    }
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
        .frame(height: height)
    }
}

struct HourValue: Identifiable {
    let hour: Double
    let value: Double
    var id: Double { hour }
}

struct HourlyBarsChart: View {
    let values: [Double?]
    var colorFor: (Double) -> Color

    var body: some View {
        let data = values.enumerated().compactMap { i, v -> HourValue? in
            guard let v else { return nil }
            return HourValue(hour: Double(i), value: v)
        }
        Chart {
            ForEach(data) { h in
                BarMark(x: .value("Hour", h.hour), y: .value("Value", h.value), width: .fixed(9))
                    .foregroundStyle(colorFor(h.value))
                    .cornerRadius(2)
            }
        }
        .chartXScale(domain: -0.5...23.5)
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: [0.0, 6.0, 12.0, 18.0]) { value in
                AxisValueLabel {
                    if let h = value.as(Double.self) {
                        Text(Format.hour(Int(h))).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().foregroundStyle(Theme.tertiary)
            }
        }
        .frame(height: 150)
    }
}

struct WeekdayValue: Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

struct WeekdayChart: View {
    let values: [Double?]
    let def: MetricDef
    var color: Color

    var body: some View {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let data = values.enumerated().compactMap { i, v -> WeekdayValue? in
            guard let v, i < names.count else { return nil }
            return WeekdayValue(name: names[i], value: v)
        }
        let domain = ChartAxis.paddedDomain(data.map(\.value), includeZero: true)
        let axisDecimals = ChartAxis.decimals(for: domain, limit: def.decimals)
        Chart {
            ForEach(data) { d in
                BarMark(x: .value("Day", d.name), y: .value(def.label, d.value))
                    .foregroundStyle(color.gradient)
                    .cornerRadius(3)
            }
        }
        .chartXScale(domain: names)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(def.formatted(v, withUnit: false, decimals: axisDecimals)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYScale(domain: domain)
        .frame(height: 140)
    }
}

struct TimedValue: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Overnight samples such as HRV or SpO₂ ([epochSeconds, value] pairs).
struct SamplesChart: View {
    let samples: [[Double]]
    var color: Color
    var zone: TimeZone?

    var body: some View {
        let data = samples.compactMap { s -> TimedValue? in
            guard s.count >= 2 else { return nil }
            return TimedValue(date: Date(timeIntervalSince1970: s[0]), value: s[1])
        }
        let start = data.map(\.date).min() ?? Date()
        let end = data.map(\.date).max() ?? start
        Chart {
            ForEach(data) { p in
                LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: start...max(end, start.addingTimeInterval(60)))
        .chartXAxis {
            AxisMarks(values: ChartAxis.hourTicks(from: start, to: end, zone: zone)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(Format.hour(d, zone: zone)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().foregroundStyle(Theme.tertiary)
            }
        }
        .chartYScale(domain: ChartAxis.paddedDomain(data.map(\.value), includeZero: false))
        .frame(height: 130)
    }
}

struct ScatterPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

struct ScatterChart: View {
    let points: [ScatterPoint]
    let xDef: MetricDef
    let yDef: MetricDef
    var color: Color = Theme.stress

    var body: some View {
        Chart {
            ForEach(points) { p in
                PointMark(x: .value(xDef.label, p.x), y: .value(yDef.label, p.y))
                    .foregroundStyle(color.opacity(0.75))
                    .symbolSize(28)
            }
        }
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(xDef.formatted(v, withUnit: false)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yDef.formatted(v, withUnit: false)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .frame(height: 240)
    }
}
