import SwiftUI

/// Insights, streaks, correlations and the training load, opened from the top of Trends.
struct InsightsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let stats = model.stats {
                    insightsSection(stats.insights)
                    TrainingLoadCard(load: stats.load, today: stats.today)
                    BedtimeCard(bedtime: stats.bedtime)
                    JournalImpactsCard(impacts: stats.journal ?? [])
                        .accessibilityIdentifier("journal-impacts")
                    streaksSection(stats.streaks)
                    correlationsSection(stats.correlations)
                } else {
                    Card {
                        EmptyStateView(icon: "sparkles", title: "No insights yet",
                                       message: "Insights appear once a few days have synced.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .refreshable { await model.pullToRefresh() }
        .screenBackground()
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func insightsSection(_ insights: [Insight]) -> some View {
        if !insights.isEmpty {
            VStack(spacing: 10) {
                ForEach(insights) { InsightCard(insight: $0) }
            }
        }
    }

    private func streaksSection(_ streaks: [Streak]) -> some View {
        Card {
            SectionHeader(title: "Streaks")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(streaks) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.label).font(Font.fs(.caption)).foregroundStyle(Theme.secondary).lineLimit(2)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(s.current)").font(Font.fredoka(26))
                            Text(s.current == 1 ? "day" : "days").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                        }
                        Text("Best \(s.longest)").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                }
            }
        }
    }

    private func correlationsSection(_ correlations: [Correlation]) -> some View {
        let sorted = correlations.sorted { abs($0.r ?? 0) > abs($1.r ?? 0) }
        return Card {
            SectionHeader(title: "What affects what", subtitle: "Pearson correlation over the last 180 days")
            ForEach(sorted) { c in
                NavigationLink(value: c.id) {
                    CorrelationRow(correlation: c)
                }
                .buttonStyle(.plain)
            }
            Text("Correlation shows that two things move together, not that one causes the other. At least 14 days are needed.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

private struct InsightCard: View {
    let insight: Insight

    private var color: Color {
        switch insight.tone {
        case "positive": return Theme.recoveryGreen
        case "negative": return Theme.recoveryRed
        default: return Theme.stress
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title).font(Font.fs(.subheadline, .semibold))
                Text(insight.body).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Glass(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

private struct CorrelationRow: View {
    let correlation: Correlation

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(correlation.title).font(Font.fs(.subheadline)).lineLimit(2)
                Text(detail).font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Text(correlation.r.map { String(format: "%+.2f", $0) } ?? "–")
                .font(Font.fredoka(16, weight: .semibold))
                .foregroundStyle(color)
            Image(systemName: "chevron.right").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var detail: String {
        let strength = correlation.strength == "insufficient" ? "not enough data" : correlation.strength
        return "\(strength) · \(correlation.n) days"
    }

    /// Brightness shows strength only; green/red would wrongly suggest good/bad.
    private var color: Color {
        switch correlation.strength {
        case "strong", "moderate": return .white
        default: return Theme.tertiary
        }
    }
}

struct CorrelationDetailView: View {
    let correlation: Correlation
    @EnvironmentObject var model: AppModel

    var body: some View {
        let xDef = MetricCatalog.def(correlation.x)
        let yDef = MetricCatalog.def(correlation.y)
        ScrollView {
            VStack(spacing: 14) {
                if let xDef, let yDef {
                    Card {
                        SectionHeader(title: correlation.title)
                        ScatterChart(points: points(xDef, yDef), xDef: xDef, yDef: yDef)
                        KeyValueRow(key: "Correlation (r)", value: correlation.r.map { String(format: "%+.2f", $0) } ?? "–")
                        KeyValueRow(key: "Days compared", value: "\(correlation.n)")
                        if let slope = correlation.slope {
                            KeyValueRow(key: "Per unit of \(xDef.label.lowercased())",
                                        value: "\(Format.signed(slope, decimals: 3)) \(yDef.unit)")
                        }
                    }
                    Text(explanation(xDef, yDef))
                        .font(Font.fs(.footnote))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .screenBackground()
        .navigationTitle("Correlation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func points(_ xDef: MetricDef, _ yDef: MetricDef) -> [ScatterPoint] {
        var out: [ScatterPoint] = []
        let start = Format.addDays(model.today, -179)
        for (i, day) in model.days.enumerated() where day.date >= start {
            let xDate = Format.addDays(day.date, -correlation.lag)
            if xDef.isDayTotal && xDate >= model.today { continue }
            if yDef.isDayTotal && day.date >= model.today { continue }
            guard let xRow = model.daysByDate[xDate], let x = xDef.value(xRow), let y = yDef.value(day) else { continue }
            out.append(ScatterPoint(id: i, x: x, y: y))
        }
        return out
    }

    private func explanation(_ xDef: MetricDef, _ yDef: MetricDef) -> String {
        let when = correlation.lag == 1 ? "the previous day's" : "the same day's"
        return "Each dot is one day: \(yDef.label.lowercased()) against \(when) \(xDef.label.lowercased()). r runs from −1 to +1; values near 0 mean no linear relationship."
    }
}
