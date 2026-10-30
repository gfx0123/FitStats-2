import SwiftUI

enum TrainingRoute: Hashable {
    case routine(String)
    case log(String)
    case library
    /// An exercise's muscles and your sessions of it, by name.
    case exercise(String)
}

/// The Training tab: start a workout from a routine (or an empty one), the routines you keep
/// (yours and the coach's), and the history of what you logged here and what the band recorded.
struct TrainingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @State private var editingRoutine: Routine?
    @State private var showAllHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let error = model.trainingError {
                        Banner(icon: "exclamationmark.triangle.fill", text: error, color: Theme.recoveryYellow, actionTitle: "OK") {
                            model.trainingError = nil
                        }
                    }
                    if let active = workout.log, !workout.presented { resumeCard(active) }
                    weekCard
                    AskCoachRow(prompts: [
                        ("sparkles", "Make me a routine", "Make me a routine that fits my recent training, recovery and goals, and save it to Training."),
                        ("checklist", "Review my last workout", "Review my last workout and tell me what to change next time."),
                        ("arrow.up.right", "How can I progress?", "How can I improve my training from here?"),
                    ])
                    if !model.library.exercises.isEmpty { MusclesWeekCard() }
                    routinesSection
                    historySection
                    if let stats = model.stats {
                        TrainingLoadCard(load: stats.load, today: stats.today)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .refreshable { await model.refreshTraining() }
            .screenBackground()
            .navigationTitle("Training")
            .swipeBackFromAnywhere()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingRoutine = Routine.new() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New routine")
                        .accessibilityIdentifier("training-new-routine")
                }
            }
            .navigationDestination(for: TrainingRoute.self) { route in
                switch route {
                case .routine(let id): RoutineDetailView(routineID: id)
                case .log(let id): WorkoutLogDetailView(logID: id)
                case .library: ExerciseLibraryView()
                case .exercise(let name): ExerciseInfoView(name: name)
                }
            }
            .navigationDestination(for: DetailRoute.self) { DetailDestination(route: $0) }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(draft: routine).environmentObject(model)
            }
            .fullScreenCover(isPresented: $workout.presented) {
                WorkoutLoggerView().environmentObject(model).environmentObject(workout)
            }
        }
    }

    // MARK: sections

    private func resumeCard(_ active: WorkoutLog) -> some View {
        Button {
            workout.presented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "timer").font(Font.fs(.title3)).foregroundStyle(Theme.strain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.editing ? "Editing \(active.name)" : "\(active.name) in progress")
                        .font(Font.fs(.subheadline, .semibold)).foregroundStyle(.white)
                    Text("\(active.doneSetCount) sets done · tap to go back to it")
                        .font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(Font.fs(.caption, .semibold)).foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.strain.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("training-resume")
    }

    /// This week (Monday on): sessions logged, sets, and the band's workouts.
    private var weekCard: some View {
        let monday = Self.monday(of: model.today)
        let logs = model.workoutLogs.filter { $0.date >= monday }
        let band = model.bandWorkouts.filter { $0.date >= monday }
        let strain = model.days.filter { $0.date >= monday }.compactMap { $0.double("strain") }
        return Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "This week")
                Spacer()
                Button {
                    workout.start(WorkoutLog.start(from: nil, date: model.today, previous: model.workoutLogs))
                } label: {
                    Label("Empty workout", systemImage: "plus.circle.fill").font(Font.fs(.caption, .semibold))
                }
                .disabled(workout.log != nil)
                .accessibilityIdentifier("training-start-empty")
            }
            weekStrip(monday: monday)
            HStack(alignment: .top) {
                stat("Logged", "\(logs.count)", logs.count == 1 ? "workout" : "workouts")
                Spacer()
                stat("Sets", "\(logs.reduce(0) { $0 + $1.doneSetCount })", "done")
                Spacer()
                stat("Band", "\(band.count)", band.count == 1 ? "workout" : "workouts")
                Spacer()
                stat("Avg strain", strain.isEmpty ? "–" : Format.number(strain.reduce(0, +) / Double(strain.count)), "a day")
            }
        }
    }

    /// Monday to Sunday: a filled dot on days with a workout logged here, the sport's icon on days
    /// only the band recorded one, today ringed.
    private func weekStrip(monday: String) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let day = Format.addDays(monday, i)
                let logged = model.workoutLogs.contains { $0.date == day }
                let band = model.bandWorkouts.first { $0.date == day }
                VStack(spacing: 5) {
                    Text(Format.weekdayLetter(day))
                        .font(Font.fs(.caption2, .semibold))
                        .foregroundStyle(day == model.today ? .white : Theme.tertiary)
                    ZStack {
                        if logged {
                            Circle().fill(Theme.strain)
                            Image(systemName: "dumbbell.fill").font(Font.fredoka(11, weight: .bold)).foregroundStyle(.white)
                        } else if let band {
                            Circle().fill(Theme.heart.opacity(0.2))
                            Image(systemName: band.symbol).font(Font.fredoka(12, weight: .semibold)).foregroundStyle(Theme.heart)
                        } else {
                            Circle().strokeBorder(day > model.today ? Theme.track : Color.white.opacity(0.16), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .overlay {
                        if day == model.today {
                            Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5).padding(-4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Format.longDay(day)): \(logged ? "workout logged" : band != nil ? "band workout" : "no workout")")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("training-week-strip")
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            Text(value).font(Font.fredoka(22))
            Text(unit).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Routines", subtitle: model.routines.isEmpty ? nil : "Swipe through them; tap one to see it, hold it to move it")
            if model.routines.isEmpty {
                Card {
                    EmptyStateView(icon: "list.bullet.clipboard", title: "No routines yet",
                                   message: "Make one with the + button, or ask the coach to make one for you.")
                }
            }
            // Side by side, swiped through, each with its own Start button.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(model.routines.enumerated()), id: \.element.id) { item in
                        routineTile(item.element, index: item.offset)
                    }
                }
                // Every tile as tall as the tallest.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routineTile(_ routine: Routine, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: TrainingRoute.routine(routine.id)) {
                RoutineCard(routine: routine, lastDone: model.workoutLogs.first { $0.routineId == routine.id }?.date, bare: true)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if index > 0 {
                    Button("Move up", systemImage: "arrow.up") {
                        Task { await model.moveRoutines(from: IndexSet(integer: index), to: index - 1) }
                    }
                }
                if index < model.routines.count - 1 {
                    Button("Move down", systemImage: "arrow.down") {
                        Task { await model.moveRoutines(from: IndexSet(integer: index), to: index + 2) }
                    }
                }
                Button("Edit", systemImage: "pencil") { editingRoutine = routine }
            }
            .accessibilityIdentifier("routine-\(routine.name)")
            Button {
                workout.start(WorkoutLog.start(from: routine, date: model.today, previous: model.workoutLogs))
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(Font.fs(.subheadline, .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.recoveryGreen))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(routine.exercises.isEmpty || workout.log != nil)
            .accessibilityIdentifier("routine-quick-start-\(routine.name)")
        }
        .padding(16)
        .frame(width: 236, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Glass(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    /// What you logged here and what the band recorded, newest first.
    @ViewBuilder private var historySection: some View {
        let pairs = model.workoutPairs
        let entries = HistoryEntry.merged(logs: model.workoutLogs, band: model.bandWorkouts, pairs: pairs)
        let shown = showAllHistory ? entries : Array(entries.prefix(8))
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "History", subtitle: "Logged here, and recorded by your band")
            if entries.isEmpty {
                Card {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "No workouts yet",
                                   message: "Workouts you log here and the ones your band records show up here.")
                }
            } else {
                ForEach(HistoryWeek.group(shown)) { week in
                    Text(weekTitle(week.monday))
                        .font(Font.fs(.caption, .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.top, 4)
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(week.entries.enumerated()), id: \.element.id) { item in
                                if item.offset > 0 { Divider().overlay(Theme.track).padding(.leading, 56) }
                                historyRow(item.element, pairs: pairs)
                            }
                        }
                    }
                }
                if entries.count > shown.count || showAllHistory {
                    Button(showAllHistory ? "Show fewer" : "Show all \(entries.count)") { showAllHistory.toggle() }
                        .font(Font.fs(.footnote, .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func historyRow(_ entry: HistoryEntry, pairs: [String: Exercise]) -> some View {
        switch entry {
        case .log(let log):
            // A session the band recorded too: one row, with its heart rate and strain.
            let band = pairs[log.id]
            NavigationLink(value: TrainingRoute.log(log.id)) {
                HistoryRow(icon: "dumbbell.fill", tint: Theme.strain, title: log.name, date: log.date,
                           detail: [log.minutes.map { Format.duration($0) }, "\(log.doneSetCount) sets",
                                    log.volumeKg.map { "\(Format.number($0)) kg" },
                                    band?.avgHr.map { "♥ \(Int($0.rounded())) bpm" },
                                    band?.strain.map { "strain \(Format.number($0, decimals: 1))" }].compactMap { $0 }.joined(separator: " · "),
                           badge: band == nil ? "Logged" : "Logged + band")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("history-log")
        case .band(let x):
            NavigationLink(value: DetailRoute.workout(x.date, x.id)) {
                HistoryRow(icon: x.symbol, tint: Theme.heart, title: x.displayName, date: x.date,
                           detail: [x.durationS.map { Format.duration($0 / 60) }, x.avgHr.map { "\(Int($0.rounded())) bpm" },
                                    x.strain.map { "strain \(Format.number($0))" }].compactMap { $0 }.joined(separator: " · "),
                           badge: "Band")
            }
            .buttonStyle(.plain)
        }
    }

    /// "This week", "Last week", "Oct 5–11", "Sep 28 – Oct 4".
    private func weekTitle(_ monday: String) -> String {
        let thisWeek = Self.monday(of: model.today)
        if monday == thisWeek { return "This week" }
        if monday == Format.addDays(thisWeek, -7) { return "Last week" }
        let sunday = Format.addDays(monday, 6)
        return monday.prefix(7) == sunday.prefix(7)
            ? "\(Format.monthDay(monday))–\(Format.dayNumber(sunday))"
            : "\(Format.monthDay(monday)) – \(Format.monthDay(sunday))"
    }

    /// Monday of the week `ymd` is in.
    static func monday(of ymd: String) -> String {
        guard let d = Format.date(ymd) else { return ymd }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Format.utc
        let weekday = (cal.component(.weekday, from: d) + 5) % 7 // Monday = 0
        return Format.addDays(ymd, -weekday)
    }
}

enum HistoryEntry: Identifiable {
    case log(WorkoutLog)
    case band(Exercise)

    var date: String {
        switch self {
        case .log(let l): return l.date
        case .band(let x): return x.date
        }
    }

    var id: String {
        switch self {
        case .log(let l): return "log-\(l.id)"
        case .band(let x): return "band-\(x.id)"
        }
    }

    private var sortKey: String {
        switch self {
        case .log(let l): return "\(l.date) \(l.startedAt ?? "")"
        case .band(let x): return "\(x.date) \(x.startTime)"
        }
    }

    /// Logged workouts and the band's, newest first; a band workout paired with a logged one
    /// (WorkoutPairing) is shown in that one's row instead of its own.
    static func merged(logs: [WorkoutLog], band: [Exercise], pairs: [String: Exercise] = [:]) -> [HistoryEntry] {
        let paired = Set(pairs.values.map(\.id))
        return (logs.map(HistoryEntry.log) + band.filter { !paired.contains($0.id) }.map(HistoryEntry.band)).sorted { $0.sortKey > $1.sortKey }
    }
}

/// History entries of one week (Monday on), newest first like the entries.
struct HistoryWeek: Identifiable {
    let monday: String
    var entries: [HistoryEntry]
    var id: String { monday }

    @MainActor
    static func group(_ entries: [HistoryEntry]) -> [HistoryWeek] {
        var weeks: [HistoryWeek] = []
        for entry in entries {
            let monday = TrainingView.monday(of: entry.date)
            if weeks.last?.monday == monday {
                weeks[weeks.count - 1].entries.append(entry)
            } else {
                weeks.append(HistoryWeek(monday: monday, entries: [entry]))
            }
        }
        return weeks
    }
}

struct HistoryRow: View {
    let icon: String
    let tint: Color
    let title: String
    let date: String
    let detail: String
    let badge: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(Font.fs(.subheadline))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(Font.fs(.subheadline, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(badge)
                        .font(Font.fs(.caption2, .semibold))
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                Text(detail.isEmpty ? Format.prettyDay(date, today: model.today) : "\(Format.prettyDay(date, today: model.today)) · \(detail)")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(Font.fs(.caption2, .semibold)).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

struct RoutineCard: View {
    let routine: Routine
    let lastDone: String?
    /// Inside a tile that draws its own card.
    var bare = false
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(padding: bare ? 0 : 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(routine.name).font(Font.fs(.headline)).foregroundStyle(.white).lineLimit(1)
                if routine.byCoach { CoachBadge() }
                Spacer()
                Image(systemName: "chevron.right").font(Font.fs(.caption2, .semibold)).foregroundStyle(Theme.tertiary)
            }
            Text(routine.exercises.isEmpty ? "No exercises yet" : routine.exercises.prefix(4).map(\.name).joined(separator: " · ") + (routine.exercises.count > 4 ? " · +\(routine.exercises.count - 4)" : ""))
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Text(lastDone.map { "Last done \(Format.prettyDay($0, today: model.today).lowercasedIfDay)" } ?? "Not done yet")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
        .environment(\.homeCardBare, bare)
    }
}

struct CoachBadge: View {
    var body: some View {
        Label("Coach", systemImage: "sparkles")
            .font(Font.fs(.caption2, .semibold))
            .foregroundStyle(Theme.sleep)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.sleep.opacity(0.16)))
            .accessibilityLabel("Made by the coach")
    }
}

/// Buttons that open the Coach with a question about this part of the app in its message
/// field, ready to finish and send.
struct AskCoachRow: View {
    /// Icon, button title, the text put in the message field.
    let prompts: [(String, String, String)]
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts.indices, id: \.self) { i in
                    let prompt = prompts[i]
                    Button { model.askCoach(prompt.2) } label: {
                        Label(prompt.1, systemImage: prompt.0)
                            .font(Font.fs(.footnote, .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.sleep.opacity(0.16)))
                            .foregroundStyle(Theme.sleep)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ask-coach-\(prompt.1)")
                }
            }
        }
    }
}

extension String {
    /// "Today" → "today", "Yesterday" → "yesterday"; other dates stay as they are.
    var lowercasedIfDay: String {
        self == "Today" || self == "Yesterday" ? lowercased() : self
    }
}
