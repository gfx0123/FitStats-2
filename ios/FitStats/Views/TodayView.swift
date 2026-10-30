import Combine
import SwiftUI

enum DetailRoute: Hashable {
    case recovery(String)
    case strain(String)
    case sleep(String)
    case stress(String)
    case metric(String)
    case workout(String, String) // date, exercise id
    case liveHeartRate
    /// A Home card at full size, opened from its small or medium version.
    case homeCard(HomeCardSpec, String) // card with its settings, date
}

struct DetailDestination: View {
    let route: DetailRoute

    var body: some View {
        switch route {
        case .recovery(let d): RecoveryDetailView(date: d)
        case .strain(let d): StrainDetailView(date: d)
        case .sleep(let d): SleepDetailView(date: d)
        case .stress(let d): StressDetailView(date: d)
        case .metric(let key):
            if let def = MetricCatalog.def(key) {
                MetricDetailView(def: def)
            } else {
                EmptyStateView(icon: "questionmark", title: "Unknown metric", message: key)
            }
        case .workout(let date, let id): WorkoutDetailView(date: date, exerciseId: id)
        case .liveHeartRate: LiveHeartRateView()
        case .homeCard(let spec, let d): HomeCardDetailView(spec: spec, date: d)
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore
    @EnvironmentObject private var live: LiveHeartRateMonitor
    @State private var selected: String?
    /// Home: the cards, their sizes and settings, and the time-of-day layouts (HomeConfig).
    @AppStorage(HomeLayout.configKey) private var storedConfig = ""
    /// Every card while CI takes screenshots (FITSTATS_HOME_CARDS=all); edits then stay in memory.
    @State private var fixtureConfig: HomeConfig? = HomeLayout.fixtureItems.map { HomeConfig(items: $0) }
    /// The time-of-day layout being edited (edit mode only).
    @State private var editingPage: HomePage = .day
    @State private var editingTimes = false
    /// Moves Home to the next time-of-day layout while it's open.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    /// Edit mode, like the iOS Home Screen: the cards wobble and can be moved, resized, removed
    /// and added in place.
    @State private var editing = false
    /// The card being moved while editing: lifted by a short hold, it follows the finger.
    @State private var moving: HomeMove?
    /// Every card's frame on screen while one is moving (HomeCellFrameKey).
    @State private var cellFrames: [String: CGRect] = [:]
    /// Where the moved card rests now; acting on it needs a short rest (zoneToken).
    @State private var moveZone: HomeZone?
    @State private var zoneToken = 0
    /// The card the moved one would stack with if let go now.
    @State private var stackTarget: String?
    /// The scroll view on screen, to scroll while a card is held near its top or bottom.
    @State private var scrollFrame: CGRect = .zero
    /// -1 scrolling up, 1 down, 0 still.
    @State private var autoscroll = 0
    @State private var moveHaptic = 0
    /// The card being resized, stretched under the finger above everything.
    @State private var resizing: HomeResize?
    /// The decoded configuration, so reading it while a card follows the finger stays cheap.
    @State private var configCache = HomeConfigCache()
    /// The card whose settings sheet is open.
    @State private var settingsItem: HomeItem?
    @State private var editHaptic = 0
    /// A day swipe past today or the first synced day.
    @State private var dayEndBump = 0

    private static let addSectionID = "home-add-section"
    private static let minuteTicker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var date: String { selected ?? model.today }
    private var day: DayRecord? { model.daysByDate[date] }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if editing {
                            editHeader
                        } else {
                            WeekStrip(today: model.today, selected: $selected) { model.daysByDate[$0]?.double("recovery") }
                            syncLine
                            banners
                            emptyState
                        }
                        HomeGridLayout(columnSpacing: 12, rowSpacing: 14) {
                            let right = rightColumn
                            ForEach(gridItems) { item in
                                cell(item, inRightColumn: right.contains(item.id))
                                    .id(item.id)
                                    .layoutValue(key: HomeCardSizeKey.self, value: item.size)
                            }
                        }
                        .onPreferenceChange(HomeCellFrameKey.self) { frames in
                            cellFrames = frames
                            adoptGrab()
                            evaluateMove()
                        }
                        if editing {
                            HomeAddSection(date: date, shown: items, isDefault: items == HomeLayout.defaultItems,
                                           canShow: isVisible, onAdd: add, onReset: reset)
                                .id(Self.addSectionID)
                        } else {
                            AskCoachRow(prompts: date == model.today
                                ? [("sparkles", "Explain today", "About today: what stands out so far, and why?"),
                                   ("figure.run", "What should I do today?", "What should I do today, given my recovery, sleep and training?")]
                                : [("sparkles", "Explain this day", "About my day on \(Format.longDay(date)): what stands out, and why?")])
                            trendsButton
                            editHomeButton
                            footer
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, editing ? 8 : 0)
                    .padding(.bottom, 32)
                    .sensoryFeedback(.impact(weight: .medium), trigger: editHaptic)
                    .sensoryFeedback(.selection, trigger: moveHaptic)
                    .sensoryFeedback(.selection, trigger: date)
                    .sensoryFeedback(.impact(weight: .light), trigger: dayEndBump)
                }
                .scrollDisabled(moving != nil)
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { scrollFrame = geo.frame(in: .global) }
                            .onChange(of: geo.frame(in: .global)) { _, frame in scrollFrame = frame }
                    }
                }
                .overlay { movingCard }
                .overlay { resizingCard }
                // Cards grow with the text size up to here (HomeGlanceMetrics.height(for:)).
                .dynamicTypeSize(...HomeGlanceMetrics.largestTextSize)
                .task(id: autoscroll) { await runAutoscroll(proxy) }
                .refreshable {
                    await model.pullToRefresh()
                    await model.loadDay(date, force: true)
                }
                .screenBackground()
                .task(id: date) { await model.loadDay(date) }
                .navigationDestination(for: DetailRoute.self) { DetailDestination(route: $0) }
                .swipeBackFromAnywhere()
                .onDaySwipe(enabled: !editing) { daySwipe($0) }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { header(proxy) }
                .fullScreenCover(isPresented: $model.showTrends) { TrendsSheet() }
                .sheet(item: $settingsItem) { item in
                    HomeCardSettingsView(draft: item, canRemove: items.count > 1,
                                         onChange: update, onRemove: { remove(item.id) },
                                         onExtract: { entry in extract(entry, from: item.id) })
                        .environmentObject(model)
                }
                .sheet(isPresented: $editingTimes) {
                    HomeTimesSheet(config: configBinding)
                }
                .sheet(item: Binding(get: { model.journalRequest.map(JournalDay.init) },
                                     set: { model.journalRequest = $0?.date })) { day in
                    JournalSheet(date: day.date).environmentObject(model)
                }
                .onReceive(Self.minuteTicker) { now = $0 }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { now = Date() }
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if day == nil {
            Card {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No data for this day",
                    message: model.days.isEmpty
                        ? "Your history is still syncing. Pull down to refresh in a minute."
                        : "Nothing was recorded on \(Format.longDay(date))."
                )
            }
        } else if visibleItems.isEmpty {
            Card {
                EmptyStateView(
                    icon: "square.grid.2x2",
                    title: "Nothing on Home for this day",
                    message: "Your Home cards only show on today. Tap Edit Home screen to add cards for past days."
                )
            }
        }
    }

    /// The hint, and with time-of-day layouts on, which one is being edited.
    private var editHeader: some View {
        VStack(spacing: 10) {
            Text("Tap a card for its settings. Hold a card, then drag it to move it, or rest it on the middle of a card the same size to stack them. Drag the corner handle to resize.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Card(padding: 12) {
                Toggle(isOn: timeOfDayBinding) {
                    Label("Change Home by time of day", systemImage: "clock.arrow.2.circlepath")
                        .font(Font.fs(.subheadline, .semibold))
                }
                .tint(Theme.recoveryGreen)
                .accessibilityIdentifier("home-time-of-day")
                if config.timeOfDay {
                    Picker("Layout", selection: $editingPage) {
                        ForEach(HomePage.allCases) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("home-page-picker")
                    Button {
                        editingTimes = true
                    } label: {
                        HStack {
                            Text(timesText)
                                .font(Font.fs(.caption))
                                .foregroundStyle(Theme.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Text("Change").font(Font.fs(.caption, .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.recoveryGreen)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var timesText: String {
        let c = config
        return "Morning from \(Format.clock(Double(c.morningStart))), day from \(Format.clock(Double(c.dayStart))), evening from \(Format.clock(Double(c.eveningStart)))."
    }

    // MARK: home cards

    private var config: HomeConfig {
        fixtureConfig ?? configCache.config(from: storedConfig)
    }

    /// Saves Home, stamped with the time of the edit (the newer copy wins on the server).
    private func save(_ config: HomeConfig) {
        var stamped = config
        stamped.editedAt = Date().timeIntervalSince1970
        if fixtureConfig != nil {
            fixtureConfig = stamped
        } else {
            storedConfig = HomeLayout.encode(stamped)
            model.homeLayoutEdited()
        }
    }

    private var configBinding: Binding<HomeConfig> {
        Binding(get: { config }, set: { save($0) })
    }

    /// The time-of-day layout on screen: the one being edited, else the one for now; nil when
    /// Home has a single layout.
    private var page: HomePage? {
        guard config.timeOfDay else { return nil }
        return editing ? editingPage : config.page(at: now)
    }

    private var items: [HomeItem] {
        config.items(for: page)
    }

    private var layout: Binding<[HomeItem]> {
        Binding(
            get: { config.items(for: page) },
            set: { next in
                var c = config
                c.setItems(next, for: page)
                save(c)
            }
        )
    }

    /// Turning it on gives each part of the day a copy of the current layout to start from;
    /// turning it off keeps them for next time.
    private var timeOfDayBinding: Binding<Bool> {
        Binding(
            get: { config.timeOfDay },
            set: { on in
                var c = config
                if on {
                    if c.morning == nil { c.morning = c.items }
                    if c.day == nil { c.day = c.items }
                    if c.evening == nil { c.evening = c.items }
                    editingPage = c.page(at: Date())
                }
                c.timeOfDay = on
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { save(c) }
            }
        )
    }

    /// The right cards of the pairs of small cards, by HomeGridLayout's rule. While editing every
    /// card draws, so none is skipped.
    private var rightColumn: Set<String> {
        var right = Set<String>()
        var leftOpen = false
        for item in gridItems {
            if item.size == .small {
                if leftOpen { right.insert(item.id) }
                leftOpen.toggle()
            } else {
                leftOpen = false
            }
        }
        return right
    }

    /// The cards Today draws for this day, so a skipped card never leaves an empty cell behind.
    private var visibleItems: [HomeItem] {
        items.filter(isVisible)
    }

    /// A Smart Stack shows when any of its cards can.
    private func isVisible(_ item: HomeItem) -> Bool {
        if item.card == .stack { return !visibleEntries(item).isEmpty }
        return isVisible(item.card)
    }

    private func visibleEntries(_ item: HomeItem) -> [StackEntry] {
        (item.options.stack ?? []).filter { $0.card != .stack && isVisible($0.card) }
    }

    /// While editing every card shows (the hidden ones as placeholders), so each can be
    /// arranged.
    private var gridItems: [HomeItem] {
        editing ? items : visibleItems
    }

    /// Cards built from this day's record. The other cards take only the date and handle a
    /// missing day themselves.
    private static let dayRecordCards: Set<HomeCard> = [.scores, .tonight, .journal, .vitals, .activity, .heartRate, .workouts]

    /// Today-only cards are skipped on past days. A day without a record skips the cards that
    /// need it, and while the history is still syncing (no days at all) only the empty state
    /// shows.
    private func isVisible(_ card: HomeCard) -> Bool {
        if card.todayOnly && date != model.today { return false }
        if day == nil {
            if model.days.isEmpty { return false }
            if Self.dayRecordCards.contains(card) { return false }
        }
        return true
    }

    private func hiddenReason(_ card: HomeCard) -> String {
        if card == .stack { return "None of its cards has anything to show on this day." }
        if card.todayOnly && date != model.today { return "Shows on today only." }
        return model.days.isEmpty ? "Shows once your history has synced." : "Shows once today's data has synced."
    }

    /// One cell of the grid. Holding a card for a moment starts editing: the long press is high
    /// priority so it wins over the links inside, but it fails as soon as the finger lifts or
    /// moves, so taps still reach those links and the page still scrolls.
    @ViewBuilder private func cell(_ item: HomeItem, inRightColumn: Bool) -> some View {
        if editing {
            HomeEditCell(
                item: item,
                seed: item.id.unicodeScalars.reduce(0) { $0 + Int($1.value) },
                canRemove: items.count > 1,
                inRightColumn: inRightColumn,
                isMoving: moving?.id == item.id && moving?.tracking == true && cellFrames[item.id] != nil,
                isResizing: resizing?.id == item.id,
                isStackTarget: stackTarget == item.id,
                onRemove: { remove(item.id) },
                onResize: { resize(item.id, to: $0) },
                onMove: { move(item.id, by: $0) },
                onEdit: { settingsItem = item },
                onResizing: { resizeChanged(item.id, $0) },
                onDrag: { event in handleDrag(item.id, event) }
            ) { size in
                cellContent(item, size: size)
            }
            .background {
                if moving != nil || resizing != nil {
                    GeometryReader { geo in
                        Color.clear.preference(key: HomeCellFrameKey.self, value: [item.id: geo.frame(in: .global)])
                    }
                }
            }
            .accessibilityIdentifier("home-card-\(item.id)")
        } else {
            VStack(spacing: 0) {
                cellContent(item, size: item.size)
                if let question = coachQuestion(item) { CoachCardTab(question: question) }
            }
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in startEditing() }
                )
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: Text("Edit Home screen")) { startEditing() }
                .accessibilityIdentifier("home-card-\(item.id)")
        }
    }

    /// The question a card's coach tab sends, for the cards it is worth asking about; nil for
    /// the others.
    private func coachQuestion(_ item: HomeItem) -> String? {
        let today = date == model.today
        let day = today ? "today" : "on \(Format.longDay(date))"
        switch item.card {
        case .scores:
            return "About my scores \(day): what's behind my recovery, sleep and strain, and what should I do about it?"
        case .tonight:
            return "About tonight's sleep plan: when should I go to bed, and why that time?"
        case .lastNight:
            return today ? "How did I sleep last night, and what affected it?" : "How did I sleep the night before \(Format.longDay(date)), and what affected it?"
        case .stressDay:
            return "About my stress \(day): why is it where it is, and what can I do about it?"
        case .workouts:
            return "About my workouts \(day): how hard were they, and how should I recover?"
        case .trainingLoad:
            return "About my training load: am I doing too much or too little right now?"
        default:
            return nil
        }
    }

    /// The card at `size`.
    @ViewBuilder private func cellContent(_ item: HomeItem, size: CardSize) -> some View {
        if !isVisible(item) {
            HomeCardPlaceholder(card: item.card, title: item.title, size: size, reason: hiddenReason(item.card))
        } else if item.card == .stack {
            SmartStackView(entries: visibleEntries(item), size: size, date: date, rotate: item.options.rotate ?? true)
        } else if size == .large {
            HomeLargeCard(spec: item.spec, date: date)
        } else {
            HomeGlance(spec: item.spec, size: size, date: date)
        }
    }

    private func startEditing() {
        editHaptic += 1
        moving = nil
        editingPage = config.page(at: now)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selected = nil
            editing = true
        }
    }

    private func finishEditing() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            editing = false
            moving = nil
            resizing = nil
            moveZone = nil
            stackTarget = nil
        }
    }

    // MARK: moving cards

    /// The moved card, drawn above everything at the finger (or gliding into its slot after it
    /// is let go). Its own cell shows an empty outline meanwhile.
    @ViewBuilder private var movingCard: some View {
        if let m = moving, m.tracking, let item = items.first(where: { $0.id == m.id }), let slot = cellFrames[m.id] {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                let grab = m.grab ?? CGSize(width: slot.width / 2, height: slot.height / 2)
                let topLeft = m.landing ? slot.origin : CGPoint(x: m.finger.x - grab.width, y: m.finger.y - grab.height)
                cellContent(item, size: item.size)
                    .frame(width: slot.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.homeCardPreview, true)
                    // Opaque, so the cards it passes over don't show through its own translucent card.
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.background))
                    .scaleEffect(m.landing ? 1 : 1.05)
                    .shadow(color: .black.opacity(m.landing ? 0 : 0.5), radius: 18, y: 10)
                    .position(x: topLeft.x - origin.x + slot.width / 2, y: topLeft.y - origin.y + slot.height / 2)
            }
            .allowsHitTesting(false)
        }
    }

    /// The card being resized, stretched under the finger above everything (or gliding into
    /// its new slot once let go). Its own cell stays empty meanwhile.
    @ViewBuilder private var resizingCard: some View {
        if let r = resizing, let item = items.first(where: { $0.id == r.id }) {
            let rect = r.settling ? (cellFrames[r.id] ?? r.rect) : r.rect
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                HomeStretchedCard(size: rect.size, leftward: r.leftward, settling: r.settling) {
                    cellContent(item, size: item.size)
                }
                .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
            }
            .allowsHitTesting(false)
        }
    }

    private func resizeChanged(_ id: String, _ stretch: HomeResize?) {
        if let stretch {
            resizing = stretch
            return
        }
        guard var r = resizing, r.id == id, !r.settling else { return }
        r.settling = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { resizing = r }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 330_000_000)
            if resizing?.id == id, resizing?.settling == true { resizing = nil }
        }
    }

    private func handleDrag(_ id: String, _ event: HomeDragEvent) {
        switch event {
        case .lifted:
            beginMove(id)
        case .moved(let start, let location):
            beginMove(id)
            guard var m = moving, m.id == id, !m.landing else { return }
            if m.start == nil { m.start = start }
            m.finger = location
            m.tracking = true
            if m.grab == nil, let frame = cellFrames[id] {
                m.grab = CGSize(width: start.x - frame.minX, height: start.y - frame.minY)
            }
            moving = m
            evaluateMove()
            updateAutoscroll(location)
        case .ended:
            endMove(id)
        }
    }

    private func beginMove(_ id: String) {
        guard moving == nil, editing else { return }
        moving = HomeMove(id: id)
        moveZone = nil
        stackTarget = nil
        editHaptic += 1
    }

    /// The finger's spot on the card, once the card's frame is known.
    private func adoptGrab() {
        guard var m = moving, m.grab == nil, let start = m.start, let frame = cellFrames[m.id] else { return }
        m.grab = CGSize(width: start.x - frame.minX, height: start.y - frame.minY)
        moving = m
    }

    /// Which card the finger is over, and whether over its middle (stack) or which half (move
    /// before or after it). Beside a lone small card, in the empty half of its row, counts as
    /// next to it, and below the last card as after it.
    private func evaluateMove() {
        guard let m = moving, m.tracking, !m.landing, let moved = items.first(where: { $0.id == m.id }) else { return }
        let p = m.finger
        let others = cellFrames.filter { $0.key != m.id }
        if let hit = others.first(where: { $0.value.contains(p) }) {
            setZone(zone(p, over: hit.key, hit.value, moving: moved, others: others))
        } else if let beside = others.filter({ $0.value.minY <= p.y && p.y <= $0.value.maxY })
                    .min(by: { abs($0.value.midX - p.x) < abs($1.value.midX - p.x) }) {
            setZone(zone(p, over: beside.key, beside.value, moving: moved, others: others))
        } else if let last = gridItems.last(where: { $0.id != m.id }), let frame = cellFrames[last.id],
                  p.y > frame.maxY, p.y < frame.maxY + 160 {
            setZone(HomeZone(target: last.id, middle: false, after: true))
        } else {
            setZone(nil)
        }
    }

    /// Before or after the card under the finger by which half it's in (sideways for two small
    /// cards). A wide card held over a pair of small ones goes before or after the whole pair.
    private func zone(_ p: CGPoint, over id: String, _ frame: CGRect, moving: HomeItem, others: [String: CGRect]) -> HomeZone {
        let target = items.first { $0.id == id }
        let stackable = target.map { canStack(moving, onto: $0) } ?? false
        let middle = stackable && frame.insetBy(dx: frame.width * 0.25, dy: frame.height * 0.25).contains(p)
        guard target?.size == .small else {
            return HomeZone(target: id, middle: middle, after: p.y > frame.midY)
        }
        guard moving.size != .small else {
            return HomeZone(target: id, middle: middle, after: p.x > frame.midX)
        }
        let after = p.y > frame.midY
        let row = others.filter { abs($0.value.midY - frame.midY) < 1 }
        let end = after ? row.max(by: { $0.value.minX < $1.value.minX }) : row.min(by: { $0.value.minX < $1.value.minX })
        return HomeZone(target: end?.key ?? id, middle: middle, after: after)
    }

    /// Like iOS, a card stacks only with one of its own size (and stacks are small or medium), so
    /// moving a card past others of another size never stops to offer a stack.
    private func canStack(_ moving: HomeItem, onto target: HomeItem) -> Bool {
        moving.card != .stack && moving.size == target.size && target.size != .large
    }

    /// Resting near a card's edge for a moment moves the card there; resting on its middle a
    /// little longer offers a stack. Passing over cards quickly does neither.
    private func setZone(_ zone: HomeZone?) {
        guard zone != moveZone else { return }
        moveZone = zone
        zoneToken += 1
        if let target = stackTarget, zone?.target != target || zone?.middle != true { stackTarget = nil }
        guard let zone else { return }
        let token = zoneToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: zone.middle ? 450_000_000 : 180_000_000)
            guard token == zoneToken, let m = moving, !m.landing else { return }
            if zone.middle {
                stackTarget = zone.target
            } else {
                reorder(m.id, beside: zone)
            }
        }
    }

    private func reorder(_ id: String, beside zone: HomeZone) {
        var list = items
        guard let from = list.firstIndex(where: { $0.id == id }) else { return }
        let item = list.remove(at: from)
        guard var to = list.firstIndex(where: { $0.id == zone.target }) else { return }
        if zone.after { to += 1 }
        list.insert(item, at: min(to, list.count))
        guard list.map(\.id) != items.map(\.id) else { return }
        moveHaptic += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout.wrappedValue = list }
    }

    /// Let go: onto a highlighted card it stacks, otherwise it glides into its slot.
    private func endMove(_ id: String) {
        guard var m = moving, m.id == id, !m.landing else { return }
        autoscroll = 0
        if let target = stackTarget, m.tracking {
            moving = nil
            moveZone = nil
            stackTarget = nil
            stack(id, onto: target)
            return
        }
        guard m.tracking else {
            moving = nil
            return
        }
        m.landing = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { moving = m }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if moving?.id == id { moving = nil }
            moveZone = nil
            stackTarget = nil
        }
    }

    private func updateAutoscroll(_ p: CGPoint) {
        let edge: CGFloat = 100
        let direction = p.y < scrollFrame.minY + edge ? -1 : (p.y > scrollFrame.maxY - edge ? 1 : 0)
        if direction != autoscroll { autoscroll = direction }
    }

    /// While a card is held near the top or bottom, the page scrolls a card at a time.
    private func runAutoscroll(_ proxy: ScrollViewProxy) async {
        while autoscroll != 0, moving != nil {
            let ids = gridItems.map(\.id)
            if autoscroll > 0 {
                if let next = ids.first(where: { (cellFrames[$0]?.maxY ?? 0) > scrollFrame.maxY + 1 }) {
                    withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(next, anchor: .bottom) }
                }
            } else if let previous = ids.last(where: { (cellFrames[$0]?.minY ?? .infinity) < scrollFrame.minY - 1 }) {
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(previous, anchor: .top) }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            evaluateMove()
        }
    }

    /// A card dropped on another's middle: the two become a Smart Stack where the target was
    /// (each keeps its settings), or the card joins the target stack.
    private func stack(_ draggedID: String, onto targetID: String) {
        var next = items
        guard let di = next.firstIndex(where: { $0.id == draggedID }),
              let ti = next.firstIndex(where: { $0.id == targetID }) else { return }
        let dragged = next[di]
        let target = next[ti]
        guard dragged.card != .stack else { return }
        let entry = StackEntry(id: dragged.id, card: dragged.card, options: dragged.options)
        if target.card == .stack {
            next[ti].options.stack = (target.options.stack ?? []) + [entry]
        } else {
            let first = StackEntry(id: target.id, card: target.card, options: target.options)
            next[ti] = HomeLayout.newItem(.stack, size: target.size == .small ? .small : .medium,
                                          options: CardOptions(stack: [first, entry], rotate: false))
        }
        next.remove(at: di)
        editHaptic += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { layout.wrappedValue = next }
    }

    /// "Move to Home" in a stack's settings: the card goes back on Home right after the stack.
    /// A one-of-a-kind card already on Home just leaves the stack.
    private func extract(_ entry: StackEntry, from stackID: String) {
        var next = items
        guard let si = next.firstIndex(where: { $0.id == stackID }) else { return }
        let size = next[si].size
        var card = HomeLayout.newItem(entry.card, size: entry.card.sizes.contains(size) ? size : entry.card.defaultSize,
                                      options: entry.options)
        if !entry.card.isUnique { card.id = entry.id }
        guard !next.contains(where: { $0.id == card.id || (entry.card.isUnique && $0.card == entry.card) }) else { return }
        next.insert(card, at: si + 1)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func remove(_ id: String) {
        guard items.count > 1 else { return }
        let next = items.filter { $0.id != id }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func resize(_ id: String, to size: CardSize) {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == id }), next[i].size != size, next[i].card.sizes.contains(size) else { return }
        next[i].size = size
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { layout.wrappedValue = next }
    }

    /// A change from the card's settings sheet.
    private func update(_ item: HomeItem) {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == item.id }), next[i] != item else { return }
        next[i] = item
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    /// VoiceOver's move up / move down.
    private func move(_ id: String, by offset: Int) {
        var next = items
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(0, i + offset), next.count - 1)
        guard i != j else { return }
        next.swapAt(i, j)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func add(_ item: HomeItem) {
        guard !items.contains(where: { $0.id == item.id || (item.card.isUnique && $0.card == item.card) }) else { return }
        editHaptic += 1
        let next = items + [item]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.wrappedValue = next }
    }

    private func reset() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { layout.wrappedValue = HomeLayout.defaultItems }
    }

    private var editHomeButton: some View {
        Button {
            startEditing()
        } label: {
            Label("Edit Home screen", systemImage: "slider.horizontal.3")
                .font(Font.fs(.caption, .semibold))
        }
        .accessibilityIdentifier("home-edit")
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// Trends and Insights used to be a tab; they open from here now.
    private var trendsButton: some View {
        Button { model.showTrends = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line").foregroundStyle(Theme.recoveryGreen)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Trends & Insights").font(Font.fs(.subheadline, .semibold)).foregroundStyle(.white)
                    Text("Every metric over time, the calendar, comparisons").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(Font.fs(.caption, .semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(Glass(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-trends-row")
    }

    // MARK: header & banners

    /// Lives in the navigation bar, so scrolled content passes under a blurred bar instead of the
    /// status bar. While editing it holds Add and Done instead of the day controls.
    @ToolbarContentBuilder private func header(_ proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if editing {
                Button {
                    withAnimation { proxy.scrollTo(Self.addSectionID, anchor: .top) }
                } label: {
                    Image(systemName: "plus").font(Font.fs(.body, .semibold))
                }
                .accessibilityLabel("Add a card")
                .accessibilityIdentifier("home-add-cards")
            } else {
                HStack(spacing: 14) {
                    Button { shift(-1) } label: {
                        Image(systemName: "chevron.left").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Previous day")
                    Button { model.showTrends = true } label: {
                        Image(systemName: "chart.xyaxis.line").foregroundStyle(Theme.recoveryGreen)
                    }
                    .accessibilityLabel("Trends")
                    .accessibilityIdentifier("today-trends")
                }
            }
        }
        ToolbarItem(placement: .principal) {
            if editing {
                Text("Edit Home").font(Font.fs(.headline))
            } else {
                VStack(spacing: 0) {
                    Text(Format.prettyDay(date, today: model.today)).font(Font.fs(.headline))
                    Text(Format.longDay(date)).font(Font.fs(.caption2)).foregroundStyle(Theme.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !editing && live.enabled {
                NavigationLink(value: DetailRoute.liveHeartRate) {
                    Image(systemName: "heart.text.square").foregroundStyle(Theme.heart)
                }
                .accessibilityLabel("Live heart rate")
                .accessibilityIdentifier("open-live-hr")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if editing {
                Button("Done") { finishEditing() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("home-done")
            } else {
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.white)
                }
                .disabled(date >= model.today)
                .opacity(date >= model.today ? 0.3 : 1)
                .accessibilityLabel("Next day")
            }
        }
    }

    /// A sideways swipe on Today: the next or previous day, within the synced days (a bump at
    /// either end).
    private func daySwipe(_ n: Int) {
        let next = Format.addDays(date, n)
        let first = model.days.first?.date ?? model.today
        guard next <= model.today, next >= first else {
            dayEndBump += 1
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { shift(n) }
    }

    private func shift(_ n: Int) {
        let next = Format.addDays(date, n)
        selected = next >= model.today ? nil : next
    }

    @ViewBuilder private var banners: some View {
        if model.needsReconnect {
            Banner(icon: "exclamationmark.triangle.fill",
                   text: "Google access has expired, so new data is not syncing.",
                   color: Theme.recoveryRed, actionTitle: "Reconnect") {
                Task { await model.connect() }
            }
        }
        if let sync = model.status?.sync, !sync.backfillDone, let p = sync.backfillProgress {
            Banner(icon: "arrow.triangle.2.circlepath",
                   text: "Importing your history… \(Int((p * 100).rounded()))% (the server keeps going in the background)",
                   color: Theme.strain)
        }
        if let notice = model.noticeMessage {
            Banner(icon: "info.circle.fill", text: notice, color: Theme.stress, actionTitle: "OK") {
                model.noticeMessage = nil
            }
        }
        if let error = model.errorMessage {
            Banner(icon: "wifi.exclamationmark", text: error, color: Theme.recoveryYellow, actionTitle: "Dismiss") {
                model.errorMessage = nil
            }
        }
    }

    /// When the server last fetched from Google, and when the band last synced with the
    /// phone (the step FitStats cannot speed up).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let page {
                Label("\(page.title) Home · changes by time of day", systemImage: page.icon)
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.top, 4)
    }

    private var updatedText: String {
        guard let fetched = model.status?.sync.lastRecentSyncAt else { return "Not updated yet" }
        return "Updated \(Format.relative(fetched))"
    }

    /// How fresh the data is, at the top: when FitStats last got data from Google and when the
    /// band last synced to the phone; tap to sync now (pull down works too).
    private var syncLine: some View {
        Button {
            Task { await model.syncNow() }
        } label: {
            HStack(spacing: 6) {
                if model.isSyncing {
                    ProgressView().controlSize(.mini)
                    Text("Getting the latest from Google…")
                } else {
                    Image(systemName: bandIsStale ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(bandIsStale ? Theme.recoveryYellow : Theme.recoveryGreen)
                    Text([updatedText, bandText].compactMap { $0 }.joined(separator: " · "))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.clockwise").foregroundStyle(Theme.tertiary)
                }
            }
            .font(Font.fs(.caption))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .overlay(alignment: .bottomLeading) {
                if bandIsStale && !model.isSyncing {
                    Text("Open the Google Health app so your band sends newer data.")
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.recoveryYellow)
                        .padding(.horizontal, 4)
                        .offset(y: 16)
                }
            }
            .padding(.bottom, bandIsStale && !model.isSyncing ? 14 : 0)
        }
        .buttonStyle(.plain)
        .disabled(model.isSyncing)
        .accessibilityLabel(model.isSyncing ? "Syncing" : "\([updatedText, bandText].compactMap { $0 }.joined(separator: ", ")). Sync now")
        .accessibilityIdentifier("today-sync-status")
    }

    /// The band hasn't sent data to the phone for over 30 minutes.
    private var bandIsStale: Bool {
        guard let synced = Format.timestamp(model.band?.lastSyncTime) else { return false }
        return Date().timeIntervalSince(synced) > 30 * 60
    }

    private var bandText: String? {
        guard let band = model.band, Format.timestamp(band.lastSyncTime) != nil else { return nil }
        return "band \(Format.relative(band.lastSyncTime))"
    }
}

/// A Home card at full size: everything the card has. Today shows it for large cards, and its
/// own screen (HomeCardDetailView) opens it from a small or medium one.
struct HomeLargeCard: View {
    let spec: HomeCardSpec
    let date: String
    @EnvironmentObject private var model: AppModel

    private var card: HomeCard { spec.card }

    private var day: DayRecord? { model.daysByDate[date] }
    private var detail: DayDetail? { model.dayDetails[date] }

    var body: some View {
        content(day: day)
    }

    /// Today already skips today-only cards on past days and the day-record cards when there is
    /// no record; the checks here only keep each case safe on its own.
    @ViewBuilder private func content(day: DayRecord?) -> some View {
        switch card {
        case .scores:
            if let day { scoresCard(day) }
        case .tonight:
            if day != nil && date == model.today { SleepPlanCard(plan: model.sleepPlan) }
        case .journal:
            if day != nil { JournalCard(date: date) }
        case .vitals:
            if let day { vitalsCard(day) }
        case .activity:
            if let day { activityCard(day) }
        case .heartRate:
            if let day { heartCard(day) }
        case .workouts:
            if day != nil { workoutsCard }
        case .lastNight:
            LastNightCard(date: date)
        case .recoveryTrend:
            RecoveryTrendCard(date: date, days: spec.days)
        case .hrvTrend:
            HRVTrendCard(date: date, windowDays: spec.days)
        case .restingHrTrend:
            RestingHRTrendCard(date: date, windowDays: spec.days)
        case .stressDay:
            StressDayCard(date: date)
        case .thisWeek:
            ThisWeekCard(date: date, keys: spec.options.metrics)
        case .weeklyZoneMinutes:
            WeeklyZoneMinutesCard(date: date)
        case .streaks:
            StreaksCard(date: date)
        case .topInsight:
            TopInsightCard(date: date)
        case .coachBrief:
            if date == model.today { CoachBriefCard(date: date) }
        case .body:
            BodyCard(date: date)
        case .trainingLoad:
            TrainingLoadHomeCard(date: date)
        case .liveHeartRate:
            if date == model.today { LiveHeartRateHomeCard() }
        case .metric:
            MetricLargeCard(key: spec.metricKey, days: spec.days, date: date)
        case .stack:
            // A stack has no large size (CardSize.sizes); a stored one shows as medium.
            SmartStackView(entries: spec.options.stack ?? [], size: .medium, date: date, rotate: spec.options.rotate ?? true)
        }
    }

    // MARK: scores

    private func strainTarget(_ day: DayRecord) -> ClosedRange<Double>? {
        guard let arr = day.json("score_details")?["strainTarget"]?.array, arr.count == 2,
              let lo = arr[0].double, let hi = arr[1].double, lo <= hi else { return nil }
        return lo...hi
    }

    private func scoresCard(_ day: DayRecord) -> some View {
        let recovery = day.double("recovery")
        let breakdown = ScoreBreakdown(day.json("score_details")?["recovery"])
        let caption = recovery != nil
            ? Theme.recoveryLabel(recovery)
            : (breakdown.status == "calibrating" ? "Calibrating" : "No data")
        return Card {
            NavigationLink(value: DetailRoute.recovery(date)) {
                VStack(spacing: 12) {
                    // Recovery as one big number, like Body age.
                    VStack(spacing: 0) {
                        Text("RECOVERY")
                            .font(Font.fs(.caption, .medium))
                            .tracking(3)
                            .foregroundStyle(Theme.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(recovery.map { "\(Int($0.rounded()))" } ?? "–")
                                .font(Font.fredoka(104, weight: .medium))
                                .foregroundStyle(.white)
                            if recovery != nil {
                                Text("%").font(Font.fredoka(38, weight: .medium)).foregroundStyle(Theme.recoveryColor(recovery))
                            }
                        }
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        Text(caption).font(Font.fs(.headline, .medium)).foregroundStyle(Theme.recoveryColor(recovery))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Recovery \(recovery.map { "\(Int($0.rounded())) percent" } ?? "no data"), \(caption)")
                    recoverySummary(day)
                    if let why = breakdown.recoveryWhy { ScoreWhyLine(why: why) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ring-recovery")
            Divider().overlay(Theme.track)
            HStack(alignment: .top) {
                smallRing(.strain(date), "Strain", day.double("strain"), Theme.strain, Theme.strainEnd,
                          strainTarget(day).map { "Goal \(Int($0.lowerBound))–\(Int($0.upperBound))" },
                          target: strainTarget(day))
                Spacer(minLength: 4)
                smallRing(.sleep(date), "Sleep", day.double("sleep_score"), Theme.sleep, nil,
                          Format.duration(day.double("sleep_asleep_min")))
                Spacer(minLength: 4)
                smallRing(.stress(date), "Stress", day.double("stress"), Theme.stressColor(day.double("stress")), nil,
                          Theme.stressLabel(day.double("stress")))
            }
        }
    }

    private func smallRing(_ route: DetailRoute, _ title: String, _ value: Double?, _ color: Color, _ end: Color?,
                           _ caption: String?, target: ClosedRange<Double>? = nil) -> some View {
        NavigationLink(value: route) {
            ScoreRing(title: title, value: value, maxValue: 100, color: color, endColor: end,
                      caption: caption, size: 88, lineWidth: 9, target: target)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ring-\(title.lowercased())")
    }

    private func recoverySummary(_ day: DayRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            summaryRow("HRV", key: "hrv_rmssd", day).frame(maxWidth: .infinity)
            summaryRow("Resting HR", key: "rhr", day).frame(maxWidth: .infinity)
            summaryRow("Sleep", key: "sleep_asleep_min", day).frame(maxWidth: .infinity)
        }
    }

    private func summaryRow(_ title: String, key: String, _ day: DayRecord) -> some View {
        let def = MetricCatalog.def(key)!
        let value = def.value(day)
        let base = model.baseline(def, before: date)
        var change: Double? = nil
        if let value, let base, base != 0 { change = (value - base) / abs(base) * 100 }
        return VStack(spacing: 3) {
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            Text(def.formatted(value)).font(Font.fredoka(17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            DeltaBadge(change: change, better: def.better)
        }
    }

    // MARK: vitals & activity

    /// Day totals are only compared when the day is complete: today's are "so far" and a
    /// low-wear day's are incomplete. Everything else is compared with the 30-day average.
    private func tile(_ key: String, _ day: DayRecord) -> some View {
        let def = MetricCatalog.def(key)!
        let value = def.value(day)
        let base = model.baseline(def, before: date)
        let soFar = def.isDayTotal && date >= model.today
        var change: Double? = nil
        if model.countsToward(def, day), def.format != .clock, key != "skin_temp_dev", let value, let base, base != 0 {
            change = (value - base) / abs(base) * 100
        }
        // Google's VO2 max can be an estimate from your profile rather than a measurement.
        let estimated = key == "vo2max" && (day.bool("vo2max_estimated") == true || day.string("vo2max_method") == "GOOGLE_DEMOGRAPHIC")
        let avg = base.map { "30d avg \(def.formatted($0, withUnit: false))" }
        // "So far" is said once, in the Activity header.
        return NavigationLink(value: DetailRoute.metric(key)) {
            MetricTile(title: def.shortLabel, shortTitle: def.compactLabel, value: def.formatted(value),
                       sub: soFar ? nil : estimated ? ["estimated", avg].compactMap { $0 }.joined(separator: " · ") : avg,
                       icon: def.icon, color: def.category.color, change: change, better: def.better)
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(soFar ? "so far" : ""))
    }

    @ViewBuilder private func vitalsCard(_ day: DayRecord) -> some View {
        let keys = (spec.options.metrics ?? VitalsGlance.keys).filter(model.recorded.contains)
        if !keys.isEmpty {
            Card {
                SectionHeader(title: "Vitals", subtitle: "Measured overnight, compared with your 30-day average")
                TwoColumnTiles(items: keys) { key in
                    tile(key, day)
                }
            }
        } else {
            Card {
                SectionHeader(title: "Vitals")
                Text("No vitals recorded yet.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func activityCard(_ day: DayRecord) -> some View {
        let steps = day.double("steps")
        let goal = Double(model.status?.settings.stepGoal ?? 10000)
        let keys = (spec.options.metrics ?? ActivityGlance.keys).filter(model.recorded.contains)
        return Card {
            SectionHeader(title: "Activity", subtitle: date >= model.today ? "So far today" : nil)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.number(steps)).font(Font.fredoka(34))
                Text("steps").foregroundStyle(Theme.secondary)
                Spacer()
                Text("Goal \(Format.number(goal))").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
            }
            ProgressView(value: min(1, (steps ?? 0) / max(goal, 1)))
                .tint(Theme.strain)
            stepsComparison(day)
            if !keys.isEmpty {
                TwoColumnTiles(items: keys) { key in
                    tile(key, day)
                }
            }
            if day.bool("low_wear") == true, let wear = day.double("wear_min") {
                Label(lowWearText(wear), systemImage: "exclamationmark.circle")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.recoveryYellow)
            }
        }
    }

    private func lowWearText(_ wear: Double) -> String {
        if wear == 0 { return "No heart rate this day (the band wasn't worn), so its totals are left out of your averages." }
        let usual = model.usualWear(before: date).map { " (usually \(Format.duration($0)))" } ?? ""
        return "Band worn \(Format.duration(wear)) this day\(usual), so its totals are left out of your averages."
    }

    /// Today: steps against what you usually have by the time the data reaches. Other days:
    /// against the 30-day average. Never for an incomplete (low-wear) day.
    @ViewBuilder private func stepsComparison(_ day: DayRecord) -> some View {
        if let steps = day.double("steps"), day.bool("low_wear") != true {
            if date == model.today {
                let minute = model.lastDataMinute(date) ?? model.localMinuteNow
                if let typical = model.typicalSteps(before: date, atMinute: minute) {
                    comparison("Usually \(Format.number(typical)) by \(Format.clock(Double(minute)))", steps, typical)
                }
            } else if let base = model.baseline(MetricCatalog.def("steps")!, before: date) {
                comparison("30-day average \(Format.number(base))", steps, base)
            }
        }
    }

    private func comparison(_ text: String, _ value: Double, _ base: Double) -> some View {
        HStack(spacing: 6) {
            Text(text).font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
            Spacer()
            DeltaBadge(change: base > 0 ? (value - base) / base * 100 : nil, better: .higher)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: heart & workouts

    private func heartCard(_ day: DayRecord) -> some View {
        Card {
            HStack {
                SectionHeader(title: "Heart rate")
                Spacer()
                Text("\(Format.number(day.double("hr_min"))) – \(Format.number(day.double("hr_max"))) bpm")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
            }
            if let hr = detail?.intraday?.hr, hr.contains(where: { $0 != nil }) {
                HeartRateDayChart(hr: hr, rhr: day.double("rhr"))
            } else if detail == nil && model.failedDays.contains(date) {
                Button {
                    Task { await model.loadDay(date, force: true) }
                } label: {
                    Label("Couldn't load the minute data. Tap to try again.", systemImage: "arrow.clockwise")
                        .font(Font.fs(.footnote))
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if detail == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text("No minute-level heart rate for this day.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    @ViewBuilder private var workoutsCard: some View {
        if let exercises = detail?.exercises, !exercises.isEmpty {
            Card {
                SectionHeader(title: "Workouts")
                ForEach(exercises) { x in
                    NavigationLink(value: DetailRoute.workout(date, x.id)) {
                        WorkoutRow(exercise: x, zone: model.zone)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-row")
                }
            }
        } else {
            Card {
                SectionHeader(title: "Workouts")
                if detail == nil && !model.failedDays.contains(date) {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    Text(date == model.today ? "No workouts yet today." : "No workouts this day.")
                        .font(Font.fs(.footnote))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

/// A small or medium Home card opened at full size.
struct HomeCardDetailView: View {
    let spec: HomeCardSpec
    let date: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            HomeLargeCard(spec: spec, date: date)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(spec.card == .metric ? (MetricCatalog.def(spec.metricKey)?.label ?? spec.card.title) : spec.card.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: date) { await model.loadDay(date) }
    }
}

/// Last seven days with a small recovery ring each; tapping one selects it.
/// A day whose journal sheet is open (sheet(item:) needs an Identifiable).
private struct JournalDay: Identifiable {
    let date: String
    var id: String { date }
}

struct WeekStrip: View {
    let today: String
    @Binding var selected: String?
    let recoveryFor: (String) -> Double?

    var body: some View {
        let current = selected ?? today
        HStack(spacing: 4) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let date = Format.addDays(today, -offset)
                let recovery = recoveryFor(date)
                Button {
                    selected = date == today ? nil : date
                } label: {
                    VStack(spacing: 5) {
                        Text(Format.weekdayLetter(date))
                            .font(Font.fs(.caption2, .semibold))
                            .foregroundStyle(Theme.tertiary)
                        ZStack {
                            Circle().stroke(Theme.track, lineWidth: 3)
                            Circle()
                                .trim(from: 0, to: min(1, (recovery ?? 0) / 100))
                                .stroke(Theme.recoveryColor(recovery), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(Format.dayNumber(date)).font(Font.fs(.caption, .semibold))
                        }
                        .frame(width: 32, height: 32)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(date == current ? Color.white.opacity(0.09) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("day-\(date)")
            }
        }
    }
}

struct WorkoutRow: View {
    let exercise: Exercise
    var zone: TimeZone?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.symbol)
                .font(Font.fs(.title3))
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.strain.opacity(0.18)))
                .foregroundStyle(Theme.strain)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.displayName)
                    .font(Font.fs(.subheadline, .semibold))
                Text(subtitle).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(exercise.durationText)
                    .font(Font.fredoka(15, weight: .semibold))
                if let strain = exercise.strain {
                    Text("strain \(Format.number(strain, decimals: 1))").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                } else if let hr = exercise.avgHr {
                    Text("\(Int(hr)) bpm avg").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                }
            }
            Image(systemName: "chevron.right").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let start = Format.timestamp(exercise.startTime) { parts.append(Format.time(start, zone: zone)) }
        if let kcal = exercise.calories { parts.append("\(Int(kcal)) kcal") }
        if let m = exercise.distanceM, m > 0 { parts.append(String(format: "%.2f km", m / 1000)) }
        if let azm = exercise.azm, azm > 0 { parts.append("\(Int(azm)) AZM") }
        // Only an unusual origin is named here; a workout started on a device is the norm.
        if exercise.recordingMethod != "ACTIVELY_MEASURED", let origin = exercise.originLabel { parts.append(origin) }
        return parts.joined(separator: " · ")
    }
}
