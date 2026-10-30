import SwiftUI

/// A workout logged in the app: every set, the totals, how hard it felt, and the band's
/// recording of the same session when there is one.
struct WorkoutLogDetailView: View {
    let logID: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var workout: ActiveWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let log = model.workoutLogs.first { $0.id == logID }
        ScrollView {
            VStack(spacing: 14) {
                if let log {
                    header(log)
                    totals(log)
                    if let band = model.workoutPairs[log.id] { bandCard(band) }
                    WorkoutMusclesCard(title: "Muscles worked", sets: model.library.sets(in: [log]), library: model.library)
                    ForEach(log.exercises) { exerciseCard($0) }
                    if let notes = log.notes, !notes.isEmpty {
                        Card {
                            SectionHeader(title: "Notes")
                            Text(notes).font(Font.fs(.subheadline)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    AskCoachRow(prompts: [
                        ("checklist", "Review this workout", "About my workout “\(log.name)” on \(Format.longDay(log.date)): how did it go, and what should I change next time?"),
                        ("arrow.up.right", "What next time?", "About my workout “\(log.name)” on \(Format.longDay(log.date)): what weights and reps should I aim for next time?"),
                    ])
                } else {
                    Card { EmptyStateView(icon: "questionmark", title: "Workout not found", message: "It may have been deleted.") }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(log.map { Format.shortDay($0.date) } ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let log {
                    Menu {
                        Button("Edit", systemImage: "pencil") { workout.start(log, editing: true) }
                            .disabled(workout.log != nil)
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Workout options")
                    .accessibilityIdentifier("log-options")
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                Task {
                    await model.deleteLog(logID)
                    dismiss()
                }
            }
        }
    }

    private func header(_ log: WorkoutLog) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(log.name).font(Font.fs(.title3, .semibold))
                Spacer()
                if let effort = log.effort {
                    Text("Effort \(effort)/10")
                        .font(Font.fs(.caption, .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Effort.color(effort).opacity(0.18)))
                        .foregroundStyle(Effort.color(effort))
                }
            }
            Text([Format.longDay(log.date), timeRange(log)].compactMap { $0 }.joined(separator: " · "))
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
            if let id = log.routineId, let routine = model.routines.first(where: { $0.id == id }) {
                NavigationLink(value: TrainingRoute.routine(id)) {
                    Label("From \(routine.name)", systemImage: "list.bullet.clipboard")
                        .font(Font.fs(.footnote, .semibold))
                }
            }
        }
    }

    private func totals(_ log: WorkoutLog) -> some View {
        HStack(spacing: 10) {
            tile("Duration", log.minutes.map { Format.duration($0) } ?? "–")
            tile("Sets done", "\(log.doneSetCount)")
            tile("Volume", log.volumeKg.map { "\(Format.number($0)) kg" } ?? "–")
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            Text(value).font(Font.fredoka(20)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Glass(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    private func exerciseCard(_ e: LoggedExercise) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(e.name, systemImage: e.kind.icon).font(Font.fs(.headline))
                Spacer()
                if let v = e.volumeKg {
                    Text("\(Format.number(v)) kg").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                }
            }
            ForEach(Array(e.sets.enumerated()), id: \.element.id) { item in
                HStack {
                    Text("Set \(item.offset + 1)").foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(item.element.summary).monospacedDigit()
                    Image(systemName: item.element.done ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(item.element.done ? Theme.recoveryGreen : Theme.tertiary)
                }
                .font(Font.fs(.subheadline))
                .opacity(item.element.done ? 1 : 0.55)
                .accessibilityElement(children: .combine)
            }
            if let notes = e.notes, !notes.isEmpty {
                Text(notes).font(Font.fs(.caption)).foregroundStyle(Theme.secondary).italic()
            }
        }
    }

    /// The band's recording of this session: heart rate, strain, calories, heart-rate recovery
    /// and time in each zone, with its own screen a tap away.
    private func bandCard(_ x: Exercise) -> some View {
        NavigationLink(value: DetailRoute.workout(x.date, x.id)) {
            Card {
                HStack {
                    SectionHeader(title: "Recorded by your band", subtitle: x.displayName)
                    Spacer()
                    Image(systemName: "chevron.right").font(Font.fs(.caption2, .semibold)).foregroundStyle(Theme.tertiary)
                }
                let raw: [(String, String?)] = [
                    ("Avg heart rate", x.avgHr.map { "\(Int($0.rounded())) bpm" }),
                    ("Max heart rate", x.hrMax.map { "\(Int($0.rounded())) bpm" }),
                    ("Strain", x.strain.map { Format.number($0, decimals: 1) }),
                    ("Calories", x.calories.map { "\(Int($0.rounded())) kcal" }),
                    ("Duration", x.durationS.map { Format.duration($0 / 60) }),
                    ("HR drop, 1 min", x.hrr1min.map { "\(Int($0.rounded())) bpm" }),
                ]
                let stats = raw.compactMap { item in item.1.map { (item.0, $0) } }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 10) {
                    ForEach(stats, id: \.0) { stat in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.1).font(Font.fs(.subheadline, .semibold)).monospacedDigit()
                            Text(stat.0).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                        }
                    }
                }
                zoneBar(x)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log-band-workout")
    }

    /// Time in the light, moderate, vigorous and peak heart-rate zones, as one bar.
    @ViewBuilder private func zoneBar(_ x: Exercise) -> some View {
        let zones: [(String, Double, Color)] = [
            ("Light", x.zoneLightS ?? 0, Theme.recoveryGreen), ("Moderate", x.zoneModerateS ?? 0, Theme.recoveryYellow),
            ("Vigorous", x.zoneVigorousS ?? 0, Theme.strain), ("Peak", x.zonePeakS ?? 0, Theme.heart),
        ]
        let total = zones.reduce(0) { $0 + $1.1 }
        if total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(zones.filter { $0.1 > 0 }, id: \.0) { z in
                            RoundedRectangle(cornerRadius: 3).fill(z.2).frame(width: max(4, (geo.size.width - 6) * z.1 / total))
                        }
                    }
                }
                .frame(height: 8)
                HStack(spacing: 10) {
                    ForEach(zones.filter { $0.1 > 0 }, id: \.0) { z in
                        HStack(spacing: 4) {
                            Circle().fill(z.2).frame(width: 6, height: 6)
                            Text("\(z.0) \(Format.duration(z.1 / 60))").font(Font.fs(.caption2)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func timeRange(_ log: WorkoutLog) -> String? {
        guard let start = Format.timestamp(log.startedAt) else { return nil }
        guard let end = Format.timestamp(log.endedAt), end.timeIntervalSince(start) >= 60 else { return Format.time(start, zone: model.zone) }
        return "\(Format.time(start, zone: model.zone))–\(Format.time(end, zone: model.zone))"
    }
}
