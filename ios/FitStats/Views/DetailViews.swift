import SwiftUI

/// Shared scaffolding for the score detail screens.
private struct DetailScaffold<Content: View>: View {
    let title: String
    let date: String
    @ViewBuilder var content: () -> Content
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(Format.longDay(date))
                    .font(Font.fs(.subheadline))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                content()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskCoachButton(text: "About my \(title.lowercased()) on \(Format.longDay(date)): what's behind it, and what should I do about it?")
            }
        }
        .task { await model.loadDay(date) }
    }
}

private struct BreakdownCard: View {
    let breakdown: ScoreBreakdown
    let color: Color
    var emptyText: String

    var body: some View {
        Card {
            SectionHeader(title: "What went into it")
            if breakdown.components.isEmpty {
                Text(emptyText).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
            } else {
                ForEach(breakdown.components) { ComponentBar(component: $0, color: color) }
            }
        }
    }
}

private struct TrendCard: View {
    let def: MetricDef
    let endDate: String
    var days: Int = 30
    var color: Color
    var referenceLine: Double? = nil
    @EnvironmentObject var model: AppModel

    var body: some View {
        let points = model.series(def, from: Format.addDays(endDate, -(days - 1)), through: endDate)
        let mean = points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
        Card {
            HStack {
                SectionHeader(title: "\(def.label) · \(days) days")
                Spacer()
                if let mean {
                    Text("avg \(def.formatted(mean))").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                }
            }
            if points.count >= 2 {
                DailyMetricChart(points: points, def: def, average: referenceLine ?? mean, color: color, height: 160)
                    .accessibilityIdentifier("trend-chart")
            } else {
                Text("Not enough data yet.").font(Font.fs(.footnote)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

// MARK: - Recovery

struct RecoveryDetailView: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let value = day?.double("recovery")
        let breakdown = ScoreBreakdown(day?.json("score_details")?["recovery"])
        DetailScaffold(title: "Recovery", date: date) {
            Card {
                HStack(spacing: 20) {
                    ScoreRing(title: "Recovery", value: value, maxValue: 100, color: Theme.recoveryColor(value),
                              caption: value == nil ? statusText(breakdown.status) : Theme.recoveryLabel(value),
                              size: 140, lineWidth: 15, suffix: "%")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Theme.recoveryLabel(value)).font(Font.fs(.headline))
                        Text(advice(value)).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
                    }
                }
                if let why = breakdown.recoveryWhy { ScoreWhyLine(why: why) }
            }
            BreakdownCard(breakdown: breakdown, color: Theme.recoveryColor(value),
                          emptyText: "Recovery needs at least 5 nights of HRV or resting heart rate to build your personal baseline.")
            TrendCard(def: MetricCatalog.def("recovery")!, endDate: date, color: Theme.recoveryGreen)
            TrendCard(def: MetricCatalog.def("hrv_rmssd")!, endDate: date, color: Theme.heart)
            TrendCard(def: MetricCatalog.def("rhr")!, endDate: date, color: Theme.heart)
            Text("Recovery is FitStats' own estimate (HRV 45%, resting HR 25%, sleep 20%, skin temperature and breathing 10%), compared with your last 30 nights. It is not Bevel's or Fitbit's score and not a medical measure.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func statusText(_ status: String) -> String {
        status == "calibrating" ? "Calibrating" : "No data"
    }

    private func advice(_ v: Double?) -> String {
        guard let v else { return "No score yet for this morning." }
        if v >= 67 { return "Your body looks recovered. A good day for hard training." }
        if v >= 34 { return "Moderately recovered. Train, but keep the intensity sensible." }
        return "Low recovery. Prioritise rest, easy movement and sleep."
    }
}

// MARK: - Sleep

struct SleepDetailView: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let detail = model.dayDetails[date]
        // The session behind the day's numbers, so the hypnogram and the rows describe the same sleep.
        let main = detail?.mainSleep(id: day?.string("sleep_main_id"))
        // Every other session that day is a nap, as on the server.
        let naps = (detail?.sleeps ?? []).filter { $0.id != main?.id }
        let score = day?.double("sleep_score")
        DetailScaffold(title: "Sleep", date: date) {
            Card {
                HStack(spacing: 20) {
                    ScoreRing(title: "Sleep score", value: score, maxValue: 100, color: Theme.sleep,
                              caption: Format.duration(day?.double("sleep_asleep_min")), size: 140, lineWidth: 15)
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueRow(key: "Bedtime", value: Format.clock(day?.double("sleep_bedtime_min")))
                        KeyValueRow(key: "Wake", value: Format.clock(day?.double("sleep_waketime_min")))
                        KeyValueRow(key: "In bed", value: Format.duration(day?.double("sleep_in_bed_min")))
                        KeyValueRow(key: "Efficiency", value: day?.double("sleep_efficiency").map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                    }
                }
                if let why = ScoreBreakdown(day?.json("score_details")?["sleep"]).sleepWhy { ScoreWhyLine(why: why) }
            }
            if let stages = main?.stages, !stages.isEmpty {
                SleepStagesCard(date: date, layout: HypnogramLayout(stages: stages), day: day)
            }
            BreakdownCard(breakdown: ScoreBreakdown(day?.json("score_details")?["sleep"]), color: Theme.sleep,
                          emptyText: "No main sleep recorded for this night.")
            BedtimeConsistencyCard(endDate: date)
            Card {
                SectionHeader(title: "Night details")
                // Estimated from the awake stretch before the first sleep stage (Fitbit reports 0).
                KeyValueRow(key: "Time to fall asleep", value: day?.double("sleep_latency_min").map { "≈ \(Format.duration($0))" } ?? "–")
                // Awake segments after falling asleep and before the final wake-up.
                KeyValueRow(key: "Awakenings", value: Format.number(day?.double("sleep_awakenings")))
                KeyValueRow(key: "Awake after falling asleep", value: Format.duration(day?.double("sleep_waso_min")))
                KeyValueRow(key: "Awake (incl. falling asleep)", value: Format.duration(day?.double("sleep_awake_min")))
                KeyValueRow(key: "Naps", value: Format.duration(day?.double("nap_min")))
                KeyValueRow(key: "Breathing rate", value: day?.double("resp_rate").map { String(format: "%.1f /min", $0) } ?? "–")
                KeyValueRow(key: "SpO₂ average", value: day?.double("spo2_avg").map { String(format: "%.1f%%", $0) } ?? "–")
            }
            if !naps.isEmpty {
                NapsCard(naps: naps, hr: detail?.intraday?.hr)
            }
            if let hrv = detail?.samples["hrv"], hrv.count >= 2 {
                Card {
                    SectionHeader(title: "Overnight HRV", subtitle: "RMSSD samples during sleep (ms)")
                    SamplesChart(samples: hrv, color: Theme.heart, zone: model.zone, name: "HRV")
                }
            }
            if let spo2 = detail?.samples["spo2"], spo2.count >= 2 {
                Card {
                    SectionHeader(title: "Overnight SpO₂", subtitle: "Blood oxygen during sleep (%)")
                    SamplesChart(samples: spo2, color: Theme.stress, zone: model.zone, name: "SpO₂", decimals: 1)
                }
            }
            let need = Double(model.status?.settings.sleepNeedMin ?? 480)
            TrendCard(def: MetricCatalog.def("sleep_asleep_min")!, endDate: date, days: 14, color: Theme.sleep, referenceLine: need)
            TrendCard(def: MetricCatalog.def("sleep_score")!, endDate: date, color: Theme.sleep)
        }
    }
}

// MARK: - Strain

struct StrainDetailView: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let detail = model.dayDetails[date]
        let value = day?.double("strain")
        let targetArr = day?.json("score_details")?["strainTarget"]?.array
        let target: ClosedRange<Double>? = {
            guard let a = targetArr, a.count == 2, let lo = a[0].double, let hi = a[1].double, lo <= hi else { return nil }
            return lo...hi
        }()
        let intraday = day?.json("intraday_details")
        let azm = MetricCatalog.def("azm_total")!
        DetailScaffold(title: "Strain", date: date) {
            Card {
                HStack(spacing: 20) {
                    ScoreRing(title: "Strain", value: value, maxValue: 100, color: Theme.strain, endColor: Theme.strainEnd,
                              caption: target.map { "Goal \(Int($0.lowerBound))–\(Int($0.upperBound))" },
                              size: 140, lineWidth: 15, target: target)
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueRow(key: "Training load", value: Format.number(day?.double("trimp")))
                        KeyValueRow(key: "Max HR used", value: Format.number(intraday?["maxHr"]?.double))
                        KeyValueRow(key: "Resting HR used", value: Format.number(intraday?["rhrUsed"]?.double))
                        KeyValueRow(key: "HR minutes", value: Format.number(intraday?["hrMinutes"]?.double))
                    }
                }
            }
            if let zones = intraday?["hrrZoneMinutes"]?.array, zones.count == 5 {
                Card {
                    SectionHeader(title: "Heart-rate reserve zones", subtitle: "Time in each zone, as % of heart-rate reserve")
                    ZoneBars(minutes: zones.map { $0.double ?? 0 })
                }
            }
            Card {
                SectionHeader(title: "Fitbit zones & Active Zone Minutes")
                // Google's LIGHT zone starts at 30 bpm, so it holds all worn time below moderate.
                KeyValueRow(key: "Light zone (incl. rest/sleep)", value: Format.duration(day?.double("zone_light_min")))
                KeyValueRow(key: "Moderate zone", value: Format.duration(day?.double("zone_moderate_min")))
                KeyValueRow(key: "Vigorous zone", value: Format.duration(day?.double("zone_vigorous_min")))
                KeyValueRow(key: "Peak zone", value: Format.duration(day?.double("zone_peak_min")))
                KeyValueRow(key: "Active Zone Minutes", value: azm.formatted(day.flatMap { azm.value($0) }))
            }
            if let hr = detail?.intraday?.hr, hr.contains(where: { $0 != nil }) {
                Card {
                    SectionHeader(title: "Heart rate")
                    HeartRateDayChart(hr: hr, rhr: day?.double("rhr"))
                }
            }
            if let exercises = detail?.exercises, !exercises.isEmpty {
                Card {
                    SectionHeader(title: "Workouts")
                    ForEach(exercises) { x in
                        NavigationLink(value: DetailRoute.workout(date, x.id)) {
                            WorkoutRow(exercise: x, zone: model.zone)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TrendCard(def: MetricCatalog.def("strain")!, endDate: date, color: Theme.strain)
            Text("Strain is FitStats' own 0\u{2060}–\u{2060}100 scale: 100 × (1 − e^(−TRIMP/120)), where TRIMP is Banister's training impulse from your minute heart rate (minutes above 30% of heart-rate reserve).")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }

}

struct ZoneBars: View {
    let minutes: [Double]
    /// Minutes with heart rate under 50 % of reserve (below Z1); nil hides the row.
    var below: Double? = nil

    var body: some View {
        let labels = ["Z1", "Z2", "Z3", "Z4", "Z5"]
        let ranges = ["50–60%", "60–70%", "70–80%", "80–90%", "90%+"]
        let colors: [Color] = [Theme.stress, Theme.recoveryGreen, Theme.recoveryYellow, Theme.body, Theme.recoveryRed]
        let maxValue = max(1, minutes.max() ?? 1, below ?? 0)
        VStack(spacing: 8) {
            if let below {
                bar("<50%", range: nil, value: below, color: Theme.tertiary, maxValue: maxValue)
            }
            ForEach(0..<min(5, minutes.count), id: \.self) { i in
                bar(labels[i], range: ranges[i], value: minutes[i], color: colors[i], maxValue: maxValue)
            }
        }
    }

    private func bar(_ label: String, range: String?, value: Double, color: Color, maxValue: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(Font.fs(.caption, .bold))
                if let range {
                    Text(range).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                }
            }
            .frame(width: 52, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(color)
                        .frame(width: value > 0 ? max(6, geo.size.width * CGFloat(value / maxValue)) : 0)
                }
            }
            .frame(height: 8)
            Text(Format.duration(value))
                .font(Font.fs(.caption).monospacedDigit())
                .frame(width: 64, alignment: .trailing)
        }
    }
}

// MARK: - Stress

struct StressDetailView: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.daysByDate[date]
        let value = day?.double("stress")
        let hourly = day?.json("intraday_details")?["stressHourly"]?.array?.map { $0.double }
        DetailScaffold(title: "Stress", date: date) {
            Card {
                HStack(spacing: 20) {
                    ScoreRing(title: "Stress", value: value, maxValue: 100, color: Theme.stressColor(value),
                              caption: Theme.stressLabel(value), size: 140, lineWidth: 15)
                    VStack(alignment: .leading, spacing: 6) {
                        KeyValueRow(key: "Minutes", value: Format.number(day?.double("stress_minutes")))
                        Text("Only minutes when you were awake, still and not exercising count.")
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
            if let hourly, hourly.contains(where: { $0 != nil }) {
                Card {
                    SectionHeader(title: "Through the day", subtitle: "Average stress per hour")
                    HourlyBarsChart(values: hourly, colorFor: { Theme.stressColor($0) })
                }
            }
            TrendCard(def: MetricCatalog.def("stress")!, endDate: date, color: Theme.stress)
            Text("Google Health does not provide daytime HRV, so FitStats estimates stress from how far your heart rate sits above your usual still heart rate while you are awake, still and not exercising or recovering from a workout: each minute scores 0 at or below your usual level (the median of the last 30 days) and 100 at 15% of heart-rate reserve above it. It is an estimate, not a medical measure.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
