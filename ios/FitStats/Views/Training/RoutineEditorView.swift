import SwiftUI

/// Makes or changes a routine: its name, notes, and exercises with their targets.
struct RoutineEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var routine: Routine
    @State private var path: [UUID] = []
    @State private var editMode: EditMode = .inactive
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var choosingExercise = false

    init(draft: Routine) {
        _routine = State(initialValue: draft)
    }

    private var isNew: Bool { routine.id.isEmpty }
    private var canSave: Bool { !routine.name.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    TextField("Name, like Upper body A", text: $routine.name)
                        .font(Font.fs(.headline))
                        .accessibilityIdentifier("routine-name")
                    TextField("Notes (optional)", text: Binding(get: { routine.notes ?? "" }, set: { routine.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    ForEach(routine.exercises) { e in
                        NavigationLink(value: e.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(e.name.isEmpty ? "New exercise" : e.name, systemImage: e.kind.icon)
                                    .font(Font.fs(.subheadline, .semibold))
                                    .foregroundStyle(e.name.isEmpty ? Theme.tertiary : .white)
                                if !e.plan.isEmpty {
                                    Text(e.plan).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("routine-exercise-\(e.name)")
                    }
                    .onDelete { routine.exercises.remove(atOffsets: $0) }
                    .onMove { routine.exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        choosingExercise = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                    }
                    .disabled(routine.exercises.count >= 40)
                    .accessibilityIdentifier("routine-add-exercise")
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if routine.exercises.count > 1 {
                            Button(editMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                            }
                            .font(Font.fs(.caption, .semibold))
                            .textCase(nil)
                        }
                    }
                } footer: {
                    Text("Swipe an exercise left to remove it. Logging this routine fills in these targets, or the weights you lifted last time when there is no target.")
                }
                if let error {
                    Section { Text(error).font(Font.fs(.footnote)).foregroundStyle(Theme.recoveryRed) }
                }
                if !isNew {
                    Section {
                        Button("Delete routine", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("routine-delete")
                    } footer: {
                        Text("Workouts you logged with it stay in your history.")
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                            .accessibilityIdentifier("routine-save")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ExerciseEditorView(exercise: exerciseBinding(id), knownNames: knownExerciseNames(model))
            }
            .sheet(isPresented: $choosingExercise) {
                NavigationStack {
                    ExerciseLibraryView { name, kind in
                        let e = RoutineExercise(name: name, kind: kind, sets: kind.timed ? 1 : 3, reps: kind.timed ? nil : "8-10")
                        routine.exercises.append(e)
                        // Its targets next, once the library has closed.
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            path.append(e.id)
                        }
                    }
                }
                .environmentObject(model)
            }
            .confirmationDialog("Delete \(routine.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete routine", role: .destructive) {
                    Task {
                        await model.deleteRoutine(routine.id)
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(saving)
    }

    /// An exercise found by id, so a removed one never leaves its editor pointing past the list.
    private func exerciseBinding(_ id: UUID) -> Binding<RoutineExercise> {
        let routine = $routine
        return Binding(get: { routine.wrappedValue.exercises.first { $0.id == id } ?? RoutineExercise(name: "") },
                       set: { new in
                           if let i = routine.wrappedValue.exercises.firstIndex(where: { $0.id == id }) { routine.wrappedValue.exercises[i] = new }
                       })
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var clean = routine
        clean.name = clean.name.trimmingCharacters(in: .whitespaces)
        clean.exercises = clean.exercises
            .map { var e = $0; e.name = e.name.trimmingCharacters(in: .whitespaces); return e }
            .filter { !$0.name.isEmpty }
        if await model.saveRoutine(clean) != nil {
            Haptics.success()
            dismiss()
        } else {
            error = model.trainingError ?? "Couldn't save the routine."
            model.trainingError = nil
        }
    }
}

/// One exercise of a routine: what it is and its targets.
struct ExerciseEditorView: View {
    @Binding var exercise: RoutineExercise
    let knownNames: [String]
    @FocusState private var nameFocused: Bool
    @EnvironmentObject private var model: AppModel

    private static let rests: [Int?] = [nil, 30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        Form {
            Section {
                TextField("Exercise, like Bench press", text: $exercise.name)
                    .focused($nameFocused)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("exercise-name")
                ExerciseNameSuggestions(typed: exercise.name, names: knownNames) { exercise.name = $0 }
                Picker("Type", selection: $exercise.kind) {
                    ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Target") {
                Stepper(value: Binding(get: { exercise.sets ?? (exercise.kind.timed ? 1 : 3) }, set: { exercise.sets = $0 }), in: 1...30) {
                    HStack {
                        Text("Sets")
                        Spacer()
                        Text("\(exercise.sets ?? (exercise.kind.timed ? 1 : 3))").monospacedDigit().foregroundStyle(Theme.secondary)
                    }
                }
                if exercise.kind.timed {
                    row("Minutes") { NumberField(placeholder: "–", value: $exercise.durationMin) }
                    row("Kilometres") { NumberField(placeholder: "–", value: $exercise.distanceKm) }
                } else {
                    row("Reps") {
                        TextField("8 or 8-12", text: Binding(get: { exercise.reps ?? "" }, set: { exercise.reps = $0.isEmpty ? nil : $0 }))
                            .accessibilityIdentifier("exercise-reps")
                    }
                    row("Weight (kg)") {
                        NumberField(placeholder: "last time's", value: $exercise.weightKg)
                            .accessibilityIdentifier("exercise-weight")
                    }
                    if exercise.kind == .mobility {
                        row("Minutes") { NumberField(placeholder: "–", value: $exercise.durationMin) }
                    }
                }
                Picker("Rest between sets", selection: $exercise.restS) {
                    ForEach(Self.rests, id: \.self) { s in
                        Text(Self.restLabel(s)).tag(s)
                    }
                }
            }
            Section("Notes") {
                TextField("Form cues, tempo, machine settings…", text: Binding(get: { exercise.notes ?? "" }, set: { exercise.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .lineLimit(1...4)
            }
            musclesSection
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(exercise.name.isEmpty ? "Exercise" : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        .onAppear { if exercise.name.isEmpty { nameFocused = true } }
    }

    /// The library's muscles for a known exercise; for your own, the muscles you choose.
    @ViewBuilder private var musclesSection: some View {
        let library = model.library
        if !library.muscles.isEmpty {
            if let known = library.find(exercise.name) {
                Section {
                    MuscleChips(primary: known.primary, secondary: known.secondary, library: library)
                        .padding(.vertical, 4)
                } header: {
                    Text("Muscles")
                } footer: {
                    Text("From the exercise library: filled are the main muscles, outlined the ones that help.")
                }
            } else if !exercise.name.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    FlowLayout(spacing: 6) {
                        ForEach(library.muscles) { m in
                            let on = exercise.muscles?.contains(m.id) ?? false
                            Button {
                                var chosen = exercise.muscles ?? []
                                if on { chosen.removeAll { $0 == m.id } } else if chosen.count < 6 { chosen.append(m.id) }
                                exercise.muscles = chosen.isEmpty ? nil : chosen
                            } label: {
                                Text(m.label)
                                    .font(Font.fs(.caption, .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(on ? Theme.muscle.opacity(0.25) : Color.white.opacity(0.07)))
                                    .foregroundStyle(on ? Theme.muscle : Theme.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Muscles it works")
                } footer: {
                    Text("Not in the exercise library: choose up to six, so it counts on the body map.")
                }
            }
        }
    }

    static func restLabel(_ s: Int?) -> String {
        guard let s else { return "Not set" }
        if s < 60 { return "\(s) s" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s"
    }

    private func row<Field: View>(_ title: String, @ViewBuilder field: () -> Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            field().multilineTextAlignment(.trailing).frame(maxWidth: 140)
        }
    }
}
