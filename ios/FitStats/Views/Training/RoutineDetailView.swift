import SwiftUI

/// A routine: its exercises with their targets and what you lifted last time, a button to start
/// it, and the workouts logged with it.
struct RoutineDetailView: View {
    let routineID: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Routine?

    var body: some View {
        let routine = model.routines.first { $0.id == routineID }
        ScrollView {
            VStack(spacing: 14) {
                if let routine {
                    header(routine)
                    startButton(routine)
                    exercisesCard(routine)
                    WorkoutMusclesCard(title: "Muscles it works", sets: model.library.sets(in: routine), library: model.library)
                    AskCoachRow(prompts: [
                        ("wand.and.stars", "Improve this routine", "About my routine “\(routine.name)”: how would you improve it?"),
                        ("arrow.up.right", "What weights next time?", "About my routine “\(routine.name)”: what should I lift next time, set by set?"),
                    ])
                    recentCard(routine)
                } else {
                    Card { EmptyStateView(icon: "questionmark", title: "Routine not found", message: "It may have been deleted.") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(routine?.name ?? "Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let routine {
                    Button("Edit") { editing = routine }
                        .accessibilityIdentifier("routine-edit")
                }
            }
        }
        .sheet(item: $editing) { RoutineEditorView(draft: $0).environmentObject(model) }
        // Deleted in the editor: back to the list.
        .onChange(of: routine == nil) { _, gone in if gone { dismiss() } }
    }

    private func header(_ routine: Routine) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(routine.name).font(Font.fs(.title3, .semibold))
                if routine.byCoach { CoachBadge() }
                Spacer()
            }
            let sets = routine.exercises.reduce(0) { $0 + ($1.sets ?? 0) }
            let logs = model.workoutLogs.filter { $0.routineId == routine.id }
            let minutes = logs.compactMap(\.minutes)
            HStack(spacing: 18) {
                fact("\(routine.exercises.count)", routine.exercises.count == 1 ? "exercise" : "exercises")
                if sets > 0 { fact("\(sets)", "sets") }
                if !minutes.isEmpty { fact(Format.duration(minutes.reduce(0, +) / Double(minutes.count)), "usually") }
                fact(logs.first.map { Format.prettyDay($0.date, today: model.today) } ?? "Not yet", "last done")
            }
            if let notes = routine.notes, !notes.isEmpty {
                Text(notes).font(Font.fs(.footnote)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Font.fs(.subheadline, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(label).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
    }

    @ViewBuilder private func startButton(_ routine: Routine) -> some View {
        if let active = workout.log {
            Button { workout.presented = true } label: {
                Label(active.routineId == routine.id ? "Back to this workout" : "Finish \(active.name) first", systemImage: "timer")
                    .font(Font.fs(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.strain.opacity(0.2)))
                    .foregroundStyle(Theme.strain)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("routine-resume")
        } else {
            Button {
                workout.start(WorkoutLog.start(from: routine, date: model.today, previous: model.workoutLogs))
            } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(Font.fs(.headline))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.recoveryGreen))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(routine.exercises.isEmpty)
            .accessibilityIdentifier("routine-start")
        }
    }

    private func exercisesCard(_ routine: Routine) -> some View {
        Card {
            SectionHeader(title: "Exercises")
            if routine.exercises.isEmpty {
                Text("No exercises yet. Tap Edit to add some.").font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
            }
            ForEach(Array(routine.exercises.enumerated()), id: \.element.id) { item in
                if item.offset > 0 { Divider().overlay(Theme.track) }
                exerciseRow(item.element)
            }
        }
    }

    private func exerciseRow(_ e: RoutineExercise) -> some View {
        let muscles = model.library.muscles(for: e.name, chosen: e.muscles)
        return NavigationLink(value: TrainingRoute.exercise(e.name)) {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: e.kind.icon)
                .font(Font.fs(.subheadline))
                .foregroundStyle(Theme.strain)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.strain.opacity(0.15)))
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(Font.fs(.subheadline, .semibold))
                if !e.plan.isEmpty {
                    Text(e.plan).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                }
                if !muscles.primary.isEmpty {
                    Text(muscleLine(muscles.primary, muscles.secondary))
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.muscle)
                }
                if let last = WorkoutLog.lastSets(of: e.name, in: model.workoutLogs) {
                    Text("Last time: \(LoggedSet.compact(last))")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(2)
                }
                if let notes = e.notes, !notes.isEmpty {
                    Text(notes).font(Font.fs(.caption)).foregroundStyle(Theme.secondary).italic()
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(Font.fs(.caption2, .semibold)).foregroundStyle(Theme.tertiary)
        }
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("routine-exercise-\(e.name)")
    }

    /// "Quads, glutes · helps hamstrings".
    private func muscleLine(_ primary: [String], _ secondary: [String]) -> String {
        let main = primary.map { model.library.label($0) }.joined(separator: ", ")
        guard !secondary.isEmpty else { return main }
        return "\(main) · helps \(secondary.map { model.library.label($0).lowercased() }.joined(separator: ", "))"
    }

    @ViewBuilder private func recentCard(_ routine: Routine) -> some View {
        let logs = model.workoutLogs.filter { $0.routineId == routine.id }
        if !logs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Done \(logs.count) \(logs.count == 1 ? "time" : "times")")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(logs.prefix(6).enumerated()), id: \.element.id) { item in
                            if item.offset > 0 { Divider().overlay(Theme.track).padding(.leading, 56) }
                            let log = item.element
                            NavigationLink(value: TrainingRoute.log(log.id)) {
                                HistoryRow(icon: "dumbbell.fill", tint: Theme.strain, title: log.name, date: log.date,
                                           detail: [log.minutes.map { Format.duration($0) }, "\(log.doneSetCount) sets",
                                                    log.volumeKg.map { "\(Format.number($0)) kg" }].compactMap { $0 }.joined(separator: " · "),
                                           badge: log.effort.map { "Effort \($0)" } ?? "Logged")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
