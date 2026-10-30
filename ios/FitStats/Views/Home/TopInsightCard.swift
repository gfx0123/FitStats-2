import SwiftUI

/// Home: the first two plain-language insights from the stats payload (`model.stats?.insights`,
/// built on the server in lib/stats.ts, in a fixed order with no ranking, so the card never
/// calls them "top" or "strongest"), each with a side bar colored by its tone, like
/// InsightCard on the Insights tab. Insights describe the latest stats (windows ending on
/// `stats.today`), not the day being viewed, so the subtitle says which day they are as of when
/// the two differ. Nothing is computed or filled in here: no stats or no insights shows an empty
/// state. An insight tied to a known metric opens that metric's detail.
struct TopInsightCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    private static let maxShown = 2

    var body: some View {
        let insights = model.stats?.insights ?? []
        let shown = Array(insights.prefix(Self.maxShown))
        let hidden = insights.count - shown.count
        Card {
            SectionHeader(title: "Insights", subtitle: subtitle)
            if shown.isEmpty {
                EmptyStateView(icon: "sparkles", title: "No insights yet", message: emptyMessage)
            } else {
                VStack(spacing: 8) {
                    ForEach(shown) { insight in
                        row(insight)
                    }
                }
                if hidden > 0 {
                    Text(moreText(hidden))
                        .font(Font.fs(.caption2))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("top-insight")
    }

    // MARK: rows

    @ViewBuilder private func row(_ insight: Insight) -> some View {
        if let key = insight.metric, let def = MetricCatalog.def(key) {
            NavigationLink(value: DetailRoute.metric(def.key)) {
                TopInsightRow(insight: insight, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenLabel(insight))
            .accessibilityHint("Opens \(def.label) details")
        } else {
            TopInsightRow(insight: insight, showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel(insight))
        }
    }

    // MARK: text

    private var subtitle: String? {
        guard let stats = model.stats else { return nil }
        if date == stats.today { return "From your latest data" }
        return "From your latest data, as of \(Format.prettyDay(stats.today, today: model.today))"
    }

    private var emptyMessage: String {
        if model.stats == nil { return "Insights appear once a few days have synced." }
        return "Nothing stands out right now. Insights appear when a trend or pattern in your data is clear."
    }

    private func moreText(_ count: Int) -> String {
        count == 1 ? "1 more insight on the Insights tab" : "\(count) more insights on the Insights tab"
    }

    private func spokenLabel(_ insight: Insight) -> String {
        let text = "\(insight.title). \(insight.body)"
        switch insight.tone {
        case "positive": return "Positive. \(text)"
        case "negative": return "Negative. \(text)"
        default: return text
        }
    }
}

/// One insight: tone bar, title and body. The bar is an overlay so it always spans the row's
/// full height, whatever the text wraps to.
private struct TopInsightRow: View {
    let insight: Insight
    let showsChevron: Bool

    private var toneColor: Color {
        switch insight.tone {
        case "positive": return Theme.recoveryGreen
        case "negative": return Theme.recoveryRed
        default: return Theme.stress
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(insight.title)
                    .font(Font.fs(.subheadline, .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.body)
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(Font.fs(.caption2, .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 24)
        .padding(.trailing, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(toneColor)
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 10)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
