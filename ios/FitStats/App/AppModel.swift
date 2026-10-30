import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var appKey: String?
    @Published private(set) var status: StatusResponse?
    @Published private(set) var days: [DayRecord] = [] {
        didSet {
            daysByDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
            recorded = Set(MetricCatalog.all.filter { def in days.contains { def.value($0) != nil } }.map(\.key))
        }
    }
    @Published private(set) var daysByDate: [String: DayRecord] = [:]
    /// Metrics with at least one value in your history; tiles for the others stay hidden.
    @Published private(set) var recorded: Set<String> = []
    @Published private(set) var journal: [String: JournalEntry] = [:]
    @Published private(set) var journalTags: [JournalTag] = []
    /// Days whose detail (minute data, sessions) failed to load, so screens stop showing a spinner.
    @Published private(set) var failedDays: Set<String> = []
    @Published private(set) var stats: StatsPayload?
    @Published private(set) var dayDetails: [String: DayDetail] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published var connectMessage: String?
    @Published var noticeMessage: String?

    let baseURL: URL
    let coach = CoachStore()
    /// The workout being logged in the Training tab.
    let workout = ActiveWorkout()
    @Published private(set) var routines: [Routine] = []
    /// Logged in the app over the last year, newest first.
    @Published private(set) var workoutLogs: [WorkoutLog] = []
    /// The band's workouts of the last 120 days, for the Training tab's history.
    @Published private(set) var bandWorkouts: [Exercise] = []
    /// Logged workout id → the band's recording of the same session (WorkoutPairing).
    var workoutPairs: [String: Exercise] { WorkoutPairing.pairs(logs: workoutLogs, band: bandWorkouts) }
    /// Which muscles exercises work (with the training data from server 1.8.0).
    @Published private(set) var library = ExerciseLibrary.empty
    @Published var trainingError: String?
    /// Text for the Coach's message field, from an "Ask coach" button elsewhere in the app.
    @Published var coachDraft: String?
    private let authenticator = WebAuthenticator()
    private var lastRefresh: Date?
    private var lastSyncRequest: Date?
    /// API-shaped JSON used instead of the server for CI screenshots (see supabase/tests/make-fixtures.ts).
    private let fixtureDir: URL?
    /// CI screenshots with fixture data: nothing is fetched or scheduled.
    var isFixture: Bool { fixtureDir != nil }
    /// A tapped journal reminder: Today opens this day's journal.
    @Published var journalRequest: String?
    /// A tapped weekly-summary reminder: the Coach opens the week's summary.
    @Published var weeklyRequest = false
    /// A tapped Home Screen widget: the tab it opens ("today", "coach"…).
    @Published var tabRequest: String?
    /// Trends (with Insights), opened as a sheet from Today.
    @Published var showTrends = false
    /// Redraws the widgets when a new brief from the coach arrives.
    private var briefWatch: AnyCancellable?

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "FitStatsServerURL") as? String
        baseURL = URL(string: configured ?? "https://zkxnbcrayjwkeyxlungk.supabase.co/functions/v1/fitstats")!
        let fixtures = ProcessInfo.processInfo.environment["FITSTATS_FIXTURES"] ?? ""
        fixtureDir = fixtures.isEmpty ? nil : URL(fileURLWithPath: fixtures)
        coach.apiProvider = { [weak self] in self?.api }
        coach.onUnauthorized = { [weak self] in
            self?.signOutLocally()
            self?.connectMessage = "This app key is no longer valid. Connect Google again."
        }
        // The coach changed something: reload that part (settings and the journal come with
        // the rest of the data, and change the scores and statistics).
        coach.onDataChanged = { [weak self] what in
            Task {
                guard let self else { return }
                if what == "training" || what == "all" { await self.refreshTraining() }
                if what != "training" { await self.refreshAll(force: true) }
            }
        }
        if let fixtureDir {
            appKey = "fixture"
            loadFixtures()
            coach.loadFixtures(from: fixtureDir)
            return
        }
        appKey = KeyStore.read()
        if appKey != nil { loadCache() }
        updateWidgets()
        briefWatch = coach.$brief.removeDuplicates().dropFirst().sink { [weak self] _ in
            // After the new value is set (@Published sends before it changes).
            DispatchQueue.main.async { self?.updateWidgets() }
        }
    }

    private func loadFixtures() {
        guard let dir = fixtureDir else { return }
        func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            do {
                let data = try Data(contentsOf: dir.appendingPathComponent(name))
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                errorMessage = "Fixture \(name): \(error)"
                return nil
            }
        }
        status = load(StatusResponse.self, "status.json")
        days = load(DaysResponse.self, "days.json")?.days ?? []
        stats = load(StatsPayload.self, "stats.json")
        if let j = load(JournalResponse.self, "journal.json") { applyJournal(j) }
        if let t = load(TrainingResponse.self, "training.json") { applyTraining(t) }
        for offset in 0..<7 {
            let date = Format.addDays(today, -offset)
            if let detail = load(DayDetail.self, "day-\(date).json") { dayDetails[date] = detail }
        }
    }

    private var api: APIClient? { appKey.map { APIClient(baseURL: baseURL, key: $0) } }

    var today: String { status?.today ?? Format.localToday() }

    var zone: TimeZone? { status?.timeZone.flatMap(TimeZone.init(identifier:)) }

    var needsReconnect: Bool {
        guard let s = status?.connection.status else { return false }
        return s == "expired" || s == "error" || s == "disconnected"
    }

    /// The band among the paired devices. Its `lastSyncTime` is when it last synced with the
    /// phone app (Google Health, formerly Fitbit): nothing it recorded after that can be at
    /// Google yet.
    var band: StatusResponse.Device? {
        let devices = status?.devices ?? []
        return devices.first { $0.type == "TRACKER" } ?? devices.first
    }

    // MARK: - Cache

    private func loadCache() {
        let decoder = JSONDecoder()
        if let d = DiskCache.load("status.json"), let s = try? decoder.decode(StatusResponse.self, from: d) { status = s }
        if let d = DiskCache.load("days.json"), let r = try? decoder.decode(DaysResponse.self, from: d) { days = r.days }
        if let d = DiskCache.load("stats.json"), let s = try? decoder.decode(StatsPayload.self, from: d) { stats = s }
        if let d = DiskCache.load("journal.json"), let j = try? decoder.decode(JournalResponse.self, from: d) { applyJournal(j) }
        if let d = DiskCache.load("training.json"), let t = try? decoder.decode(TrainingResponse.self, from: d) { applyTraining(t) }
    }

    // MARK: - Connect

    func connect() async {
        connectMessage = nil
        let url = APIClient.url(base: baseURL, route: "connect", query: ["app_redirect": "fitstats://connected"])
        do {
            let callback = try await authenticator.start(url: url, callbackScheme: "fitstats")
            handleCallback(callback)
        } catch {
            if let e = error as? URLError, e.code == .cancelled { return }
            let ns = error as NSError
            if ns.domain == "com.apple.AuthenticationServices.WebAuthenticationSession", ns.code == 1 { return } // user cancelled
            connectMessage = "Could not open Google sign-in: \(error.localizedDescription)"
        }
    }

    /// Handles `fitstats://connected?...` from the sign-in sheet (or Safari, via onOpenURL).
    func handleCallback(_ url: URL) {
        guard url.scheme == "fitstats" else { return }
        // fitstats://open?tab=coach from a Home Screen widget.
        if url.host == "open" {
            let tab = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "tab" }?.value
            tabRequest = tab ?? "today"
            return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        if let error = value("error") {
            connectMessage = value("message") ?? "Google sign-in failed (\(error))."
            return
        }
        guard let key = value("key"), key.count >= 20 else {
            connectMessage = "The server did not return an app key. Try again."
            return
        }
        KeyStore.save(key)
        appKey = key
        connectMessage = nil
        if let missing = value("missing_scopes"), !missing.isEmpty {
            noticeMessage = "Some Google Health permissions were not granted (\(missing)). Those numbers will stay empty until you reconnect and allow them."
        } else {
            noticeMessage = "Connected. The first sync downloads your history in the background; it can take a while."
        }
        Task { await refreshAll(force: true) }
    }

    // MARK: - Loading

    /// Reloads status, days and stats from the server. `full` refetches the whole history
    /// (otherwise only the last 10 days, plus the whole history when the import has moved or
    /// every 12 h). Afterwards, starts a sync with Google if the server's copy is stale.
    func refreshAll(force: Bool = false, full: Bool = false) async {
        if fixtureDir != nil { return }
        guard let api else { return }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 20 { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (s, sData) = try await api.fetch(StatusResponse.self, "status")
            status = s
            DiskCache.save(sData, as: "status.json")
            let defaults = UserDefaults.standard
            let lastFull = defaults.double(forKey: "lastFullDaysFetch")
            let importMoved = s.sync.backfillOldest != defaults.string(forKey: "fullFetchBackfillOldest")
            let needFull = full || importMoved || days.isEmpty || Date().timeIntervalSince1970 - lastFull > 12 * 3600
            let from = needFull
                ? Format.addDays(s.today, -min(max(s.settings.backfillDays, 90), 1825))
                : Format.addDays(s.today, -10)
            let (d, dData) = try await api.fetch(DaysResponse.self, "days", query: ["from": from, "to": s.today])
            if needFull {
                days = d.days
                DiskCache.save(dData, as: "days.json")
                defaults.set(Date().timeIntervalSince1970, forKey: "lastFullDaysFetch")
                defaults.set(s.sync.backfillOldest, forKey: "fullFetchBackfillOldest")
            } else {
                var merged = days.filter { $0.date < from }
                merged.append(contentsOf: d.days)
                days = merged
                if let all = try? JSONEncoder().encode(DaysResponse(from: merged.first?.date ?? from, to: s.today, today: s.today, days: merged)) {
                    DiskCache.save(all, as: "days.json")
                }
            }
            if let result = try? await api.fetch(StatsPayload.self, "stats") {
                stats = result.0
                DiskCache.save(result.1, as: "stats.json")
            }
            if let result = try? await api.fetch(JournalResponse.self, "journal") {
                applyJournal(result.0)
                DiskCache.save(result.1, as: "journal.json")
            }
            await syncHomeLayout()
            await refreshTraining()
            // Today's minute data grows with every sync. Replace it rather than drop it: the Today
            // screen only loads a day when it appears, so a dropped detail never came back.
            if let result = try? await api.fetch(DayDetail.self, "day", query: ["date": s.today]) {
                dayDetails[s.today] = result.0
                failedDays.remove(s.today)
            }
            lastRefresh = Date()
            errorMessage = nil
            await Reminders.update(self)
            updateWidgets()
        } catch {
            handle(error)
            return
        }
        if let s = status, autoSyncDue(s) {
            Task { await syncNow() }
        }
    }

    /// True when the server last fetched recent data from Google over 3 minutes ago
    /// (cron runs every 5), and no sync was asked for in the last 3 minutes.
    private func autoSyncDue(_ s: StatusResponse) -> Bool {
        guard !isSyncing, s.connection.status == "ok" else { return false }
        if let last = lastSyncRequest, Date().timeIntervalSince(last) < 180 { return false }
        guard let fetched = Format.timestamp(s.sync.lastRecentSyncAt) else { return true }
        let now = Format.timestamp(s.serverTime) ?? Date()
        return now.timeIntervalSince(fetched) > 180
    }

    @discardableResult
    func loadDay(_ date: String, force: Bool = false) async -> DayDetail? {
        if fixtureDir != nil { return dayDetails[date] }
        if !force, let cached = dayDetails[date], date != today { return cached }
        guard let api else { return nil }
        do {
            let (detail, _) = try await api.fetch(DayDetail.self, "day", query: ["date": date])
            dayDetails[date] = detail
            failedDays.remove(date)
            return detail
        } catch {
            if !error.isCancellation { failedDays.insert(date) }
            handle(error)
            return dayDetails[date]
        }
    }

    /// Asks the server to fetch the latest data from Google now, then reloads as soon as the
    /// recent days are saved (the server finishes those before any history import).
    func syncNow() async {
        guard fixtureDir == nil, let api, !isSyncing else { return }
        isSyncing = true
        lastSyncRequest = Date()
        defer { isSyncing = false }
        let before = status?.sync.lastRecentSyncAt
        do {
            _ = try await api.post("sync")
            let started = Date()
            while Date().timeIntervalSince(started) < 60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                let (s, data) = try await api.fetch(StatusResponse.self, "status")
                status = s
                DiskCache.save(data, as: "status.json")
                // A run already in progress (cron) makes the server skip this request; its own
                // recent sync, or its end, is just as good.
                if s.sync.lastRecentSyncAt != before || !s.sync.running { break }
            }
            await refreshAll(force: true)
        } catch {
            handle(error)
        }
    }

    /// Pull to refresh: a sync with Google, or a reload while one is already running. It runs in
    /// its own task, so it finishes (and reloads the screen) even if SwiftUI ends the gesture early.
    func pullToRefresh() async {
        await Task {
            if isSyncing { await refreshAll(force: true) } else { await syncNow() }
        }.value
    }

    func saveSettings(_ settings: UserSettings) async -> Bool {
        guard let api else { return false }
        do {
            let body = try JSONEncoder().encode(settings)
            _ = try await api.post("settings", body: body)
            noticeMessage = "Settings saved. Scores are being recalculated."
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await refreshAll(force: true, full: true)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func disconnect(wipe: Bool) async {
        if let api {
            _ = try? await api.post("disconnect", query: wipe ? ["wipe": "true"] : [:])
        }
        signOutLocally()
    }

    func signOutLocally() {
        KeyStore.delete()
        DiskCache.clear()
        UserDefaults.standard.removeObject(forKey: "lastFullDaysFetch")
        UserDefaults.standard.removeObject(forKey: "fullFetchBackfillOldest")
        lastSyncRequest = nil
        appKey = nil
        status = nil
        days = []
        stats = nil
        journal = [:]
        journalTags = []
        dayDetails = [:]
        failedDays = []
        routines = []
        workoutLogs = []
        bandWorkouts = []
        coach.reset()
        updateWidgets()
    }

    private func handle(_ error: Error) {
        if error.isCancellation { return }
        if case APIError.unauthorized = error {
            signOutLocally()
            connectMessage = "This app key is no longer valid. Connect Google again."
        } else {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived data

    /// False for day totals of today (still growing) and of days you barely wore the band.
    func countsToward(_ def: MetricDef, _ day: DayRecord) -> Bool {
        !def.isDayTotal || (day.date < today && day.bool("low_wear") != true)
    }

    func series(_ def: MetricDef, from: String, through: String) -> [DayPoint] {
        days.compactMap { day in
            guard day.date >= from, day.date <= through, countsToward(def, day) else { return nil }
            guard let v = def.value(day), let date = Format.chartDate(day.date) else { return nil }
            return DayPoint(date: date, value: v)
        }
    }

    /// Mean of a metric over the `days` days before `date` (baseline for comparisons).
    func baseline(_ def: MetricDef, before date: String, days count: Int = 30) -> Double? {
        let from = Format.addDays(date, -count)
        let values = days.compactMap { d -> Double? in
            guard d.date >= from, d.date < date, countsToward(def, d) else { return nil }
            return def.value(d)
        }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Steps you usually have by `minute` of the day: each of the previous 30 full days' total,
    /// scaled by the share of its minute steps taken by then. Nil with fewer than 5 such days.
    func typicalSteps(before date: String, atMinute minute: Int) -> Double? {
        let from = Format.addDays(date, -30)
        let h = min(23, max(0, minute / 60))
        let values = days.compactMap { d -> Double? in
            guard d.date >= from, d.date < date, d.bool("low_wear") != true, let total = d.double("steps"),
                  let byHour = d.json("steps_by_hour")?.array?.compactMap(\.double), byHour.count == 24,
                  let full = byHour.last, full > 0 else { return nil }
            let before = h == 0 ? 0 : byHour[h - 1]
            let byThen = before + (byHour[h] - before) * Double(minute - h * 60) / 60
            return total * byThen / full
        }
        guard values.count >= 5 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Local minute of the newest minute data loaded for `date`, i.e. how far its totals reach.
    func lastDataMinute(_ date: String) -> Int? {
        guard let intra = dayDetails[date]?.intraday else { return nil }
        let lastHr = intra.hr?.lastIndex { $0 != nil }
        let lastSteps = intra.steps?.lastIndex { $0 != nil }
        return [lastHr, lastSteps].compactMap { $0 }.max()
    }

    /// The current minute of the day in the server's time zone.
    var localMinuteNow: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone ?? .current
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Median wear over the 30 days before `date`.
    func usualWear(before date: String) -> Double? {
        let from = Format.addDays(date, -30)
        // Worn days only, as the server's low-wear rule (days without minute heart rate say nothing about usual wear).
        let values = days.filter { $0.date >= from && $0.date < date }.compactMap { $0.double("wear_min") }.filter { $0 > 0 }.sorted()
        guard values.count >= 5 else { return nil }
        return values[values.count / 2]
    }

    var sleepPlan: SleepPlan {
        SleepPlan.plan(days: daysByDate, today: today, sleepNeedMin: Double(status?.settings.sleepNeedMin ?? 480), wakeTimes: wakeTimes)
    }

    /// The wake-up times set by hand (Monday first), or nil when none are.
    var wakeTimes: [Int?]? {
        guard let times = status?.settings.wakeTimes, times.count == 7, times.contains(where: { $0 != nil }) else { return nil }
        return times
    }

    /// Saves the wake-up times (all nil = none) and makes tonight's plan and the bedtime
    /// reminders use them at once. With the screenshot fixtures they are kept on the phone only.
    func saveWakeTimes(_ times: [Int?]) async -> Bool {
        let any = times.contains(where: { $0 != nil })
        var value: Any = NSNull()
        if any { value = times.map { t -> Any in t.map { $0 as Any } ?? NSNull() } }
        if !isFixture {
            guard let api else { return false }
            do {
                let body = try JSONSerialization.data(withJSONObject: ["wake_times": value])
                _ = try await api.post("settings", body: body)
            } catch {
                handle(error)
                return false
            }
        }
        status?.settings.wakeTimes = any ? times : nil
        await Reminders.update(self)
        updateWidgets()
        return true
    }

    /// Saves the Body age answers; the server works out the body age again before it replies,
    /// so the refresh after it has the new number. With the screenshot fixtures they are kept on
    /// the phone only.
    func saveLifestyle(_ answers: Lifestyle) async -> Bool {
        if !isFixture {
            guard let api else { return false }
            do {
                let body = try JSONSerialization.data(withJSONObject: ["lifestyle": JSONSerialization.jsonObject(with: JSONEncoder().encode(answers))])
                _ = try await api.post("settings", body: body)
            } catch {
                handle(error)
                return false
            }
        }
        status?.settings.lifestyle = answers
        if !isFixture { await refreshAll(force: true) }
        return true
    }

    // MARK: - Home layout backup

    private var homePush: Task<Void, Never>?

    /// Keeps the newer of the phone's and the server's Home layout: a new install gets its Home
    /// back, and edits made on the phone go up. Failures are silent; the next refresh retries.
    func syncHomeLayout() async {
        guard fixtureDir == nil, let api else { return }
        guard let result = try? await api.fetch(HomeLayoutResponse.self, "home") else { return }
        let remote = result.0
        let local = HomeLayout.storedConfig
        if let saved = remote.layout, !HomeLayout.hasLocalLayout || remote.editedAt > local.editedAt {
            UserDefaults.standard.set(HomeLayout.encode(saved), forKey: HomeLayout.configKey)
        } else if remote.layout == nil || local.editedAt > remote.editedAt {
            await pushHomeLayout(local)
        }
    }

    /// Called after every Home edit: uploads it once the edits pause for 2 seconds.
    func homeLayoutEdited() {
        guard fixtureDir == nil else { return }
        homePush?.cancel()
        homePush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.pushHomeLayout(HomeLayout.storedConfig)
        }
    }

    private func pushHomeLayout(_ config: HomeConfig) async {
        guard let api, let body = try? JSONEncoder().encode(HomeLayoutUpload(layout: config, editedAt: config.editedAt)) else { return }
        guard let data = try? await api.post("home", body: body),
              let reply = try? JSONDecoder().decode(HomeLayoutResponse.self, from: data) else { return }
        // The server kept a copy edited later (on a reinstall, say): take it.
        if let newer = reply.layout, reply.editedAt > config.editedAt {
            UserDefaults.standard.set(HomeLayout.encode(newer), forKey: HomeLayout.configKey)
        }
    }

    // MARK: - Training

    private func applyTraining(_ response: TrainingResponse) {
        routines = response.routines
        workoutLogs = response.logs
        bandWorkouts = response.bandWorkouts
        if let l = response.library { library = l }
    }

    func refreshTraining() async {
        guard !isFixture, let api else { return }
        do {
            let (result, data) = try await api.fetch(TrainingResponse.self, "training")
            applyTraining(result)
            DiskCache.save(data, as: "training.json")
            trainingError = nil
        } catch {
            if !error.isCancellation { trainingError = "Couldn't load your training: \(error.localizedDescription)" }
        }
    }

    private func postTraining(_ body: [String: Any]) async throws -> Data {
        guard let api else { throw APIError.unauthorized }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await api.post("training", body: data)
    }

    private func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    /// Saves a new or changed routine and returns it as saved (with its id).
    @discardableResult
    func saveRoutine(_ routine: Routine) async -> Routine? {
        if isFixture {
            var saved = routine
            if saved.id.isEmpty { saved.id = UUID().uuidString.lowercased(); saved.position = (routines.last?.position ?? -1) + 1 }
            if let i = routines.firstIndex(where: { $0.id == saved.id }) { routines[i] = saved } else { routines.append(saved) }
            return saved
        }
        do {
            var body = try json(routine) as? [String: Any] ?? [:]
            // A new one: the server gives it an id and puts it after the others.
            if routine.id.isEmpty {
                body["id"] = nil
                body["position"] = nil
            }
            let data = try await postTraining(["action": "save_routine", "routine": body])
            struct Reply: Decodable { let routine: Routine }
            let saved = try JSONDecoder().decode(Reply.self, from: data).routine
            if let i = routines.firstIndex(where: { $0.id == saved.id }) { routines[i] = saved } else { routines.append(saved) }
            trainingError = nil
            Task { await refreshTraining() }
            return saved
        } catch {
            trainingError = "Couldn't save the routine: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteRoutine(_ id: String) async {
        routines.removeAll { $0.id == id }
        guard !isFixture else { return }
        do {
            _ = try await postTraining(["action": "delete_routine", "id": id])
        } catch {
            trainingError = "Couldn't delete the routine: \(error.localizedDescription)"
            await refreshTraining()
        }
    }

    func moveRoutines(from source: IndexSet, to destination: Int) async {
        routines.move(fromOffsets: source, toOffset: destination)
        guard !isFixture else { return }
        do {
            _ = try await postTraining(["action": "reorder_routines", "ids": routines.map(\.id)])
        } catch {
            trainingError = "Couldn't save the order: \(error.localizedDescription)"
        }
    }

    /// Saves a new or changed workout and returns it as saved (with its id).
    @discardableResult
    func saveLog(_ log: WorkoutLog) async -> WorkoutLog? {
        func keep(_ saved: WorkoutLog) {
            workoutLogs.removeAll { $0.id == saved.id }
            workoutLogs.append(saved)
            workoutLogs.sort { $0.date != $1.date ? $0.date > $1.date : ($0.startedAt ?? "") > ($1.startedAt ?? "") }
        }
        if isFixture {
            var saved = log
            if saved.id.isEmpty { saved.id = UUID().uuidString.lowercased() }
            keep(saved)
            return saved
        }
        do {
            var body = try json(log) as? [String: Any] ?? [:]
            if log.id.isEmpty { body["id"] = nil }
            let data = try await postTraining(["action": "save_log", "log": body])
            struct Reply: Decodable { let log: WorkoutLog }
            let saved = try JSONDecoder().decode(Reply.self, from: data).log
            keep(saved)
            trainingError = nil
            return saved
        } catch {
            trainingError = "Couldn't save the workout: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteLog(_ id: String) async {
        workoutLogs.removeAll { $0.id == id }
        guard !isFixture else { return }
        do {
            _ = try await postTraining(["action": "delete_log", "id": id])
        } catch {
            trainingError = "Couldn't delete the workout: \(error.localizedDescription)"
            await refreshTraining()
        }
    }

    /// Opens the Coach with `text` in its message field, ready to finish and send.
    func askCoach(_ text: String) {
        coachDraft = text
    }

    // MARK: - Journal

    private func applyJournal(_ response: JournalResponse) {
        journalTags = response.tags
        journal = Dictionary(response.entries.map { ($0.date, $0) }, uniquingKeysWith: { _, b in b })
    }

    func tagLabel(_ tag: String) -> String { journalTags.first { $0.id == tag }?.label ?? tag }

    func tagIcon(_ tag: String) -> String { journalTags.first { $0.id == tag }?.icon ?? "tag.fill" }

    /// Your own tags (not built in), most used first.
    var customTags: [String] {
        let builtIn = Set(journalTags.map(\.id))
        var counts: [String: Int] = [:]
        for entry in journal.values {
            for tag in entry.tags where !builtIn.contains(tag) { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Saves one day's entry; an empty tag list means "nothing to note".
    func saveJournal(date: String, tags: [String], note: String) async -> Bool {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = JournalEntry(date: date, tags: tags, note: trimmed.isEmpty ? nil : trimmed)
        if fixtureDir != nil {
            journal[date] = entry
            return true
        }
        guard let api else { return false }
        struct Saved: Decodable { let entry: JournalEntry? }
        do {
            let body = try JSONEncoder().encode(entry)
            let data = try await api.post("journal", body: body)
            journal[date] = (try? JSONDecoder().decode(Saved.self, from: data))?.entry ?? entry
            refreshStatsSoon()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func clearJournal(date: String) async {
        if fixtureDir != nil {
            journal[date] = nil
            return
        }
        guard let api else { return }
        struct Clear: Encodable {
            let date: String
            let clear = true
        }
        do {
            let body = try JSONEncoder().encode(Clear(date: date))
            _ = try await api.post("journal", body: body)
            journal[date] = nil
            refreshStatsSoon()
        } catch {
            handle(error)
        }
    }

    /// Tag effects are rebuilt on the server right after a journal change.
    private func refreshStatsSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let api, let result = try? await api.fetch(StatsPayload.self, "stats") else { return }
            stats = result.0
            DiskCache.save(result.1, as: "stats.json")
        }
    }

    func csvExport() -> URL? {
        let defs = MetricCatalog.all
        var lines = [(["date"] + defs.map(\.key)).joined(separator: ",")]
        for day in days {
            let cells = defs.map { def -> String in
                guard let v = def.value(day) else { return "" }
                return String(format: "%.\(def.decimals + 1)f", v)
            }
            lines.append(([day.date] + cells).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FitStats-\(today).csv")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }
}
