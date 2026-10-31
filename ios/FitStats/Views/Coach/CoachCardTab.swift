import SwiftUI

/// A small tab hanging under an important Home card, drawn as part of it: the coach's face and
/// "Ask Nova". Tapping it sends the card's question to the coach (a new conversation).
struct CoachCardTab: View {
    let question: String
    /// Drawn with its card as one shape (CardWithTabBackground), so it has no background of its own.
    var joined = false
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
            .background {
                if !joined {
                    CardTabShape(closed: true).fill(.ultraThinMaterial).overlay(CardTabShape(closed: true).fill(Theme.card))
                }
            }
            .overlay { if !joined { CardTabShape(closed: false).stroke(Theme.cardBorder, lineWidth: 1) } }
            .anchorPreference(key: CoachTabBoundsKey.self, value: .bounds) { $0 }
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

/// Where a card's coach tab is, for drawing the card and its tab as one shape.
struct CoachTabBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

/// A card and the coach tab under it as one frosted shape with one outline, so the tab reads as
/// part of the card even though the glass is see-through (two layers would show the card's
/// bottom edge across the tab).
struct CardWithTabBackground: View {
    let tab: CGRect?

    var body: some View {
        GeometryReader { geo in
            let shape = CardWithTabShape(tab: tab)
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.card))
                .overlay(shape.stroke(Theme.cardBorder, lineWidth: 1))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct CardWithTabShape: Shape {
    let tab: CGRect?
    var radius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        guard let tab, tab.minY > rect.minY else {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        // The tab overlaps the card's bottom edge by 1.5 points (CoachCardTab).
        let card = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: tab.minY + 1.5 - rect.minY)
        return Path(roundedRect: card, cornerRadius: radius, style: .continuous)
            .union(CardTabShape(closed: true).path(in: tab))
    }
}

/// The coach button inside the Recovery area at the top of Today, which isn't a card.
struct CoachAskPill: View {
    let question: String
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var coach: CoachStore

    var body: some View {
        Button { model.askCoach(question) } label: {
            HStack(spacing: 6) {
                CoachCharacter(persona: coach.persona, size: 22, animated: false)
                Text("Ask \(coach.persona.name)")
                    .font(Font.fs(.subheadline, .semibold))
                    .foregroundStyle(coach.persona.color)
                Image(systemName: "arrow.up.right")
                    .font(Font.fredoka(10, weight: .bold))
                    .foregroundStyle(coach.persona.color.opacity(0.75))
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Theme.card)))
            .overlay(Capsule().stroke(coach.persona.color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask \(coach.persona.name) about this card")
        .accessibilityIdentifier("coach-tab")
    }
}
