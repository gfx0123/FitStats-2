import SwiftUI

/// Settings → Wake-up times: when you have to be up each morning, set by hand. Tonight's plan
/// (In bed by), the bedtime reminder and the coach use the time of the next morning; a morning
/// without one is free to sleep in, and the plan uses the time you usually wake up on that kind
/// of day, from your band.
struct WakeTimesView: View {
    /// In a sheet (from the Tonight card): saving closes it.
    var closesOnSave = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var times: [Int?] = Self.none
    @State private var loaded = false
    @State private var saving = false
    @State private var saved = false

    static let none: [Int?] = Array(repeating: nil, count: 7)
    static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let shortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        List {
            Section {
                ForEach(0..<7, id: \.self) { row($0) }
            } header: {
                Text("Up at, each morning")
            } footer: {
                Text("When you have to be up. Tonight's In bed by time, the bedtime reminder and the coach use the time for the next morning. Switch a morning off when you can sleep in: FitStats then uses the time you usually wake up, and the coach knows it's a morning to catch up on sleep.")
            }
            Section {
                Button("Use Monday's time Tuesday to Friday") {
                    for i in 1...4 { times[i] = times[0] }
                    saved = false
                }
                .disabled(times[0] == nil || (1...4).allSatisfy { times[$0] == times[0] })
                .accessibilityIdentifier("wake-copy-weekdays")
                Button("Clear all", role: .destructive) {
                    times = Self.none
                    saved = false
                }
                .disabled(times == Self.none)
            }
            Section {
                KeyValueRow(key: "Weekdays", value: usualText(weekend: false))
                KeyValueRow(key: "Weekends", value: usualText(weekend: true))
            } header: {
                Text("You usually wake up")
            } footer: {
                Text("From your band: the middle of the last 28 mornings of each kind. Used for mornings without a time.")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text("Save wake-up times")
                        Spacer()
                        if saving {
                            ProgressView()
                        } else if saved {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.recoveryGreen)
                        }
                    }
                }
                .disabled(saving || !changed || model.status == nil)
                .accessibilityValue(saved ? "Saved" : saving ? "Saving" : "")
                .accessibilityIdentifier("wake-save")
            } footer: {
                Text(tonightText)
            }
        }
        .screenBackground()
        .navigationTitle("Wake-up times")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            times = model.wakeTimes ?? Self.none
            loaded = true
        }
    }

    private var changed: Bool { times != (model.wakeTimes ?? Self.none) }

    private func row(_ i: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dayNames[i])
                if times[i] == nil {
                    Text("Free: sleep in").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 8)
            if times[i] != nil {
                DatePicker(Self.dayNames[i], selection: timeBinding(i), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityIdentifier("wake-time-\(i)")
            }
            Toggle(Self.dayNames[i], isOn: Binding(get: { times[i] != nil }, set: { on in
                times[i] = on ? (times[i] ?? startTime(i)) : nil
                saved = false
            }))
            .labelsHidden()
            .tint(Theme.sleep)
            .accessibilityIdentifier("wake-toggle-\(i)")
        }
    }

    private func timeBinding(_ i: Int) -> Binding<Date> {
        Binding(
            get: {
                let m = times[i] ?? 7 * 60
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                times[i] = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                saved = false
            }
        )
    }

    /// A morning switched on starts at the nearest earlier morning's time of the same kind
    /// (weekday or weekend), else the time you usually wake up then, else 07:00.
    private func startTime(_ i: Int) -> Int {
        let weekend = i >= 5
        if let near = (0..<i).reversed().first(where: { ($0 >= 5) == weekend && times[$0] != nil }), let t = times[near] { return t }
        if let usual = SleepPlan.usualWake(days: model.daysByDate, today: model.today, weekendMorning: weekend) {
            return Int((usual.wakeMin / 5).rounded()) * 5
        }
        return 7 * 60
    }

    private func usualText(weekend: Bool) -> String {
        SleepPlan.usualWake(days: model.daysByDate, today: model.today, weekendMorning: weekend).map { Format.clock($0.wakeMin) }
            ?? "Not known yet"
    }

    /// Tonight's plan with the times on screen, saved or not.
    private var tonightText: String {
        let plan = SleepPlan.plan(days: model.daysByDate, today: model.today,
                                  sleepNeedMin: Double(model.status?.settings.sleepNeedMin ?? 480), wakeTimes: times)
        let tomorrow = Self.dayNames[SleepPlan.weekdayIndex(Format.addDays(model.today, 1))]
        guard let bed = plan.bedtimeMin, let wake = plan.wakeMin else {
            return "Tonight: no bedtime yet. Set a time for \(tomorrow), or wear the band for 3 nights."
        }
        let source = plan.wakeBasis == .set ? "your \(tomorrow) time" : "\(tomorrow) is free, so your usual time"
        return "Tonight: in bed by \(Format.clock(bed)) to be up at \(Format.clock(wake)) (\(source)), for \(Format.duration(plan.needMin)) of sleep."
    }

    private func save() async {
        saving = true
        let ok = await model.saveWakeTimes(times)
        saving = false
        saved = ok
        if ok { Haptics.success() }
        if ok && closesOnSave { dismiss() }
    }

    /// "Mon–Fri 06:30 · Sat 09:00 · Sun free", or nil when none are set.
    static func summary(_ times: [Int?]?) -> String? {
        guard let times, times.count == 7, times.contains(where: { $0 != nil }) else { return nil }
        var parts: [String] = []
        var start = 0
        while start < 7 {
            var end = start
            while end + 1 < 7 && times[end + 1] == times[start] { end += 1 }
            let days = end == start ? shortNames[start] : end == start + 1 ? "\(shortNames[start]), \(shortNames[end])" : "\(shortNames[start])–\(shortNames[end])"
            parts.append("\(days) \(times[start].map { Format.clock(Double($0)) } ?? "free")")
            start = end + 1
        }
        return parts.joined(separator: " · ")
    }
}
