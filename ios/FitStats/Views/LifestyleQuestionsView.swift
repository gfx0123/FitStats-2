import SwiftUI

/// The Body age questions: smoking, vaping and alcohol. Shown before the first body age, and
/// later from "Edit answers".
struct LifestyleQuestionsView: View {
    var initial: Lifestyle?
    /// Saves the answers; true when saved.
    let onSave: (Lifestyle) async -> Bool
    @State private var smoking: String?
    @State private var quitAge: String?
    @State private var vaping: String?
    @State private var alcohol: String?
    @State private var saving = false
    @State private var failed = false

    private var answers: Lifestyle? {
        guard let smoking, let vaping, let alcohol else { return nil }
        let l = Lifestyle(smoking: smoking, quitAge: smoking == "former" ? quitAge : nil, vaping: vaping, alcohol: alcohol)
        return l.isComplete ? l : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            question("Do you smoke cigarettes?", key: "smoking", options: [("never", "Never"), ("former", "I used to"), ("current", "Yes")], selection: $smoking)
            if smoking == "former" {
                question("How old were you when you quit?", key: "quit", options: [("under40", "Before 40"), ("40to54", "40–54"), ("55plus", "55 or later")], selection: $quitAge)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            question("Do you vape?", key: "vaping", options: [("never", "No"), ("sometimes", "Sometimes"), ("daily", "Every day")], selection: $vaping)
            VStack(alignment: .leading, spacing: 8) {
                question("How many alcoholic drinks a week?", key: "alcohol",
                         options: [("none", "None"), ("1-10", "1–10"), ("11-20", "11–20"), ("21-35", "21–35"), ("36+", "36+")], selection: $alcohol)
                Text("One drink is a small beer (250 ml), a glass of wine (100 ml) or a shot (30 ml). A half-litre beer counts as 2.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard let answers else { return }
                Task {
                    saving = true
                    failed = !(await onSave(answers))
                    saving = false
                    if !failed { Haptics.success() }
                }
            } label: {
                HStack {
                    Spacer()
                    if saving { ProgressView().tint(.black) } else { Text(initial == nil ? "See my body age" : "Save answers").fontWeight(.semibold) }
                    Spacer()
                }
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14).fill(answers == nil ? Theme.track : Theme.recoveryGreen))
                .foregroundStyle(answers == nil ? Theme.tertiary : .black)
            }
            .buttonStyle(.plain)
            .disabled(answers == nil || saving)
            .accessibilityIdentifier("q-save")
            if failed {
                Text("Couldn't save your answers. Check your connection and try again.").font(.caption).foregroundStyle(Theme.recoveryRed)
            }
            Text("Your answers are kept on your own server and only used for your body age and by your coach. Smoking and alcohol are counted from large studies; vaping is asked but not counted, as there's no long-term figure for it yet.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.snappy, value: smoking)
        .onAppear {
            guard let initial, smoking == nil else { return }
            smoking = initial.smoking
            quitAge = initial.quitAge
            vaping = initial.vaping
            alcohol = initial.alcohol
        }
    }

    private func question(_ title: String, key: String, options: [(String, String)], selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            HStack(spacing: 6) {
                ForEach(options.indices, id: \.self) { i in
                    let option = options[i]
                    let on = selection.wrappedValue == option.0
                    Button {
                        selection.wrappedValue = option.0
                        Haptics.tap()
                    } label: {
                        Text(option.1)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 11).fill(on ? Theme.recoveryGreen : Color.white.opacity(0.08)))
                            .foregroundStyle(on ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("q-\(key)-\(option.0)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}
