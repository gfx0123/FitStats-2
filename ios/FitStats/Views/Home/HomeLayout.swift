import Foundation

/// A card the Today (Home) screen can show. The raw values are what gets stored, so never
/// rename them: add new cases instead (stored values that no longer match are dropped).
enum HomeCard: String, CaseIterable, Identifiable, Codable {
    // The cards Today always had, in their original order.
    case scores
    case tonight
    case journal
    case vitals
    case activity
    case heartRate
    case workouts
    // Optional cards.
    case lastNight
    case recoveryTrend
    case hrvTrend
    case restingHrTrend
    case stressDay
    case thisWeek
    case weeklyZoneMinutes
    case streaks
    case topInsight
    case coachBrief
    case body
    case trainingLoad
    case liveHeartRate
    // Cards that can be on Home more than once, each with its own settings.
    case metric
    case stack

    var id: String { rawValue }

    /// The cards that can have an "Ask" coach tab under them (TodayView.coachQuestion).
    var hasCoachTab: Bool {
        [.scores, .tonight, .lastNight, .stressDay, .workouts, .trainingLoad].contains(self)
    }

    /// The name in the Home editor: the same as the header the card shows (Scores has none).
    var title: String {
        switch self {
        case .scores: return "Scores"
        case .tonight: return "Tonight"
        case .journal: return "Journal"
        case .vitals: return "Vitals"
        case .activity: return "Activity"
        case .heartRate: return "Heart rate"
        case .workouts: return "Workouts"
        case .lastNight: return "Last night"
        case .recoveryTrend: return "Recovery trend"
        case .hrvTrend: return "HRV trend"
        case .restingHrTrend: return "Resting heart rate trend"
        case .stressDay: return "Stress through the day"
        case .thisWeek: return "This week"
        case .weeklyZoneMinutes: return "Weekly Zone Minutes"
        case .streaks: return "Streaks"
        case .topInsight: return "Insights"
        case .coachBrief: return "Coach briefing"
        case .body: return "Body"
        case .trainingLoad: return "Training load"
        case .liveHeartRate: return "Live heart rate"
        case .metric: return "Metric"
        case .stack: return "Smart Stack"
        }
    }

    /// One line for the Home editor.
    var subtitle: String {
        switch self {
        case .scores: return "Recovery, strain, sleep and stress rings"
        case .tonight: return "Tonight's sleep need and bedtime"
        case .journal: return "Tag what you did that day"
        case .vitals: return "Overnight vitals against your 30-day average"
        case .activity: return "Steps, calories, distance and zone minutes"
        case .heartRate: return "The day's minute-by-minute heart rate"
        case .workouts: return "Workouts recorded that day"
        case .lastNight: return "Last night's sleep, stages and efficiency"
        case .recoveryTrend: return "Recovery over the last few weeks"
        case .hrvTrend: return "HRV against your baseline"
        case .restingHrTrend: return "Resting heart rate against your baseline"
        case .stressDay: return "How stress went through the day"
        case .thisWeek: return "The last 7 days at a glance"
        case .weeklyZoneMinutes: return "Heart-rate zone minutes over the week"
        case .streaks: return "Your current streaks"
        case .topInsight: return "Plain-language insights from your latest stats"
        case .coachBrief: return "Today's briefing from your coach"
        case .body: return "Weight and body fat"
        case .trainingLoad: return "Fitness, fatigue and form from your training"
        case .liveHeartRate: return "From your Fitbit Air over Bluetooth"
        case .metric: return "Any statistic with its trend; add as many as you like"
        case .stack: return "Several cards in one spot: swipe between them"
        }
    }

    /// SF Symbol.
    var icon: String {
        switch self {
        case .scores: return "circle.circle"
        case .tonight: return "moon.stars.fill"
        case .journal: return "square.and.pencil"
        case .vitals: return "stethoscope"
        case .activity: return "figure.walk"
        case .heartRate: return "heart.fill"
        case .workouts: return "figure.run"
        case .lastNight: return "bed.double.fill"
        case .recoveryTrend: return "chart.line.uptrend.xyaxis"
        case .hrvTrend: return "waveform.path.ecg"
        case .restingHrTrend: return "heart.text.square"
        case .stressDay: return "brain.head.profile"
        case .thisWeek: return "calendar"
        case .weeklyZoneMinutes: return "flame.fill"
        case .streaks: return "trophy.fill"
        case .topInsight: return "sparkles"
        case .coachBrief: return "text.bubble.fill"
        case .body: return "scalemass.fill"
        case .trainingLoad: return "speedometer"
        case .liveHeartRate: return "heart.circle"
        case .metric: return "chart.xyaxis.line"
        case .stack: return "square.stack.3d.up.fill"
        }
    }

    /// Shown only while Today is on the current day (past days skip it).
    var todayOnly: Bool { self == .tonight || self == .coachBrief || self == .liveHeartRate }

    /// The size a card gets when it is added, and when a layout from before sizes is loaded.
    var defaultSize: CardSize {
        switch self {
        case .scores: return .large
        case .vitals, .activity, .heartRate, .workouts, .lastNight, .thisWeek, .topInsight, .coachBrief: return .medium
        case .tonight, .journal, .recoveryTrend, .hrvTrend, .restingHrTrend, .stressDay, .weeklyZoneMinutes,
             .streaks, .body, .trainingLoad, .liveHeartRate, .metric: return .small
        case .stack: return .medium
        }
    }

    /// Metric cards and Smart Stacks can be added again and again; every other card once.
    var isUnique: Bool { self != .metric && self != .stack }

    /// A Smart Stack pages between cards of one fixed height, so it has no large size.
    var sizes: [CardSize] { self == .stack ? [.small, .medium] : CardSize.allCases }

    /// Cards with something to set beyond their size (HomeCardSettingsView).
    var hasSettings: Bool {
        switch self {
        case .metric, .stack, .vitals, .activity, .thisWeek, .recoveryTrend, .hrvTrend, .restingHrTrend: return true
        default: return false
        }
    }

    /// Days a trend card covers unless set otherwise.
    var defaultDays: Int {
        switch self {
        case .recoveryTrend: return 14
        default: return 30
        }
    }
}

/// How big a Home card is, like iOS widgets: small takes half the width (two sit side by
/// side), medium the full width at the same height, large is the full card with everything.
enum CardSize: String, CaseIterable, Identifiable, Codable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// The footprint the resize handle works in: small is 1 column, medium 2, large 2 × 2.
    var columns: Int { self == .small ? 1 : 2 }
    var rows: Int { self == .large ? 2 : 1 }

    /// Tapping the resize handle steps through the sizes.
    var next: CardSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .small
        }
    }
}

/// What a card shows beyond its kind. Every field is optional, so a card without settings
/// stores nothing and older layouts decode as they are.
struct CardOptions: Codable, Hashable {
    /// Metric card: the metric key (MetricCatalog).
    var metric: String?
    /// Metric and trend cards: how many days the trend covers.
    var days: Int?
    /// Vitals, Activity and This week: the metrics shown, in order.
    var metrics: [String]?
    /// Smart Stack: its cards, first on top.
    var stack: [StackEntry]?
    /// Smart Stack: open on the card that fits the time of day.
    var rotate: Bool?
    /// The coach tab under the card (HomeCard.hasCoachTab); nil means shown.
    var askCoach: Bool?
}

/// A card inside a Smart Stack.
struct StackEntry: Codable, Hashable, Identifiable {
    var id: String
    var card: HomeCard
    var options = CardOptions()

    var spec: HomeCardSpec { HomeCardSpec(card, options) }
}

/// A card kind with its settings: what a card draws, whatever its size.
struct HomeCardSpec: Hashable {
    var card: HomeCard
    var options: CardOptions

    init(_ card: HomeCard, _ options: CardOptions = CardOptions()) {
        self.card = card
        self.options = options
    }

    var metricKey: String { options.metric ?? "steps" }
    var days: Int { options.days ?? card.defaultDays }
}

/// One card on Home: its kind, size and settings. `id` tells apart two cards of one kind.
struct HomeItem: Codable, Identifiable, Equatable {
    var id: String
    var card: HomeCard
    var size: CardSize
    var options = CardOptions()

    var spec: HomeCardSpec { HomeCardSpec(card, options) }

    /// The name shown in the editor: a Metric card is named after its metric.
    var title: String {
        if card == .metric, let def = MetricCatalog.def(spec.metricKey) { return def.label }
        return card.title
    }
}

/// The ordered cards on Home with their sizes and settings, stored for @AppStorage as JSON
/// under `storageKey`.
enum HomeLayout {
    static let storageKey = "homeCards.v3"
    /// Before settings: "card:size,…". Read once, when nothing is stored under v3.
    static let sizedKey = "homeCards.v2"
    /// Before sizes: the same list without them.
    static let legacyKey = "homeCards.v1"

    static let defaultItems: [HomeItem] = [
        HomeItem(id: "scores", card: .scores, size: .large),
        HomeItem(id: "tonight", card: .tonight, size: .small),
        HomeItem(id: "journal", card: .journal, size: .small),
        HomeItem(id: "vitals", card: .vitals, size: .medium),
        HomeItem(id: "activity", card: .activity, size: .medium),
        HomeItem(id: "heartRate", card: .heartRate, size: .medium),
        HomeItem(id: "workouts", card: .workouts, size: .medium),
    ]

    /// A new card with its default settings. A one-of-a-kind card is identified by its kind,
    /// so it can never be on Home twice.
    static func newItem(_ card: HomeCard, size: CardSize? = nil, options: CardOptions? = nil) -> HomeItem {
        let id = card.isUnique ? card.rawValue : "\(card.rawValue)-\(UUID().uuidString.prefix(8).lowercased())"
        let chosen = size ?? card.defaultSize
        return HomeItem(id: id, card: card, size: card.sizes.contains(chosen) ? chosen : card.defaultSize,
                        options: options ?? defaultOptions(card))
    }

    static func defaultOptions(_ card: HomeCard) -> CardOptions {
        switch card {
        case .metric:
            return CardOptions(metric: "steps", days: 30)
        case .stack:
            return CardOptions(stack: [newEntry(.lastNight), newEntry(.activity), newEntry(.tonight)], rotate: true)
        default:
            return CardOptions()
        }
    }

    static func newEntry(_ card: HomeCard) -> StackEntry {
        StackEntry(id: "\(card.rawValue)-\(UUID().uuidString.prefix(8).lowercased())", card: card, options: defaultOptions(card))
    }

    /// CI screenshots launch with FITSTATS_HOME_CARDS=all to show every card, whatever is stored,
    /// and FITSTATS_HOME_SIZE=small|medium|large to show them all at one size.
    static var showsAllCards: Bool {
        ProcessInfo.processInfo.environment["FITSTATS_HOME_CARDS"] == "all"
    }

    /// Every card in declaration order in fixture mode (ids fixed so tests can find them),
    /// otherwise nil (use the stored layout).
    /// CI only (FITSTATS_HOLD_RESIZE=1): a resize stays stretched after the finger lifts, so a
    /// screenshot can show the card mid-resize.
    static let holdsResize = ProcessInfo.processInfo.environment["FITSTATS_HOLD_RESIZE"] == "1"

    static var fixtureItems: [HomeItem]? {
        guard showsAllCards else { return nil }
        let forced = ProcessInfo.processInfo.environment["FITSTATS_HOME_SIZE"].flatMap(CardSize.init(rawValue:))
        return HomeCard.allCases.map { card -> HomeItem in
            let size = forced.flatMap { card.sizes.contains($0) ? $0 : nil } ?? card.defaultSize
            var options = defaultOptions(card)
            if card == .stack {
                options.stack = [HomeCard.lastNight, .activity, .tonight].map { StackEntry(id: "stack-\($0.rawValue)", card: $0) }
            }
            return HomeItem(id: card.isUnique ? card.rawValue : "\(card.rawValue)-fixture", card: card, size: size, options: options)
        }
    }

    /// The stored layout, else the one from before settings, else the one from before sizes
    /// (each card at its default size), else the default layout. Repeats of a one-of-a-kind
    /// card and repeated ids are dropped.
    static func decode(_ stored: String?) -> [HomeItem] {
        if let stored, !stored.isEmpty, let data = stored.data(using: .utf8),
           let items = try? JSONDecoder().decode([HomeItem].self, from: data) {
            let clean = sanitized(items)
            if !clean.isEmpty { return clean }
        }
        for key in [sizedKey, legacyKey] {
            if let old = UserDefaults.standard.string(forKey: key), !old.isEmpty {
                let items = parseLegacy(old)
                if !items.isEmpty { return items }
            }
        }
        return defaultItems
    }

    static func encode(_ items: [HomeItem]) -> String {
        guard let data = try? JSONEncoder().encode(sanitized(items)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func sanitized(_ items: [HomeItem]) -> [HomeItem] {
        var ids = Set<String>()
        var kinds = Set<HomeCard>()
        return items.compactMap { item -> HomeItem? in
            guard ids.insert(item.id).inserted else { return nil }
            if item.card.isUnique && !kinds.insert(item.card).inserted { return nil }
            if item.card == .stack && (item.options.stack ?? []).isEmpty { return nil }
            var fixed = item
            if !item.card.sizes.contains(item.size) { fixed.size = item.card.defaultSize }
            return fixed
        }
    }

    /// "card:size,…" or "card,…" (the size then the card's default).
    private static func parseLegacy(_ stored: String) -> [HomeItem] {
        var seen = Set<HomeCard>()
        var items: [HomeItem] = []
        for part in stored.split(separator: ",") {
            let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let raw = pieces.first, let card = HomeCard(rawValue: raw), card.isUnique, seen.insert(card).inserted else { continue }
            let size = pieces.count > 1 ? CardSize(rawValue: pieces[1]) : nil
            items.append(HomeItem(id: card.rawValue, card: card, size: size ?? card.defaultSize))
        }
        return items
    }
}

/// A part of the day with its own Home layout (when time-of-day layouts are on).
enum HomePage: String, CaseIterable, Identifiable, Codable {
    case morning, day, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Morning"
        case .day: return "Day"
        case .evening: return "Evening"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        }
    }
}

/// Everything about Home: its layout, and optionally one layout per part of the day. Stored on
/// the phone under `HomeLayout.configKey` and on the server (AppModel.syncHomeLayout); the
/// copy edited last wins.
struct HomeConfig: Codable, Equatable {
    /// The layout when time-of-day layouts are off, and the starting point for each of them.
    var items: [HomeItem]
    var timeOfDay = false
    var morning: [HomeItem]?
    var day: [HomeItem]?
    var evening: [HomeItem]?
    /// Minutes after midnight each part of the day starts (morning < day < evening).
    var morningStart = 240
    var dayStart = 660
    var eveningStart = 1080
    /// Last edit, in seconds since 1970; 0 for a layout never edited on this version.
    var editedAt: Double = 0

    init(items: [HomeItem]) {
        self.items = items
    }

    /// Every field but `items` may be missing (older or newer copies still load).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([HomeItem].self, forKey: .items)
        timeOfDay = (try? c.decodeIfPresent(Bool.self, forKey: .timeOfDay)) ?? false
        morning = try? c.decodeIfPresent([HomeItem].self, forKey: .morning)
        day = try? c.decodeIfPresent([HomeItem].self, forKey: .day)
        evening = try? c.decodeIfPresent([HomeItem].self, forKey: .evening)
        morningStart = (try? c.decodeIfPresent(Int.self, forKey: .morningStart)) ?? 240
        dayStart = (try? c.decodeIfPresent(Int.self, forKey: .dayStart)) ?? 660
        eveningStart = (try? c.decodeIfPresent(Int.self, forKey: .eveningStart)) ?? 1080
        editedAt = (try? c.decodeIfPresent(Double.self, forKey: .editedAt)) ?? 0
    }

    /// The part of the day `date` falls in (the phone's clock).
    func page(at date: Date) -> HomePage {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if minute >= eveningStart || minute < morningStart { return .evening }
        return minute >= dayStart ? .day : .morning
    }

    /// The cards of `page`, or the single layout for nil; a page never set up starts as a copy.
    func items(for page: HomePage?) -> [HomeItem] {
        let list: [HomeItem]?
        switch page {
        case .morning: list = morning
        case .day: list = day
        case .evening: list = evening
        case nil: list = items
        }
        let clean = HomeLayout.sanitized(list ?? items)
        return clean.isEmpty ? HomeLayout.defaultItems : clean
    }

    mutating func setItems(_ new: [HomeItem], for page: HomePage?) {
        switch page {
        case .morning: morning = new
        case .day: day = new
        case .evening: evening = new
        case nil: items = new
        }
    }

    /// The minute after midnight `page` starts.
    func start(of page: HomePage) -> Int {
        switch page {
        case .morning: return morningStart
        case .day: return dayStart
        case .evening: return eveningStart
        }
    }
}

extension HomeLayout {
    /// The whole Home configuration (JSON of HomeConfig).
    static let configKey = "homeConfig.v1"

    /// The stored configuration, else one built from the layout before time-of-day layouts.
    static func config(from stored: String?) -> HomeConfig {
        if let stored, !stored.isEmpty, let data = stored.data(using: .utf8),
           let config = try? JSONDecoder().decode(HomeConfig.self, from: data), !sanitized(config.items).isEmpty {
            return config
        }
        return HomeConfig(items: decode(UserDefaults.standard.string(forKey: storageKey)))
    }

    static func encode(_ config: HomeConfig) -> String {
        guard let data = try? JSONEncoder().encode(config) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The configuration on this phone right now (same key and format as TodayView's @AppStorage).
    static var storedConfig: HomeConfig {
        config(from: UserDefaults.standard.string(forKey: configKey))
    }

    /// False until Home has been stored on this phone in any version: a new install, which takes
    /// the server's copy whatever its time.
    static var hasLocalLayout: Bool {
        [configKey, storageKey, sizedKey, legacyKey].contains { !(UserDefaults.standard.string(forKey: $0) ?? "").isEmpty }
    }
}

/// The last configuration decoded from its stored JSON, kept until that JSON changes. Today
/// reads it many times per update, and every frame while a card follows the finger.
final class HomeConfigCache {
    private var raw: String?
    private var value: HomeConfig?

    func config(from stored: String) -> HomeConfig {
        if stored == raw, let value { return value }
        let decoded = HomeLayout.config(from: stored)
        raw = stored
        value = decoded
        return decoded
    }
}

/// The server's copy of the Home configuration (route "home").
struct HomeLayoutResponse: Decodable {
    let layout: HomeConfig?
    let editedAt: Double

    enum CodingKeys: String, CodingKey {
        case layout
        case editedAt = "edited_at"
    }

    /// A copy this version can't read counts as none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try? c.decodeIfPresent(HomeConfig.self, forKey: .layout)
        editedAt = (try? c.decode(Double.self, forKey: .editedAt)) ?? 0
    }
}

struct HomeLayoutUpload: Encodable {
    let layout: HomeConfig
    let editedAt: Double

    enum CodingKeys: String, CodingKey {
        case layout
        case editedAt = "edited_at"
    }
}
