import SwiftUI
import UIKit

/// A number typed as text, so the value is there with every keystroke (a TextField with a number
/// format only commits on return). Takes "62,5" as well as "62.5"; empty is nil.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var decimals = true
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .monospacedDigit()
            .onAppear { text = Self.text(value) }
            .onChange(of: text) { _, new in
                let parsed = Self.parse(new)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, new in
                if Self.parse(text) != new { text = Self.text(new) }
            }
    }

    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        // Nothing logged here comes near 100 000 (and Int(_:) would trap on a huge number).
        guard let v = Double(t), v.isFinite, v >= 0, v < 100_000 else { return nil }
        return v
    }

    static func text(_ v: Double?) -> String {
        guard let v else { return "" }
        let s = v == v.rounded() && abs(v) < 1e9 ? String(Int(v)) : String(format: "%g", v)
        return s.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}

extension Binding where Value == Int? {
    /// For a NumberField without decimals.
    var asDouble: Binding<Double?> {
        Binding<Double?>(get: { wrappedValue.map(Double.init) }, set: { wrappedValue = $0.map { Int($0.rounded()) } })
    }
}

/// Hides the keyboard, whichever field has it.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Exercise names used before, in routines and logged workouts, so the same exercise keeps the
/// same name and its progress can be followed.
@MainActor
func knownExerciseNames(_ model: AppModel) -> [String] {
    var seen = Set<String>()
    var names: [String] = []
    let all = model.routines.flatMap { $0.exercises.map(\.name) } + model.workoutLogs.flatMap { $0.exercises.map(\.name) }
    for name in all where !name.isEmpty && seen.insert(name.lowercased()).inserted {
        names.append(name)
    }
    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

/// Names from before that start with (or contain) what is typed, for picking instead of retyping.
struct ExerciseNameSuggestions: View {
    let typed: String
    let names: [String]
    let pick: (String) -> Void

    var body: some View {
        let t = typed.trimmingCharacters(in: .whitespaces)
        let matches = names.filter {
            $0.caseInsensitiveCompare(t) != .orderedSame && (t.isEmpty || $0.localizedCaseInsensitiveContains(t))
        }
        .sorted { a, b in
            let pa = a.lowercased().hasPrefix(t.lowercased()), pb = b.lowercased().hasPrefix(t.lowercased())
            return pa != pb ? pa : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(matches.prefix(8), id: \.self) { name in
                        Button(name) { pick(name) }
                            .font(Font.fs(.footnote))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// A small "Ask coach" toolbar button that opens the Coach with `text` in its message field.
struct AskCoachButton: View {
    let text: String
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Named, not just a sparkle: on its own the icon didn't say what it does. An HStack, as a
        // navigation bar shows a Label as its icon only.
        Button { model.askCoach(text) } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("Ask")
            }
            .font(Font.fs(.subheadline, .semibold))
        }
        .tint(Theme.sleep)
        .accessibilityLabel("Ask coach")
        .accessibilityIdentifier("ask-coach")
    }
}

/// How hard a workout felt, 1–10.
enum Effort {
    static func word(_ n: Int) -> String {
        switch n {
        case ...1: return "Very easy"
        case 2...3: return "Easy"
        case 4...5: return "Moderate"
        case 6: return "Somewhat hard"
        case 7: return "Hard"
        case 8...9: return "Very hard"
        default: return "All out"
        }
    }

    static func color(_ n: Int) -> Color {
        n <= 3 ? Theme.recoveryGreen : n <= 6 ? Theme.recoveryYellow : n <= 8 ? Theme.body : Theme.recoveryRed
    }
}
