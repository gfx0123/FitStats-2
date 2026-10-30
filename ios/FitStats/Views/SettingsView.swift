import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore
    @EnvironmentObject private var live: LiveHeartRateMonitor
    @State private var draft = UserSettings.defaults
    @State private var coachModel = ""
    @State private var useMaxHr = false
    @State private var saving = false
    @State private var exportURL: URL?
    @State private var confirmDisconnect = false
    @State private var confirmWipe = false

    private let historyOptions = [90, 180, 365, 730, 1095, 1825, 3650]

    var body: some View {
        NavigationStack {
            List {
                Group {
                    accountSection
                    syncSection
                    deviceSection
                    appearanceSection
                    liveSection
                    remindersSection
                    widgetsSection
                    preferencesSection
                    coachSection
                    dataSection
                    dangerSection
                    aboutSection
                }
                .listRowBackground(GlassRow())
            }
            .screenBackground()
            .navigationTitle("Settings")
            .swipeBackFromAnywhere()
            .onAppear(perform: loadDraft)
            // Saving the wake-up times (their own screen) leaves unsaved preferences alone.
            .onChange(of: model.status.map(\.settings.withoutWakeTimes)) { _, _ in loadDraft() }
            .task { if coach.status == nil { await coach.refresh() } }
            .onChange(of: coach.status?.model) { _, new in coachModel = new ?? "" }
            .confirmationDialog("Disconnect Google?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await model.disconnect(wipe: false) } }
            } message: {
                Text("The server stops syncing and this app signs out. Your stored history is kept.")
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { Task { await model.disconnect(wipe: true) } }
            } message: {
                Text("Removes every synced day, sleep and workout, your journal and coach chats, and the Google connection from your Supabase database. This cannot be undone.")
            }
        }
    }

    private func loadDraft() {
        guard let s = model.status?.settings else { return }
        draft = s
        useMaxHr = s.maxHrOverride != nil
    }

    // MARK: sections

    @ViewBuilder private var coachSection: some View {
        Section {
            NavigationLink {
                CoachPickerView()
            } label: {
                HStack(spacing: 12) {
                    CoachCharacter(persona: coach.persona, size: 40, animated: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your coach: \(coach.persona.name)")
                        Text(coach.persona.tagline).font(Font.fs(.caption)).foregroundStyle(coach.persona.color)
                    }
                }
            }
            .accessibilityIdentifier("settings-coach")
            if let status = coach.status {
                KeyValueRow(key: "Claude API key", value: status.configured ? "Added" : "Missing",
                            color: status.configured ? Theme.recoveryGreen : Theme.recoveryYellow)
                Picker("Model", selection: $coachModel) {
                    ForEach(status.models) { m in Text(m.label).tag(m.id) }
                }
                .onChange(of: coachModel) { _, new in
                    guard !new.isEmpty, new != coach.status?.model else { return }
                    Task { await coach.setModel(new) }
                }
                if let note = status.models.first(where: { $0.id == coachModel })?.note {
                    Text(note).font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
                }
                if let u = status.usage {
                    KeyValueRow(key: "This month", value: "\(u.requests) API calls · \(costText(u.costUsd))")
                    KeyValueRow(key: "Tokens", value: "\(Format.number(Double(u.input + u.cacheRead + u.cacheWrite))) in · \(Format.number(Double(u.output))) out")
                }
                Text("Cost is estimated from Anthropic's list prices; the Anthropic Console shows your actual bill. The coach answers at most \(status.dailyLimit ?? 100) messages a day.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            } else {
                Text("Loading…").foregroundStyle(Theme.secondary)
            }
        }
        } header: {
            SettingsHeader("Coach", icon: "sparkles", color: Theme.sleep)
        }
        .onAppear { coachModel = coach.status?.model ?? "" }
    }

    private func costText(_ usd: Double) -> String {
        if usd > 0 && usd < 0.01 { return "under $0.01" }
        return String(format: "$%.2f", usd)
    }

    private var accountSection: some View {
        Section {
            KeyValueRow(key: "Account", value: model.status?.connection.email ?? "–")
            KeyValueRow(key: "Status", value: connectionText, color: connectionColor)
            if let missing = model.status?.connection.missingScopes, !missing.isEmpty {
                Text("Missing permissions: \(missing.joined(separator: ", "))")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.recoveryYellow)
            }
            if let error = model.status?.connection.error, model.needsReconnect {
                Text(error).font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
            }
            Button(model.needsReconnect ? "Reconnect Google" : "Re-authorise Google") {
                Task { await model.connect() }
            }
        } header: {
            SettingsHeader("Google Health", icon: "heart.text.square.fill", color: Theme.heart)
        }
    }

    private var connectionText: String {
        switch model.status?.connection.status {
        case "ok": return "Connected"
        case "expired": return "Expired — reconnect"
        case "error": return "Error"
        case "disconnected": return "Disconnected"
        default: return "Unknown"
        }
    }

    private var connectionColor: Color {
        model.status?.connection.status == "ok" ? Theme.recoveryGreen : Theme.recoveryRed
    }

    private var syncSection: some View {
        Section {
            KeyValueRow(key: "Updated from Google", value: Format.relative(model.status?.sync.lastRecentSyncAt))
            KeyValueRow(key: "Last run", value: "\(Format.relative(model.status?.sync.lastRunAt)) · \(model.status?.sync.lastRunStatus ?? "–")")
            if let sync = model.status?.sync {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("History import").foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(sync.backfillDone ? "Complete" : "\(Int(((sync.backfillProgress ?? 0) * 100).rounded()))%")
                    }
                    .font(Font.fs(.subheadline))
                    ProgressView(value: sync.backfillDone ? 1 : (sync.backfillProgress ?? 0)).tint(Theme.strain)
                    if let oldest = sync.backfillOldest {
                        Text("Imported back to \(Format.shortDay(oldest))").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
            Button {
                Task { await model.syncNow() }
            } label: {
                HStack {
                    Label(model.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                    if model.isSyncing { Spacer(); ProgressView() }
                }
            }
            .disabled(model.isSyncing)
            Text("The server checks Google for new data every 5 minutes, even when this app is closed, and again whenever you open it or pull to refresh. Your band's data only reaches Google after the band syncs with the Google Health app on your phone.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        } header: {
            SettingsHeader("Sync", icon: "arrow.triangle.2.circlepath", color: Theme.recoveryGreen)
        }
    }

    @ViewBuilder private var deviceSection: some View {
        if let devices = model.status?.devices, !devices.isEmpty {
            Section {
                ForEach(devices) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.name ?? "Fitbit device").font(Font.fs(.subheadline, .semibold))
                        HStack(spacing: 12) {
                            if let level = d.batteryLevel {
                                Label("\(level)%", systemImage: batteryIcon(level))
                            } else if let status = d.batteryStatus {
                                Label(status, systemImage: "battery.50")
                            }
                            Text("Synced \(Format.relative(d.lastSyncTime))")
                        }
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                    }
                }
            } header: {
                SettingsHeader("Devices", icon: "applewatch", color: Theme.stress)
            }
        }
    }

    @AppStorage(AppBackground.natureKey) private var natureBackground = true

    private var appearanceSection: some View {
        Section {
            Toggle(isOn: $natureBackground) {
                Label("Nature background", systemImage: "mountain.2.fill")
            }
            .accessibilityIdentifier("settings-nature")
        } header: {
            SettingsHeader("Appearance", icon: "paintpalette.fill", color: Theme.body)
        } footer: {
            Text(natureBackground
                 ? "A calm, slowly moving landscape whose sky follows the time of day. It stands still when Reduce Motion is on."
                 : "Off: a plain grey background.")
        }
    }

    @AppStorage(Reminders.bedtimeKey) private var bedtimeReminder = false
    @AppStorage(Reminders.bedtimeLeadKey) private var bedtimeLead = Reminders.defaultLead
    @AppStorage(Reminders.journalKey) private var journalReminder = false
    @AppStorage(Reminders.journalTimeKey) private var journalTime = Reminders.defaultJournalTime

    private var remindersSection: some View {
        Section {
            ReminderToggle("Bedtime reminder", key: Reminders.bedtimeKey)
            if bedtimeReminder {
                Picker("Remind me", selection: $bedtimeLead) {
                    ForEach(Reminders.leadChoices, id: \.self) { Text("\($0) min before").tag($0) }
                }
                .onChange(of: bedtimeLead) { _, _ in Task { await Reminders.update(model) } }
            }
            ReminderToggle("Weekly summary (Sunday 7 PM)", key: Reminders.weeklyKey)
            ReminderToggle("Journal reminder", key: Reminders.journalKey)
            if journalReminder {
                DatePicker("At", selection: journalTimeBinding, displayedComponents: .hourAndMinute)
                    .onChange(of: journalTime) { _, _ in Task { await Reminders.update(model) } }
            }
        } header: {
            SettingsHeader("Reminders", icon: "bell.fill", color: Theme.recoveryYellow)
        } footer: {
            Text("The bedtime reminder comes before tonight's In bed by time from the Tonight plan. It is set again each time FitStats refreshes; for nights after that it uses an estimate until you open the app. The weekly summary is written by your server on Sunday evening; the reminder opens it. The journal reminder skips days you've already logged.")
        }
    }

    private var journalTimeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: journalTime / 60, minute: journalTime % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                journalTime = (c.hour ?? 21) * 60 + (c.minute ?? 30)
            }
        )
    }

    private var liveSection: some View {
        Section {
            Toggle("Live heart rate", isOn: $live.enabled)
        } header: {
            SettingsHeader("Live heart rate", icon: "waveform.path.ecg", color: Theme.heart)
        } footer: {
            Text(live.enabled
                 ? "FitStats connects to your Fitbit Air over Bluetooth while the live card or screen is open. Your band buzzes when FitStats connects and when it lets go, such as when you open or close the app."
                 : "Off: FitStats doesn't use Bluetooth, and the live card and the heart button on Today are hidden. Your band won't buzz because of FitStats.")
        }
    }

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var widgetsSection: some View {
        Section {
            NavigationLink {
                WidgetsView()
            } label: {
                Label("Home Screen widgets", systemImage: "square.grid.2x2.fill")
            }
            .accessibilityIdentifier("settings-widgets")
        } header: {
            SettingsHeader("Widgets", icon: "square.grid.2x2.fill", color: Theme.strain)
        }
    }

    private var preferencesSection: some View {
        Section {
            Picker("Sex (for training load)", selection: $draft.sex) {
                Text("Not set").tag("unspecified")
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            Stepper("Sleep need: \(Format.duration(Double(draft.sleepNeedMin)))", value: $draft.sleepNeedMin, in: 300...720, step: 15)
            NavigationLink {
                WakeTimesView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake-up times")
                    Text(WakeTimesView.summary(model.wakeTimes) ?? "Not set: the times you usually wake up")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .accessibilityIdentifier("settings-wake-times")
            Stepper("Step goal: \(Format.number(Double(draft.stepGoal)))", value: $draft.stepGoal, in: 1000...50000, step: 500)
            Toggle("Set max heart rate manually", isOn: $useMaxHr)
            if useMaxHr {
                Stepper("Max HR: \(draft.maxHrOverride ?? 190) bpm",
                        value: Binding(get: { draft.maxHrOverride ?? 190 }, set: { draft.maxHrOverride = $0 }),
                        in: 120...230)
            }
            Picker("History to import", selection: $draft.backfillDays) {
                ForEach(historyOptions, id: \.self) { days in
                    Text(days >= 365 ? "\(days / 365) year\(days >= 730 ? "s" : "")" : "\(days) days").tag(days)
                }
            }
            Button {
                saving = true
                var toSave = draft
                if !useMaxHr { toSave.maxHrOverride = nil } else if toSave.maxHrOverride == nil { toSave.maxHrOverride = 190 }
                Task {
                    _ = await model.saveSettings(toSave)
                    saving = false
                }
            } label: {
                HStack {
                    Text("Save preferences")
                    if saving { Spacer(); ProgressView() }
                }
            }
            .disabled(saving || model.status == nil)
        } header: {
            SettingsHeader("Preferences", icon: "slider.horizontal.3", color: Theme.strain)
        } footer: {
            Text(maxHrText)
        }
    }

    /// The max heart rate in use and where it came from (status "maxHr"; older servers don't send it).
    private var maxHrText: String {
        let age = model.status?.profile.age.map { "age \($0)" } ?? "age unknown"
        guard let hr = model.status?.maxHr else {
            return "Without a manual value, max heart rate is the higher of 208 − 0.7 × age (\(age)) and the highest heart rate you have sustained in the last year."
        }
        let bpm = "\(Int(hr.value.rounded())) bpm"
        switch hr.source {
        case "override": return "Max heart rate in use: \(bpm), set by you."
        case "observed": return "Max heart rate in use: \(bpm), the highest heart rate you have sustained in the last year, which is above the 208 − 0.7 × age estimate (\(age))."
        default: return "Max heart rate in use: \(bpm), estimated as 208 − 0.7 × age (\(age)). It rises automatically if you sustain a higher heart rate."
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink { ScoreInfoView() } label: { Label("How the scores work", systemImage: "function") }
            Button { exportURL = model.csvExport() } label: { Label("Prepare CSV export", systemImage: "tablecells") }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            SettingsHeader("Data", icon: "externaldrive.fill", color: Theme.stageRem)
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Disconnect Google", role: .destructive) { confirmDisconnect = true }
            Button("Delete all synced data", role: .destructive) { confirmWipe = true }
        }
    }

    private var aboutSection: some View {
        Section {
            KeyValueRow(key: "App", value: appVersion)
            KeyValueRow(key: "Server", value: model.status?.version ?? "–")
            Text(model.baseURL.absoluteString).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        } header: {
            SettingsHeader("About", icon: "info.circle.fill", color: Theme.secondary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}

/// A Settings section title with its icon in a small coloured tile.
struct SettingsHeader: View {
    let title: String
    let icon: String
    let color: Color

    init(_ title: String, icon: String, color: Color) {
        self.title = title
        self.icon = icon
        self.color = color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(Font.fredoka(11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.2)))
            Text(title)
        }
    }
}

/// A list row's background: frosted glass like the cards.
struct GlassRow: View {
    var body: some View {
        Rectangle().fill(.ultraThinMaterial).overlay(Rectangle().fill(Theme.card))
    }
}

struct ScoreInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                info("Recovery (0–100%)", Theme.recoveryGreen, """
                Compares last night with your own previous 30 nights. HRV 45% (log RMSSD as a z-score, 50 + 25·z), \
                resting heart rate 25% (lower than usual scores higher), sleep score 20%, and vitals 10% \
                (skin temperature and breathing rate lose points when they are more than one standard deviation \
                from your baseline). It needs 5 nights of history and either HRV or resting heart rate.
                """)
                info("Strain (0–100)", Theme.strain, """
                Built from your minute-by-minute heart rate. Each minute above 30% of your heart-rate reserve adds \
                Banister TRIMP = HRR × a × e^(b × HRR) (a = 0.64, b = 1.92, or 0.86 / 1.67 if set to female). \
                Strain = 100 × (1 − e^(−TRIMP / 120)), so it climbs quickly at first and flattens near 100. \
                A single minute more than 30 bpm above both neighbours is a sensor glitch and is smoothed first. \
                The goal band comes from your recovery: 55–80 when green, 35–60 when yellow, 10–35 when red.
                """)
                info("Max heart rate", Theme.heart, """
                Heart-rate reserve runs from your resting heart rate to your max heart rate. Unless you set it \
                yourself, the max is the higher of 208 − 0.7 × age and the highest heart rate you have sustained \
                in the last year (a minute average with the minute next to it at most 15 bpm lower, so a \
                one-minute spike doesn't count). When it changes by 2 bpm or more, your history is recomputed.
                """)
                info("Sleep score (0–100)", Theme.sleep, """
                Duration 50% (time asleep ÷ your sleep need), efficiency 15% (time asleep ÷ the sleep period: \
                85% → 0, 98% → 100; Fitbit's sleep period starts when it detects you settling, so most nights \
                are 92–99%), deep + REM 20% (full marks at 15% deep and 20% REM), consistency 15% (bed and \
                wake time compared with your 14-night median; 2 hours off scores 0).
                """)
                info("Sleep details", Theme.sleep, """
                A day's sleep numbers come from one session: a night rather than a nap, then the one Google \
                marks as main sleep, then the longest. Every other session that day counts as a nap. \
                Awakenings are the times you were awake after first falling asleep and before the final \
                wake-up; "Awake after falling asleep" is their minutes. Time to fall asleep is the awake \
                stretch at the start of the night when Google reports none.
                """)
                info("Stress (0–100)", Theme.stress, """
                Google Health does not offer daytime HRV, so stress is estimated from heart rate. A minute counts \
                when you are awake, still (no steps in it or the 3 minutes before, and sedentary in Fitbit's \
                minute data when it has that) and not exercising or recovering from a workout (until your heart \
                rate is back near its level before the workout, 30–180 minutes after). Each minute scores 0 at \
                or below your usual still heart rate (the median of the last 30 days; until there are 7 days, \
                14% of heart-rate reserve above resting) and 100 at 15% of reserve above it. The day's stress \
                is the average: under 25 low, 25–49 moderate, 50–74 high, 75 or more very high.
                """)
                info("Tonight (sleep plan)", Theme.sleep, """
                Need tonight = your sleep need setting (Base), plus 0–45 minutes for the day's strain (nothing \
                at 35 or less, 45 minutes at 85 or more), plus a quarter of your last 7 nights' sleep debt (at \
                most an hour; naps on earlier days count as sleep), minus today's naps (at most an hour). \
                Time in bed = need ÷ your typical sleep efficiency \
                (median of 14 nights). Bedtime = your usual wake time for tomorrow's kind of day (weekday or \
                weekend, median of 28 nights) minus the time in bed.
                """)
                info("Journal effects", Theme.stress, """
                For each tag, the night and morning after tagged days (sleep score, time asleep, HRV, resting \
                heart rate, recovery) are compared with the night and morning after your other logged days. \
                "Nothing to note" counts as logged. A tag needs 3 logged days with it and 3 without. A \
                difference is "clear" when Welch's t is 2 or more, i.e. larger than your usual night-to-night \
                variation. It shows a pattern, not a cause.
                """)
                info("Partial and low-wear days", Theme.recoveryYellow, """
                Today's steps, calories and other day totals are still growing, so they are shown "so far" and \
                not compared with full days; Trends' 7D, 30D and longer ranges for day totals cover complete \
                days before today. Steps are compared with what you usually have by the same time. A finished \
                day is incomplete when the band recorded under 60% of your usual wear time (the median of your \
                worn days among the previous 30), or under 10 hours while you have fewer than 5 worn days. A \
                day without any minute heart rate (say, before you had the band) is incomplete once the band \
                has been worn. Incomplete days' totals stay visible but are left out of averages, records, \
                trends and correlations.
                """)
                info("Workouts", Theme.strain, """
                Peak minute HR is the highest one-minute average, after smoothing one-minute sensor spikes. \
                When Google's step count for a workout is missing or implies more than a metre per step, the \
                minute steps over the workout are shown instead (marked ≈). When under 70% of a workout has \
                heart rate, its strain and zones cover only those minutes and are marked partial.
                """)
                Text("These are FitStats' own transparent formulas. They are not Bevel's or Fitbit's scores (both are proprietary), and they are not medical advice.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("How scores work")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func info(_ title: String, _ color: Color, _ text: String) -> some View {
        Card {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(Font.fs(.headline))
            }
            Text(text).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
        }
    }
}
