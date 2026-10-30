import SwiftUI

/// The bottom of Home while editing: every card that isn't on Home yet (and a Metric card and a
/// Smart Stack, which can be added any number of times), each as a live preview of your own
/// data at the size you pick, with an Add button, and a reset to the default layout.
struct HomeAddSection: View {
    let date: String
    let shown: [HomeItem]
    let isDefault: Bool
    /// Whether a card can draw on `date` (see TodayView.isVisible); the others preview as placeholders.
    var canShow: (HomeCard) -> Bool
    var onAdd: (HomeItem) -> Void
    var onReset: () -> Void

    /// The size picked for each card's preview; a card's default until changed.
    @State private var sizes: [HomeCard: CardSize] = [:]
    /// The Metric card preview's metric.
    @State private var metricKey = "steps"
    /// The Smart Stack preview, added as it is (its cards are changed in its settings).
    @State private var stackOptions = HomeLayout.defaultOptions(.stack)

    private var more: [HomeCard] {
        HomeCard.allCases.filter { card in !card.isUnique || !shown.contains { $0.card == card } }
    }

    private func options(for card: HomeCard) -> CardOptions {
        switch card {
        case .metric: return CardOptions(metric: metricKey, days: 30)
        case .stack: return stackOptions
        default: return CardOptions()
        }
    }

    private func add(_ card: HomeCard, size: CardSize) {
        onAdd(HomeLayout.newItem(card, size: size, options: options(for: card)))
        if card == .stack { stackOptions = HomeLayout.defaultOptions(.stack) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Add cards", subtitle: "Previews use your own data. Pick a size, then tap Add.")
                .padding(.top, 16)
            LazyVStack(alignment: .leading, spacing: 26) {
                ForEach(more) { card in
                    previewRow(card)
                }
            }
            Button {
                onReset()
            } label: {
                Label("Reset Home to default", systemImage: "arrow.counterclockwise")
                    .font(Font.fs(.subheadline, .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Glass(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDefault ? Theme.tertiary : .white)
            .disabled(isDefault)
            .padding(.top, 8)
            .accessibilityIdentifier("home-reset")
        }
    }

    private func size(for card: HomeCard) -> CardSize {
        let size = sizes[card] ?? card.defaultSize
        return card.sizes.contains(size) ? size : card.defaultSize
    }

    private func previewRow(_ card: HomeCard) -> some View {
        let chosen = size(for: card)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: card.icon)
                    .font(Font.fs(.subheadline, .semibold))
                    .foregroundStyle(Theme.recoveryGreen)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.recoveryGreen.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.title)
                            .font(Font.fs(.subheadline, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if card.todayOnly {
                            Text("Today only")
                                .font(Font.fs(.caption2, .semibold))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                    Text(card.subtitle)
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button {
                    add(card, size: chosen)
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(Font.fs(.subheadline, .semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.recoveryGreen)
                .accessibilityLabel(Text("Add \(card.title), \(chosen.label.lowercased())"))
                .accessibilityIdentifier("home-add-\(card.rawValue)")
            }
            Picker("Size", selection: Binding(get: { size(for: card) }, set: { sizes[card] = $0 })) {
                ForEach(card.sizes) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("home-size-\(card.rawValue)")
            if card == .metric {
                Picker("Metric", selection: $metricKey) {
                    ForEach(metricChoices) { def in
                        Text(def.label).tag(def.key)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.recoveryGreen)
                .accessibilityIdentifier("home-metric-picker")
            }
            HomeGridLayout(columnSpacing: 12, rowSpacing: 14) {
                preview(card, size: chosen)
                    .layoutValue(key: HomeCardSizeKey.self, value: chosen)
            }
            .allowsHitTesting(false)
            .environment(\.homeCardPreview, true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Preview of \(card.title), \(chosen.label.lowercased())"))
        }
    }

    @EnvironmentObject private var model: AppModel

    /// The metrics a Metric card can show: the recorded ones (all before anything has synced).
    private var metricChoices: [MetricDef] {
        MetricCatalog.all.filter { model.recorded.isEmpty || model.recorded.contains($0.key) }
    }

    @ViewBuilder private func preview(_ card: HomeCard, size: CardSize) -> some View {
        let spec = HomeCardSpec(card, options(for: card))
        if !canShow(card) {
            // Editing always shows today, so only a day that hasn't synced yet hides a card here.
            HomeCardPlaceholder(card: card, title: card.title, size: size, reason: "Shows once today's data has synced.")
        } else if size == .large {
            HomeLargeCard(spec: spec, date: date)
        } else {
            HomeGlance(spec: spec, size: size, date: date)
        }
    }
}
