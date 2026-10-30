import SwiftUI
import UIKit

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    /// Drawn inside a Home card's resize frame, which has the background already.
    @Environment(\.homeCardBare) private var bare

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { if !bare { Glass(cornerRadius: 22) } }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(bare ? Color.clear : Theme.cardBorder, lineWidth: 1)
        )
    }
}

/// The line under a score saying what moved it most (ScoreBreakdown.recoveryWhy, .sleepWhy).
struct ScoreWhyLine: View {
    let why: ScoreWhy

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: why.lifted ? "arrow.up.right" : "arrow.down.right")
                .font(Font.fs(.caption, .bold))
                .foregroundStyle(why.lifted ? Theme.recoveryGreen : Theme.recoveryYellow)
            Text(why.text)
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("score-why")
    }
}

/// One line of text that switches to a shorter wording when the full one doesn't fit, instead of
/// cutting it off ("Resting heart rate" → "Resting HR").
struct FittingText: View {
    let full: String
    let short: String

    init(_ full: String, short: String) {
        self.full = full
        self.short = short
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(full).lineLimit(1)
            Text(short).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(Font.fs(.caption, .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondary)
            if let subtitle {
                Text(subtitle).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// Circular progress ring with a gradient and an optional target band.
struct RingGauge<Center: View>: View {
    let progress: Double
    let color: Color
    var endColor: Color? = nil
    var lineWidth: CGFloat = 12
    var target: ClosedRange<Double>? = nil
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            // The target band is drawn on the track itself, so it stays inside the ring.
            if let target {
                Circle()
                    .trim(from: max(0, min(1, target.lowerBound)), to: max(0, min(1, target.upperBound)))
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            // A zero score draws no arc (a round cap would otherwise leave a dot at 12 o'clock).
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: min(1, progress))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [color.opacity(0.85), endColor ?? color]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * max(0.05, min(1, progress)))
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.35), radius: 6)
            }
            center()
        }
    }
}

struct ScoreRing: View {
    let title: String
    let value: Double?
    let maxValue: Double
    let color: Color
    var endColor: Color? = nil
    var caption: String? = nil
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10
    var decimals: Int = 0
    var suffix: String = ""
    var target: ClosedRange<Double>? = nil

    var body: some View {
        VStack(spacing: 8) {
            RingGauge(
                progress: (value ?? 0) / maxValue,
                color: color,
                endColor: endColor,
                lineWidth: lineWidth,
                target: target.map { ($0.lowerBound / maxValue)...($0.upperBound / maxValue) }
            ) {
                VStack(spacing: 0) {
                    Text(value.map { Format.number($0, decimals: decimals) + suffix } ?? "–")
                        .font(Font.fredoka(size * 0.27))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let caption {
                        Text(caption)
                            .font(Font.fredoka(max(9, size * 0.1), weight: .medium))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(lineWidth)
            }
            .frame(width: size, height: size)
            Text(title)
                .font(Font.fs(.footnote, .semibold))
                .foregroundStyle(Theme.secondary)
        }
    }
}

struct DeltaBadge: View {
    let change: Double?
    let better: Better?
    var suffix: String = "%"
    var decimals: Int = 0

    var body: some View {
        if let change, change.isFinite, abs(change) >= 0.5 {
            let up = change > 0
            let good: Bool? = better.map { $0 == .higher ? up : !up }
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text("\(Format.number(abs(change), decimals: decimals))\(suffix)")
            }
            .font(Font.fs(.caption2, .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(color(good).opacity(0.16)))
            .foregroundStyle(color(good))
        }
    }

    private func color(_ good: Bool?) -> Color {
        guard let good else { return Theme.secondary }
        return good ? Theme.recoveryGreen : Theme.recoveryRed
    }
}

struct MetricTile: View {
    let title: String
    /// Used when the title doesn't fit.
    var shortTitle: String? = nil
    let value: String
    var sub: String? = nil
    var icon: String
    var color: Color
    var change: Double? = nil
    var better: Better? = nil

    /// DeltaBadge shows nothing for changes under 0.5.
    private var showsBadge: Bool {
        guard let change else { return false }
        return change.isFinite && abs(change) >= 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(Font.fs(.caption)).foregroundStyle(color)
                FittingText(title, short: shortTitle ?? title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            // A fixed line height, so a value shrunk to fit is as tall as its neighbours.
            Text(value)
                .font(Font.fredoka(22))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 28, alignment: .leading)
            if sub != nil || showsBadge {
                HStack(spacing: 6) {
                    if let sub {
                        Text(sub).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    DeltaBadge(change: change, better: better)
                }
            }
        }
        .padding(12)
        // Fills its grid row (TwoColumnTiles), so tiles side by side are the same height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

/// Tiles in two equal columns. Tiles in a row share its height, and an odd last tile
/// spans both columns, so no half row is left empty.
struct TwoColumnTiles<Item: Hashable, Tile: View>: View {
    let items: [Item]
    @ViewBuilder var tile: (Item) -> Tile

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<Swift.min($0 + 2, items.count)]) }
    }

    var body: some View {
        let rows = self.rows
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows.indices, id: \.self) { i in
                GridRow {
                    ForEach(rows[i], id: \.self) { item in
                        tile(item).gridCellColumns(rows[i].count == 1 ? 2 : 1)
                    }
                }
            }
        }
    }
}

struct ComponentBar: View {
    let component: ScoreComponentInfo
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(component.label).font(Font.fs(.subheadline, .medium))
                Text("\(Int((component.weight * 100).rounded()))%")
                    .font(Font.fs(.caption2))
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                Text(Format.number(component.value)).font(Font.fredoka(16, weight: .semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    let fraction = CGFloat(min(100, max(0, component.value)) / 100)
                    Capsule()
                        .fill(color)
                        .frame(width: fraction > 0 ? max(6, geo.size.width * fraction) : 0)
                }
            }
            .frame(height: 6)
            if !component.detail.isEmpty {
                Text(component.detail).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var color: Color = .white

    var body: some View {
        HStack {
            Text(key).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).foregroundStyle(color).font(Font.fs(.body).monospacedDigit())
        }
        .font(Font.fs(.subheadline))
    }
}

struct Banner: View {
    let icon: String
    let text: String
    var color: Color = Theme.recoveryYellow
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(Font.fs(.footnote)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Font.fs(.footnote, .semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.12)))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(Font.fredoka(34, weight: .regular)).foregroundStyle(Theme.tertiary)
            Text(title).font(Font.fs(.headline))
            Text(message)
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// A card's frosted glass: the background scene shows through, blurred and tinted.
struct Glass: View {
    var cornerRadius: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(.ultraThinMaterial).overlay(shape.fill(Theme.card))
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppBackground())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

/// Short haptic taps for things that just happened (silent where the iPhone has haptics off).
@MainActor
enum Haptics {
    /// Something was saved or finished: a workout, a routine, the journal.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// A small step: a set ticked off, an answer arrived.
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}
