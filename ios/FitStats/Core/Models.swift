import Foundation

// Shapes returned by the `fitstats` Supabase Edge Function.

struct StatusResponse: Codable {
    let version: String
    let serverTime: String
    let today: String
    let timeZone: String?
    let connection: Connection
    let sync: SyncInfo
    let devices: [Device]
    let profile: Profile
    /// `var`: saving the wake-up times updates it on the phone at once (AppModel.saveWakeTimes).
    var settings: UserSettings
    /// The max heart rate strain, stress and zones were computed with (server 1.4.1+).
    let maxHr: MaxHrInfo?

    struct MaxHrInfo: Codable {
        let value: Double
        /// "override", "observed" (your sustained peak) or "age" (208 − 0.7 × age).
        let source: String
    }

    struct Connection: Codable {
        let status: String
        let email: String?
        let connectedAt: String?
        let error: String?
        let missingScopes: [String]
    }

    struct SyncInfo: Codable {
        let running: Bool
        let lastRunAt: String?
        let lastRunStatus: String?
        let lastRecentSyncAt: String?
        let backfillOldest: String?
        let backfillTarget: String?
        let backfillDone: Bool
        let backfillProgress: Double?
        let lastRunLog: JSONValue?
    }

    struct Device: Codable, Identifiable {
        let name: String?
        let type: String?
        let batteryLevel: Int?
        let batteryStatus: String?
        let lastSyncTime: String?
        var id: String { (name ?? "device") + (lastSyncTime ?? "") }
    }

    struct Profile: Codable {
        let age: Int?
    }
}

struct UserSettings: Codable, Equatable {
    var sex: String
    var maxHrOverride: Int?
    var sleepNeedMin: Int
    var stepGoal: Int
    var backfillDays: Int
    var coachModel: String?
    /// Wake-up times set by hand, Monday first: minutes from midnight, nil for a morning without
    /// one (server 1.9.0+). Saved on its own (AppModel.saveWakeTimes), never with the rest.
    var wakeTimes: [Int?]? = nil

    enum CodingKeys: String, CodingKey {
        case sex
        case maxHrOverride = "max_hr_override"
        case sleepNeedMin = "sleep_need_min"
        case stepGoal = "step_goal"
        case backfillDays = "backfill_days"
        case coachModel = "coach_model"
        case wakeTimes = "wake_times"
    }

    static let defaults = UserSettings(sex: "unspecified", maxHrOverride: nil, sleepNeedMin: 480, stepGoal: 10000, backfillDays: 730)

    /// Everything the Preferences form edits (the wake-up times have their own screen).
    var withoutWakeTimes: UserSettings {
        var s = self
        s.wakeTimes = nil
        return s
    }

    // Encode nil explicitly so clearing the max-HR override reaches the server.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sex, forKey: .sex)
        try c.encode(maxHrOverride, forKey: .maxHrOverride)
        try c.encode(sleepNeedMin, forKey: .sleepNeedMin)
        try c.encode(stepGoal, forKey: .stepGoal)
        try c.encode(backfillDays, forKey: .backfillDays)
        try c.encodeIfPresent(coachModel, forKey: .coachModel)
    }
}

struct SettingsResponse: Codable {
    let settings: UserSettings
    /// The max heart rate strain, stress and zones use. Missing from older servers.
    let maxHr: MaxHr?

    struct MaxHr: Codable {
        let value: Double
        /// "override", "observed" or "age".
        let source: String
    }

    enum CodingKeys: String, CodingKey {
        case settings
        case maxHr = "max_hr"
    }
}

/// One `fs_days` row. Columns are read by name so new server columns need no app update.
struct DayRecord: Codable, Identifiable {
    let date: String
    let values: [String: JSONValue]
    var id: String { date }

    init(from decoder: Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let dict = value.object, let date = dict["date"]?.string else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "day row without date"))
        }
        self.date = date
        self.values = dict
    }

    func encode(to encoder: Encoder) throws {
        try JSONValue.object(values).encode(to: encoder)
    }

    func double(_ key: String) -> Double? { values[key]?.double }
    func int(_ key: String) -> Int? { values[key]?.int }
    func string(_ key: String) -> String? { values[key]?.string }
    func bool(_ key: String) -> Bool? { values[key]?.bool }
    func json(_ key: String) -> JSONValue? { values[key] }
}

struct DaysResponse: Codable {
    let from: String
    let to: String
    let today: String
    let days: [DayRecord]
}

struct SleepSession: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let isMain: Bool?
    let isNap: Bool?
    let minutesAsleep: Int?
    let minutesAwake: Int?
    let minutesInPeriod: Int?
    let deepMin: Int?
    let lightMin: Int?
    let remMin: Int?
    let awakeMin: Int?
    let awakeCount: Int?
    let stages: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case id, date, stages
        case startTime = "start_time"
        case endTime = "end_time"
        case isMain = "is_main"
        case isNap = "is_nap"
        case minutesAsleep = "minutes_asleep"
        case minutesAwake = "minutes_awake"
        case minutesInPeriod = "minutes_in_period"
        case deepMin = "deep_min"
        case lightMin = "light_min"
        case remMin = "rem_min"
        case awakeMin = "awake_min"
        case awakeCount = "awake_count"
    }
}

struct Exercise: Codable, Identifiable {
    let id: String
    let date: String
    let startTime: String
    let endTime: String
    let exerciseType: String?
    let name: String?
    let durationS: Double?
    let activeDurationS: Double?
    let calories: Double?
    let steps: Double?
    let distanceM: Double?
    let avgHr: Double?
    let azm: Double?
    let zoneLightS: Double?
    let zoneModerateS: Double?
    let zoneVigorousS: Double?
    let zonePeakS: Double?
    let elevationGainM: Double?
    let avgSpeedMps: Double?
    let runVo2max: Double?
    /// From the minute heart rate during the workout (server lib/scores.ts).
    let trimp: Double?
    let strain: Double?
    /// Highest minute average after single-minute spikes are smoothed out (not a beat-level maximum).
    let hrMax: Double?
    let hrrZoneMin: [Double?]?
    /// Minutes with heart rate, and minute steps, in the server's workout window: from the start's
    /// minute for ceil((end − that minute) / 60 s) minutes. Missing on rows from older servers.
    let hrMinutes: Double?
    let stepsMinute: Double?
    /// Google's DataPoint.dataSource: recordingMethod (MANUAL, PASSIVELY_MEASURED, ACTIVELY_MEASURED,
    /// DERIVED, UNKNOWN), platform and device name.
    let recordingMethod: String?
    let sourcePlatform: String?
    let sourceDevice: String?
    /// Heart-rate recovery: the mean of the last 2 minute HR values in the window (after spikes are
    /// smoothed), and how far heart rate fell 1 and 2 minutes after it. Nil unless the workout ended
    /// hard and heart rate was recorded for both minutes after it, and on rows from older servers.
    let endHr: Double?
    let hrr1min: Double?
    let hrr2min: Double?

    enum CodingKeys: String, CodingKey {
        case id, date, name, calories, steps, azm, trimp, strain
        case startTime = "start_time"
        case endTime = "end_time"
        case exerciseType = "exercise_type"
        case durationS = "duration_s"
        case activeDurationS = "active_duration_s"
        case distanceM = "distance_m"
        case avgHr = "avg_hr"
        case zoneLightS = "zone_light_s"
        case zoneModerateS = "zone_moderate_s"
        case zoneVigorousS = "zone_vigorous_s"
        case zonePeakS = "zone_peak_s"
        case elevationGainM = "elevation_gain_m"
        case avgSpeedMps = "avg_speed_mps"
        case runVo2max = "run_vo2max"
        case hrMax = "hr_max"
        case hrrZoneMin = "hrr_zone_min"
        case hrMinutes = "hr_minutes"
        case stepsMinute = "steps_minute"
        case recordingMethod = "recording_method"
        case sourcePlatform = "source_platform"
        case sourceDevice = "source_device"
        case endHr = "end_hr"
        case hrr1min = "hrr_1min"
        case hrr2min = "hrr_2min"
    }
}

struct DayDetail: Codable {
    let date: String
    let day: DayRecord?
    let intraday: Intraday?
    let sleeps: [SleepSession]
    let exercises: [Exercise]
    let samples: [String: [[Double]]]

    struct Intraday: Codable {
        let hr: [Int?]?
        let steps: [Int?]?
    }

    /// The session the day's sleep columns came from (fs_days.sleep_main_id). Without that id, the
    /// server's ranking (lib/transform.ts mainSleepOf): not a nap, then flagged main sleep, then
    /// longest asleep, then earliest start. Google sometimes flags a nap as main sleep too.
    func mainSleep(id: String?) -> SleepSession? {
        if let id, let named = sleeps.first(where: { $0.id == id }) { return named }
        func rank(_ s: SleepSession) -> Int { (s.isNap == true ? 0 : 2) + (s.isMain == true ? 1 : 0) }
        return sleeps.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) > rank(b) }
            let asleepA = a.minutesAsleep ?? 0, asleepB = b.minutesAsleep ?? 0
            if asleepA != asleepB { return asleepA > asleepB }
            return a.startTime < b.startTime
        }.first
    }
}

// MARK: - Statistics

struct StatsPayload: Codable {
    let generatedAt: String
    let today: String
    let firstDate: String?
    let dayCount: Int
    let metrics: [String: MetricStats]
    let streaks: [Streak]
    let correlations: [Correlation]
    let insights: [Insight]
    /// Missing in stats cached by older servers.
    let journal: [TagImpact]?
    /// Fitness, fatigue and form from daily TRIMP. Missing in stats cached by older servers.
    let load: TrainingLoad?
    /// Sleep by bedtime window. Missing in stats cached by older servers.
    let bedtime: BedtimeStats?
    /// Workouts with a heart-rate recovery over the last 365 days, oldest first. Missing in stats
    /// cached by older servers.
    let hrr: [HrrPoint]?
    /// Body age (server 1.14.0+); nil without their age from Google or enough data.
    let bodyAge: BodyAge?

    enum CodingKeys: String, CodingKey {
        case generatedAt, today, firstDate, dayCount, metrics, streaks, correlations, insights, journal, load, bedtime, hrr
        case bodyAge = "body_age"
    }
}

/// The age whose typical person has their fitness, steps, exercise and sleep (lib/bodyage.ts).
struct BodyAge: Codable, Equatable {
    struct Factor: Codable, Equatable, Identifiable {
        /// fitness, steps, exercise or sleep.
        let key: String
        let label: String
        let value: Double
        let unit: String
        let reference: String
        /// + older, − younger.
        let years: Double
        let detail: String
        let source: String
        let days: Int
        var id: String { key }
    }

    struct Vo2: Codable, Equatable {
        let value: Double
        let typicalForAge: Double
        let method: String
        let errorMlKgMin: Double

        enum CodingKeys: String, CodingKey {
            case value, method
            case typicalForAge = "typical_for_age"
            case errorMlKgMin = "error_ml_kg_min"
        }
    }

    struct WhatIf: Codable, Equatable, Identifiable {
        let change: String
        let years: Double
        var id: String { change }
    }

    struct Point: Codable, Equatable, Identifiable {
        let date: String
        let bodyAge: Double
        var id: String { date }

        enum CodingKeys: String, CodingKey {
            case date
            case bodyAge = "body_age"
        }
    }

    struct Window: Codable, Equatable {
        let from: String
        let to: String
    }

    let age: Int
    let bodyAge: Double
    let difference: Double
    let factors: [Factor]
    let missing: [String]
    let vo2max: Vo2?
    let whatIf: [WhatIf]
    let history: [Point]
    let window: Window
    let note: String

    enum CodingKeys: String, CodingKey {
        case age, difference, factors, missing, vo2max, history, window, note
        case bodyAge = "body_age"
        case whatIf = "what_if"
    }
}

/// Fitness and fatigue: exponentially weighted averages of daily TRIMP (fs_days.trimp).
struct TrainingLoad: Codable {
    /// From the first day with TRIMP through yesterday (today is still growing), at most the last
    /// 180 days. The averages run over the whole history.
    let series: [LoadPoint]
    let latest: LoadPoint?
    /// "calibrating", "fresh", "neutral", "productive" or "overreaching".
    let status: String
    /// The acute:chronic ratio is 1.5 or more.
    let spike: Bool
    /// Days in the series with TRIMP.
    let days: Int
}

struct LoadPoint: Codable, Identifiable {
    let date: String
    /// Nil on a day without TRIMP, which counts as no load.
    let trimp: Double?
    /// Fitness: the 42-day average.
    let ctl: Double
    /// Fatigue: the 7-day average.
    let atl: Double
    /// Fitness minus fatigue.
    let form: Double
    /// Mean TRIMP of the last 7 days over the mean of the last 28. Nil unless 21 of those 28 days have TRIMP.
    let acwr: Double?
    var id: String { date }
}

/// Sleep after each bedtime window, over the last 180 nights with a sleep score.
struct BedtimeStats: Codable {
    let nights: Int
    let buckets: [BedtimeBucket]
    /// Nil when fewer than 2 windows have 3 or more nights.
    let best: Best?

    struct Best: Codable {
        /// The label of the bucket with the highest mean sleep score.
        let label: String
        /// Its mean sleep score minus the mean of all other nights.
        let diff: Double
        /// Welch's t of 2 or more.
        let clear: Bool
    }
}

struct BedtimeBucket: Codable, Identifiable {
    let label: String
    /// In sleep_bedtime_min units (minutes from midnight of the wake day, negative = the evening
    /// before). `from` is included and `to` excluded; nil is open-ended.
    let from: Double?
    let to: Double?
    let nights: Int
    /// Means, nil with fewer than 3 nights. Recovery is the next morning's.
    let sleepScore: Double?
    let asleepMin: Double?
    let recovery: Double?
    var id: String { label }
}

/// One workout's heart-rate recovery (fs_exercise.hrr_1min and friends).
struct HrrPoint: Codable, Identifiable {
    let id: String
    let date: String
    let exerciseType: String?
    let name: String?
    let hrr1: Double
    let hrr2: Double?
    let endHr: Double
}

struct TagImpact: Codable, Identifiable {
    let tag: String
    let label: String
    let days: Int
    let effects: [TagEffect]
    var id: String { tag }
}

/// An outcome on the day after tagged days versus the day after other logged days.
struct TagEffect: Codable, Identifiable {
    let metric: String
    let with: Double
    let without: Double
    let diff: Double
    let nWith: Int
    let nWithout: Int
    let t: Double?
    let clear: Bool
    var id: String { metric }
}

// MARK: - Journal

struct JournalTag: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

struct JournalEntry: Codable, Equatable {
    let date: String
    var tags: [String]
    var note: String?
}

struct JournalResponse: Codable {
    let tags: [JournalTag]
    let entries: [JournalEntry]
}

struct MetricStats: Codable {
    let key: String
    let latest: Double?
    let latestDate: String?
    let ranges: [String: RangeStats]
    let weekday: [Double?]
    let best: Record?
    let worst: Record?

    struct Record: Codable {
        let value: Double
        let date: String
    }
}

struct RangeStats: Codable {
    let days: Int?
    let n: Int
    let mean: Double?
    let median: Double?
    let min: Double?
    let minDate: String?
    let max: Double?
    let maxDate: String?
    let sd: Double?
    let sum: Double?
    let slopePerWeek: Double?
    let prevMean: Double?
    /// mean − prevMean. Missing in stats cached by older servers.
    let change: Double?
    /// Nil for clock times and skin temperature deviation, where a ratio means nothing.
    let changePct: Double?
}

struct Streak: Codable, Identifiable {
    let key: String
    let label: String
    let current: Int
    let longest: Int
    let longestEnd: String?
    var id: String { key }
}

struct Correlation: Codable, Identifiable {
    let x: String
    let y: String
    let lag: Int
    let title: String
    let r: Double?
    let n: Int
    let slope: Double?
    let strength: String
    var id: String { "\(x)-\(y)-\(lag)" }
}

struct Insight: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let tone: String
    let metric: String?
}

// MARK: - Score details stored in fs_days.score_details

struct ScoreComponentInfo: Identifiable {
    let key: String
    let label: String
    let value: Double
    let weight: Double
    let detail: String
    var id: String { key }
}

/// What moved a score most, in one line (ScoreBreakdown.why).
struct ScoreWhy: Equatable {
    let text: String
    /// True when it names the part that lifted the score, false for the part that held it back.
    let lifted: Bool
}

struct ScoreBreakdown {
    let score: Double?
    let status: String
    let components: [ScoreComponentInfo]

    /// Recovery's parts are scored against your own baseline (50 is your usual). On a day under 67
    /// it names the part furthest below that, weighted ("Held back most by HRV: 39 ms vs 43 ms
    /// baseline"); from 67 up the part furthest above it ("Lifted most by HRV: 67 ms vs 43 ms
    /// baseline"). Nil without a score or when no part stands out that way.
    var recoveryWhy: ScoreWhy? {
        guard status == "ok", let score, !components.isEmpty else { return nil }
        let pull = { (c: ScoreComponentInfo) in c.weight * (c.value - 50) }
        if score < 67 {
            guard let down = components.min(by: { pull($0) < pull($1) }), pull(down) <= -1 else { return nil }
            return ScoreWhy(text: "Held back most by \(Self.inSentence(down.label)): \(down.detail)", lifted: false)
        }
        guard let up = components.max(by: { pull($0) < pull($1) }), pull(up) >= 1 else { return nil }
        return ScoreWhy(text: "Lifted most by \(Self.inSentence(up.label)): \(up.detail)", lifted: true)
    }

    /// Sleep's parts are scored against a target (100 is met), and the score is their weighted
    /// average, so it names the part that cost the most points, weight × (100 − value):
    /// "Held back most by duration: 4h 1m of 8h 0m needed". Nil when none cost 3 points.
    var sleepWhy: ScoreWhy? {
        guard status == "ok", score != nil, !components.isEmpty else { return nil }
        let cost = { (c: ScoreComponentInfo) in c.weight * (100 - c.value) }
        guard let worst = components.max(by: { cost($0) < cost($1) }), cost(worst) >= 3 else { return nil }
        return ScoreWhy(text: "Held back most by \(Self.inSentence(worst.label)): \(worst.detail)", lifted: false)
    }

    /// "Consistency" → "consistency" mid-sentence; "HRV" stays.
    private static func inSentence(_ label: String) -> String {
        let chars = Array(label)
        guard chars.count > 1, !chars[1].isUppercase else { return label }
        return label.prefix(1).lowercased() + label.dropFirst()
    }

    init(_ json: JSONValue?) {
        score = json?["score"]?.double
        status = json?["status"]?.string ?? "no_data"
        components = (json?["components"]?.array ?? []).compactMap { c in
            guard let key = c["key"]?.string, let value = c["value"]?.double else { return nil }
            return ScoreComponentInfo(
                key: key,
                label: c["label"]?.string ?? key,
                value: value,
                weight: c["weight"]?.double ?? 0,
                detail: c["detail"]?.string ?? ""
            )
        }
    }
}
