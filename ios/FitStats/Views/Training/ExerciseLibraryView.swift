import Charts
import SwiftUI

/// The exercise library: search, filter by muscle, and see what each exercise works. With
/// `onPick` it picks an exercise to add (to a routine or the workout being logged), including
/// one of your own by the name you typed.
struct ExerciseLibraryView: View {
    var onPick: ((String, ExerciseKind) -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var muscle: String?

    private struct ExerciseGroup: Identifiable {
        let title: String
        let exercises: [LibraryExercise]
        var id: String { title }
    }

    /// The library's categories in order; older servers send none, so their exercises are
    /// grouped by their first main muscle.
    private static let categories = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Glutes", "Core", "Full body", "Calisthenics", "Cardio", "Sports", "Mobility"]
    private static let regions: [String: String] = [
        "chest": "Chest", "upper_back": "Back", "lats": "Back", "lower_back": "Back", "shoulders": "Shoulders",
        "biceps": "Arms", "triceps": "Arms", "forearms": "Arms", "quads": "Legs", "hamstrings": "Legs", "adductors": "Legs",
        "calves": "Legs", "glutes": "Glutes", "abs": "Core", "obliques": "Core",
    ]

    private static func category(_ e: LibraryExercise) -> String {
        if let c = e.category { return c }
        if e.kind == "cardio" { return "Cardio" }
        if e.kind == "mobility" { return "Mobility" }
        return regions[e.primary.first ?? ""] ?? "Full body"
    }

    var body: some View {
        let library = model.library
        let groups = groups(library)
        List {
            Section {
                muscleFilter(library)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            if onPick != nil, !typed.isEmpty, library.find(typed) == nil {
                Section {
                    Button {
                        pick(typed, .strength)
                    } label: {
                        Label("Add “\(typed)” as your own exercise", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("library-custom")
                } footer: {
                    Text("Not in the library. You can choose the muscles it works in the routine's exercise settings.")
                }
            }
            if library.exercises.isEmpty {
                Text("The exercise library comes from your server. Update it (server 1.8.0 or later) to see which muscles each exercise works.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.exercises) { e in row(e, library: library) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .listSectionSpacing(.compact)
        .contentMargins(.top, 6, for: .scrollContent)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
        .navigationTitle(onPick == nil ? "Exercise library" : "Add exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if onPick != nil { Button("Cancel") { dismiss() } }
            }
        }
        .navigationDestination(for: LibraryExercise.self) { ExerciseInfoView(name: $0.name) }
    }

    private var typed: String { search.trimmingCharacters(in: .whitespaces) }

    private func groups(_ library: ExerciseLibrary) -> [ExerciseGroup] {
        let matching = library.exercises.filter { e in
            (muscle == nil || e.primary.contains(muscle!) || e.secondary.contains(muscle!)) &&
                (typed.isEmpty || ([e.name] + e.aliases).contains { $0.localizedCaseInsensitiveContains(typed) })
        }
        let byCategory = Dictionary(grouping: matching, by: Self.category)
        let order = Self.categories + byCategory.keys.filter { !Self.categories.contains($0) }.sorted()
        return order.compactMap { title in
            byCategory[title].map { ExerciseGroup(title: title, exercises: $0) }
        }
    }

    private func muscleFilter(_ library: ExerciseLibrary) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip("All", selected: muscle == nil) { muscle = nil }
                ForEach(library.muscles) { m in
                    filterChip(m.label, selected: muscle == m.id) { muscle = muscle == m.id ? nil : m.id }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Font.fs(.footnote, .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.muscle : Color.white.opacity(0.08)))
                .foregroundStyle(selected ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func row(_ e: LibraryExercise, library: ExerciseLibrary) -> some View {
        let label = HStack(spacing: 12) {
            BodyMapThumbnail(levels: Dictionary(uniqueKeysWithValues: e.primary.map { ($0, 1.0) } + e.secondary.filter { !e.primary.contains($0) }.map { ($0, 0.4) }))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(Font.fs(.subheadline, .semibold)).foregroundStyle(.white)
                Text(Self.musclesText(e, library: library))
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        if onPick != nil {
            Button { pick(e.name, e.exerciseKind) } label: { label }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-\(e.name)")
        } else {
            NavigationLink(value: e) { label }
                .accessibilityIdentifier("library-\(e.name)")
        }
    }

    /// "Quads, glutes · helps hamstrings · Barbell".
    static func musclesText(_ e: LibraryExercise, library: ExerciseLibrary) -> String {
        var parts: [String] = []
        if !e.primary.isEmpty { parts.append(e.primary.map(library.label).joined(separator: ", ")) }
        if !e.secondary.isEmpty { parts.append("helps \(e.secondary.map { library.label($0).lowercased() }.joined(separator: ", "))") }
        if e.equipment != "None" { parts.append(e.equipment) }
        return parts.joined(separator: " · ")
    }

    private func pick(_ name: String, _ kind: ExerciseKind) {
        onPick?(name, kind)
        dismiss()
    }
}

/// One exercise: the muscles it works on the body map, and your sessions of it.
struct ExerciseInfoView: View {
    let name: String
    @EnvironmentObject private var model: AppModel

    private struct Session: Identifiable {
        let date: String
        let sets: [LoggedSet]
        var id: String { date + "\(sets.count)" }
        var heaviest: Double? { sets.compactMap(\.weightKg).max() }
    }

    var body: some View {
        let library = model.library
        let entry = library.find(name)
        let muscles = library.muscles(for: name, chosen: nil)
        let equipment = entry.map { " Equipment: \($0.equipment.lowercased())." } ?? ""
        let sessions = model.workoutLogs.compactMap { log -> Session? in
            guard let e = log.exercises.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }), !e.doneSets.isEmpty else { return nil }
            return Session(date: log.date, sets: e.doneSets)
        }
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    SectionHeader(title: "Muscles worked")
                    if muscles.primary.isEmpty && muscles.secondary.isEmpty {
                        Text("The library doesn't know this exercise.").font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
                    } else {
                        BodyMapView(levels: Dictionary(uniqueKeysWithValues: muscles.primary.map { ($0, 1.0) } + muscles.secondary.filter { !muscles.primary.contains($0) }.map { ($0, 0.4) }))
                        MuscleChips(primary: muscles.primary, secondary: muscles.secondary, library: library)
                        Text("Filled: the muscles that do most of the work. Outlined: the ones that help.\(equipment)")
                            .font(Font.fs(.caption))
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                progressCard(sessions)
                if !sessions.isEmpty {
                    Card {
                        SectionHeader(title: "Your sessions", subtitle: "\(sessions.count) logged in the last year")
                        ForEach(sessions.prefix(10)) { s in
                            HStack(alignment: .firstTextBaseline) {
                                Text(Format.prettyDay(s.date, today: model.today)).font(Font.fs(.subheadline)).foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(LoggedSet.compact(s.sets)).font(Font.fs(.subheadline)).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(entry?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskCoachButton(text: "About the exercise “\(entry?.name ?? name)”: how am I progressing, and how should I train it next?")
            }
        }
    }

    /// The heaviest set of each session, when there are at least two with a weight.
    @ViewBuilder private func progressCard(_ sessions: [Session]) -> some View {
        let points = sessions.compactMap { s -> (Date, Double)? in
            guard let d = Format.chartDate(s.date), let kg = s.heaviest else { return nil }
            return (d, kg)
        }
        if points.count >= 2 {
            Card {
                SectionHeader(title: "Heaviest set", subtitle: "Per session, kg")
                Chart {
                    ForEach(points.indices, id: \.self) { i in
                        LineMark(x: .value("Day", points[i].0), y: .value("kg", points[i].1))
                            .foregroundStyle(Theme.muscle)
                        PointMark(x: .value("Day", points[i].0), y: .value("kg", points[i].1))
                            .foregroundStyle(Theme.muscle)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 150)
            }
        }
    }
}
