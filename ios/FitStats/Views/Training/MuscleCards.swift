import SwiftUI

/// Training tab: done sets per muscle over the last 7 days on the body map, the most worked
/// muscles, and the big ones not trained at all, with the exercise library a tap away.
struct MusclesWeekCard: View {
    @EnvironmentObject private var model: AppModel

    /// The muscles worth calling out when they got no sets.
    private static let major = ["chest", "upper_back", "lats", "shoulders", "quads", "hamstrings", "glutes", "abs"]

    var body: some View {
        let library = model.library
        let since = Format.addDays(model.today, -6)
        let sets = library.sets(in: model.workoutLogs.filter { $0.date >= since })
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Muscles · last 7 days", subtitle: "Done sets in the workouts you logged")
                Spacer()
                NavigationLink(value: TrainingRoute.library) {
                    Label("Library", systemImage: "books.vertical").font(Font.fs(.caption, .semibold))
                }
                .accessibilityIdentifier("training-library")
            }
            BodyMapView(levels: sets.mapValues(Self.level))
            if sets.isEmpty {
                Text("Log a workout and the muscles it works light up here.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(MuscleCount.sorted(sets).prefix(5)) { item in
                        Text("\(library.label(item.id)) \(Self.setsText(item.sets))")
                            .font(Font.fs(.caption, .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.muscle.opacity(0.18)))
                            .foregroundStyle(Theme.muscle)
                    }
                }
                let missing = Self.major.filter { (sets[$0] ?? 0) == 0 }
                if !missing.isEmpty {
                    Text("No sets yet: \(missing.map(library.label).joined(separator: ", ")).")
                        .font(Font.fs(.footnote))
                        .foregroundStyle(Theme.secondary)
                }
            }
            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("muscles-week")
    }

    /// 1–3 sets light, 4–9 medium, 10 or more full.
    static func level(_ sets: Double) -> Double {
        sets <= 0 ? 0 : sets < 4 ? 0.2 : sets < 10 ? 0.55 : 1
    }

    static func setsText(_ v: Double) -> String {
        let n = v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
        return "\(n) \(v == 1 ? "set" : "sets")"
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(MuscleCount.legend) { step in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.muscle.opacity(0.25 + 0.75 * step.sets)).frame(width: 12, height: 12)
                    Text(step.id).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) {
            Text("helpers count ½").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
    }
}

/// The muscles a routine or a logged workout works, on the body map with the sets per muscle.
struct WorkoutMusclesCard: View {
    let title: String
    let sets: [String: Double]
    let library: ExerciseLibrary

    var body: some View {
        if !sets.isEmpty {
            let most = sets.values.max() ?? 1
            Card {
                SectionHeader(title: title)
                BodyMapView(levels: sets.mapValues { $0 / most }, height: 190)
                FlowLayout(spacing: 6) {
                    ForEach(MuscleCount.sorted(sets)) { item in
                        Text("\(library.label(item.id)) \(MusclesWeekCard.setsText(item.sets))")
                            .font(Font.fs(.caption))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout-muscles")
        }
    }
}

/// A muscle and its sets, for lists (also the legend's steps: label and level).
private struct MuscleCount: Identifiable {
    let id: String
    let sets: Double

    static func sorted(_ sets: [String: Double]) -> [MuscleCount] {
        sets.map { MuscleCount(id: $0.key, sets: $0.value) }.sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.id < $1.id }
    }

    static let legend = [MuscleCount(id: "1–3", sets: 0.2), MuscleCount(id: "4–9", sets: 0.55), MuscleCount(id: "10+ sets", sets: 1)]
}
