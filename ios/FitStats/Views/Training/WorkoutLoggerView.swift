import SwiftUI
import UIKit

/// Logging a workout set by set: the weight and reps (or minutes and km) of each set, ticked off
/// as they are done. Every change is kept on the phone (ActiveWorkout), so closing the screen or
/// the app doesn't lose it. Also changes a saved workout (`workout.editing`).
struct WorkoutLoggerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @State private var finishing = false
    @State private var addingExercise = false
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            if workout.log != nil {
                content(logBinding)
            }
        }
    }

    /// The workout being logged. Once it is saved or discarded the sheets above it can still
    /// redraw while they close: they read a blank workout then, and their writes are dropped.
    private var logBinding: Binding<WorkoutLog> {
        let w = workout
        return Binding(get: { w.log ?? Self.blank }, set: { new in
            DebugLog.note("logger: workout saved locally, \(new.doneSetCount) sets done, \(Int(new.volumeKg ?? 0)) kg\(w.log == nil ? " (dropped: no workout)" : "")")
            if w.log != nil { w.log = new }
        })
    }

    private static let blank = WorkoutLog(id: "", date: "", startedAt: nil, endedAt: nil, routineId: nil, name: "",
                                          exercises: [], notes: nil, effort: nil)

    /// One exercise of the workout, found by id, so removing another one never leaves a row
    /// pointing past the end of the list.
    private func exerciseBinding(_ log: Binding<WorkoutLog>, _ id: UUID) -> Binding<LoggedExercise> {
        Binding(get: { log.wrappedValue.exercises.first { $0.id == id } ?? LoggedExercise(name: "", sets: []) },
                set: { new in
                    if let i = log.wrappedValue.exercises.firstIndex(where: { $0.id == id }) { log.wrappedValue.exercises[i] = new }
                })
    }

    private func content(_ log: Binding<WorkoutLog>) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                header(log)
                ForEach(log.wrappedValue.exercises) { exercise in
                    LoggedExerciseCard(exercise: exerciseBinding(log, exercise.id),
                                       last: WorkoutLog.lastSets(of: exercise.name, in: model.workoutLogs.filter { $0.id != log.wrappedValue.id }),
                                       onRemove: { log.wrappedValue.exercises.removeAll { $0.id == exercise.id } })
                }
                Button { addingExercise = true } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .font(Font.fs(.subheadline, .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Glass(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(log.wrappedValue.exercises.count >= 40)
                .accessibilityIdentifier("logger-add-exercise")
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle(workout.editing ? "Edit workout" : "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if workout.editing {
                    Button("Cancel") { confirmDiscard = true }
                } else {
                    Button { workout.presented = false } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Close, keep going later")
                        .accessibilityIdentifier("logger-close")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(workout.editing ? "Save" : "Finish") {
                    dismissKeyboard()
                    finishing = true
                }
                .fontWeight(.semibold)
                .disabled(log.wrappedValue.exercises.isEmpty)
                .accessibilityIdentifier("logger-finish")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .sheet(isPresented: $addingExercise) {
            NavigationStack {
                ExerciseLibraryView { name, kind in
                    let last = WorkoutLog.lastSets(of: name, in: model.workoutLogs)
                    let count = kind.timed ? 1 : max(1, last?.count ?? 3)
                    let sets = (0..<count).map { i in
                        LoggedSet(reps: last?[safe: i]?.reps, weightKg: last?[safe: i]?.weightKg,
                                  durationMin: last?[safe: i]?.durationMin, distanceKm: last?[safe: i]?.distanceKm)
                    }
                    log.wrappedValue.exercises.append(LoggedExercise(name: name, kind: kind, sets: sets, notes: nil))
                }
            }
            .environmentObject(model)
        }
        .sheet(isPresented: $finishing) {
            FinishWorkoutSheet(log: log)
                .environmentObject(model)
                .environmentObject(workout)
        }
        .confirmationDialog(workout.editing ? "Discard your changes?" : "Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(workout.editing ? "Discard changes" : "Discard workout", role: .destructive) { workout.discard() }
        } message: {
            Text(workout.editing ? "The saved workout stays as it was." : "Nothing of it is saved.")
        }
    }

    private func header(_ log: Binding<WorkoutLog>) -> some View {
        Card {
            TextField("Name", text: log.name)
                .font(Font.fs(.title3, .semibold))
                .accessibilityIdentifier("logger-name")
            HStack(spacing: 14) {
                if workout.editing {
                    Label(Format.longDay(log.wrappedValue.date), systemImage: "calendar")
                } else if let start = Format.timestamp(log.wrappedValue.startedAt) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Label(Self.elapsed(from: start, to: context.date), systemImage: "timer")
                            .monospacedDigit()
                    }
                }
                Label("\(log.wrappedValue.doneSetCount) sets", systemImage: "checkmark.circle")
                if let v = log.wrappedValue.volumeKg {
                    Label("\(Format.number(v)) kg", systemImage: "scalemass")
                }
                Spacer(minLength: 0)
                if !workout.editing {
                    Menu {
                        Button("Discard workout", systemImage: "trash", role: .destructive) { confirmDiscard = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(Font.fs(.title3))
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("logger-more")
                }
            }
            .font(Font.fs(.footnote))
            .foregroundStyle(Theme.secondary)
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// One exercise being logged: its sets with weight and reps (or minutes and km), each ticked
/// when done, and what was lifted last time.
private struct LoggedExerciseCard: View {
    @Binding var exercise: LoggedExercise
    let last: [LoggedSet]?
    let onRemove: () -> Void
    @State private var showNotes = false

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(exercise.name, systemImage: exercise.kind.icon)
                    .font(Font.fs(.headline))
                    .labelStyle(.titleAndIcon)
                Spacer()
                Menu {
                    Button(showNotes || exercise.notes != nil ? "Notes" : "Add a note", systemImage: "note.text") { showNotes = true }
                    Button("Remove exercise", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis").font(Font.fs(.body, .semibold)).frame(width: 32, height: 24)
                }
                .accessibilityLabel("\(exercise.name) options")
            }
            if let last {
                Text("Last time: \(LoggedSet.compact(last))")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(2)
            }
            columns
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { item in
                SetRow(number: item.offset + 1, set: setBinding(item.element.id), timed: exercise.kind.timed)
            }
            HStack {
                Button {
                    var next = exercise.sets.last ?? LoggedSet()
                    next.id = UUID()
                    next.done = false
                    exercise.sets.append(next)
                } label: {
                    Label("Add set", systemImage: "plus").font(Font.fs(.footnote, .semibold))
                }
                .disabled(exercise.sets.count >= 30)
                .accessibilityIdentifier("logger-add-set")
                Spacer()
                if exercise.sets.count > 1 {
                    Button {
                        exercise.sets.removeLast()
                    } label: {
                        Label("Remove set", systemImage: "minus").font(Font.fs(.footnote, .semibold))
                    }
                    .tint(Theme.secondary)
                }
            }
            .buttonStyle(.borderless)
            if showNotes || exercise.notes != nil {
                TextField("Notes for this exercise", text: Binding(get: { exercise.notes ?? "" }, set: { exercise.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .font(Font.fs(.footnote))
                    .lineLimit(1...4)
            }
        }
    }

    /// A set found by id (see WorkoutLoggerView.exerciseBinding).
    private func setBinding(_ id: UUID) -> Binding<LoggedSet> {
        let exercise = $exercise
        return Binding(get: { exercise.wrappedValue.sets.first { $0.id == id } ?? LoggedSet() },
                       set: { new in
                           let i = exercise.wrappedValue.sets.firstIndex(where: { $0.id == id })
                           DebugLog.note("logger: set \(i.map { "\($0 + 1)" } ?? "not found") of \(exercise.wrappedValue.name) -> \(new.summary)\(new.done ? " done" : "")")
                           if let i { exercise.wrappedValue.sets[i] = new }
                       })
    }

    private var columns: some View {
        HStack(spacing: 8) {
            Text("SET").frame(width: 34, alignment: .leading)
            Text(exercise.kind.timed ? "MIN" : "KG").frame(maxWidth: .infinity)
            Text(exercise.kind.timed ? "KM" : "REPS").frame(maxWidth: .infinity)
            Image(systemName: "checkmark").frame(width: 44)
        }
        .font(Font.fs(.caption2, .semibold))
        .foregroundStyle(Theme.tertiary)
    }
}

private struct SetRow: View {
    let number: Int
    @Binding var set: LoggedSet
    let timed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(Font.fs(.subheadline, .semibold).monospacedDigit())
                .foregroundStyle(Theme.secondary)
                .frame(width: 34, alignment: .leading)
            if timed {
                field(NumberField(placeholder: "–", value: $set.durationMin))
                field(NumberField(placeholder: "–", value: $set.distanceKm))
            } else {
                field(NumberField(placeholder: "–", value: $set.weightKg))
                    .accessibilityIdentifier("set-\(number)-kg")
                field(NumberField(placeholder: "–", value: $set.reps.asDouble, decimals: false))
                    .accessibilityIdentifier("set-\(number)-reps")
            }
            Button {
                set.done.toggle()
                if set.done { Haptics.tap() }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(Font.fs(.title2))
                    .foregroundStyle(set.done ? Theme.recoveryGreen : Theme.tertiary)
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.done ? "Set \(number) done" : "Mark set \(number) done")
            .accessibilityIdentifier("set-\(number)-done")
        }
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(set.done ? Theme.recoveryGreen.opacity(0.08) : .clear))
    }

    private func field(_ f: NumberField) -> some View {
        f.multilineTextAlignment(.center)
            .font(Font.fs(.body, .semibold))
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// The end of a workout: how hard it felt, notes, the day, then saved to the Training history.
private struct FinishWorkoutSheet: View {
    @Binding var log: WorkoutLog
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        summary("Time", log.minutes.map { Format.duration($0) } ?? (workout.editing ? "–" : elapsedNow))
                        summary("Sets", "\(log.doneSetCount)")
                        summary("Volume", log.volumeKg.map { "\(Format.number($0)) kg" } ?? "–")
                    }
                    if log.doneSetCount == 0 {
                        Text("No set is ticked yet. Only ticked sets count as done.")
                            .font(Font.fs(.footnote))
                            .foregroundStyle(Theme.recoveryYellow)
                    }
                }
                Section {
                    effortPicker
                } header: {
                    Text("How hard was it?")
                } footer: {
                    Text(log.effort.map { "\($0) of 10: \(Effort.word($0))" } ?? "1 is very easy, 10 is all out. The coach reads it with your heart rate and recovery.")
                }
                Section("Notes") {
                    TextField("How it went, what to change next time…", text: Binding(get: { log.notes ?? "" }, set: { log.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("finish-notes")
                    DatePicker("Day", selection: dayBinding, in: ...(Format.date(model.today) ?? Date()), displayedComponents: .date)
                        .environment(\.timeZone, Format.utc)
                }
                if let error {
                    Section { Text(error).font(Font.fs(.footnote)).foregroundStyle(Theme.recoveryRed) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(workout.editing ? "Save changes" : "Finish workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(workout.editing ? "Back" : "Keep going") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("finish-save")
                    }
                }
            }
            .interactiveDismissDisabled(saving)
        }
        .presentationDetents([.large])
    }

    private var elapsedNow: String {
        guard let start = Format.timestamp(log.startedAt) else { return "–" }
        return Format.duration(Date().timeIntervalSince(start) / 60)
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { Format.date(log.date) ?? Date() }, set: { log.date = Format.ymd($0) })
    }

    private func summary(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Font.fredoka(20))
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var effortPicker: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { n in
                Button {
                    log.effort = log.effort == n ? nil : n
                } label: {
                    Text("\(n)")
                        .font(Font.fs(.subheadline, .semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(log.effort == n ? Effort.color(n) : Color.white.opacity(0.07)))
                        .foregroundStyle(log.effort == n ? Color.black : Color.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effort \(n)")
                .accessibilityIdentifier("effort-\(n)")
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var final = log
        if !workout.editing && final.endedAt == nil { final.endedAt = Format.isoNow() }
        final.name = final.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Workout" : final.name.trimmingCharacters(in: .whitespaces)
        if await model.saveLog(final) != nil {
            Haptics.success()
            dismiss()
            workout.discard()
        } else {
            error = model.trainingError ?? "Couldn't save the workout."
            model.trainingError = nil
        }
    }
}
