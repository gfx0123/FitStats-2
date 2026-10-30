import SwiftUI

/// A small tab hanging under an important Home card, drawn as part of it: the coach's face and
/// "Ask Nova". Tapping it sends the card's question to the coach (a new conversation).
struct CoachCardTab: View {
    let question: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore

    var body: some View {
        Button { model.askCoach(question) } label: {
            HStack(spacing: 6) {
                CoachCharacter(persona: coach.persona, size: 22, animated: false)
                Text("Ask \(coach.persona.name)")
                    .font(Font.fs(.caption, .semibold))
                    .foregroundStyle(coach.persona.color)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(Font.fredoka(9, weight: .bold))
                    .foregroundStyle(coach.persona.color.opacity(0.75))
            }
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .padding(.top, 4)
            .padding(.bottom, 5)
            .background(CardTabShape(closed: true).fill(.ultraThinMaterial).overlay(CardTabShape(closed: true).fill(Theme.card)))
            .overlay(CardTabShape(closed: false).stroke(Theme.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Over the card's bottom edge, so the two read as one shape.
        .padding(.top, -1.5)
        .accessibilityLabel("Ask \(coach.persona.name) about this card")
        .accessibilityIdentifier("coach-tab")
    }
}

/// A tab under a card: square at the top where it meets the card, flaring into it with small
/// inward curves, and rounded at the bottom. `closed: false` leaves the top edge open, for the
/// outline.
struct CardTabShape: Shape {
    var closed: Bool
    var flare: CGFloat = 7
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX - flare, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + flare), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + flare))
        p.addQuadCurve(to: CGPoint(x: rect.maxX + flare, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        if closed { p.closeSubpath() }
        return p
    }
}
