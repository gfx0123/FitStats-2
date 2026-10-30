import SwiftUI

/// Settings → Coach: choose who coaches you, the three characters with how each one talks. The
/// choice applies to the next message (also in an open conversation) and stays on the phone.
struct CoachPickerView: View {
    @EnvironmentObject private var coach: CoachStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Every coach reads the same data and follows the same rules. Only how they talk to you differs.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                ForEach(CoachPersona.allCases) { persona in
                    Button {
                        coach.persona = persona
                        dismiss()
                    } label: {
                        card(persona)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-pick-\(persona.rawValue)")
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Choose your coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(_ persona: CoachPersona) -> some View {
        let selected = coach.persona == persona
        return HStack(alignment: .top, spacing: 14) {
            CoachCharacter(persona: persona, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(persona.name).font(Font.fs(.title3, .bold)).foregroundStyle(.white)
                    Text(persona.tagline)
                        .font(Font.fs(.caption, .semibold))
                        .foregroundStyle(persona.color)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(Font.fs(.title3))
                        .foregroundStyle(selected ? persona.color : Theme.tertiary)
                }
                Text(persona.summary)
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("“\(persona.sample)”")
                    .font(Font.fs(.footnote).italic())
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(persona.color.opacity(0.12)))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Glass(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(selected ? persona.color.opacity(0.8) : Theme.cardBorder, lineWidth: selected ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
