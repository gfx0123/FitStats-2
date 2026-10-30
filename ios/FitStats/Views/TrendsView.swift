import SwiftUI

/// The tools linked at the top of Trends.
private enum TrendsRoute: Hashable {
    case insights
    case calendar
    case compare
}

struct TrendsView: View {
    @EnvironmentObject var model: AppModel
    /// In a sheet: a Done button that closes it.
    var onDone: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toolLinks
                    if let stats = model.stats {
                        Text("\(stats.dayCount) days of data since \(Format.shortDay(stats.firstDate))")
                            .font(Font.fs(.footnote))
                            .foregroundStyle(Theme.secondary)
                    }
                    ForEach(MetricCategory.allCases) { category in
                        let defs = MetricCatalog.all.filter { $0.category == category && hasData($0) }
                        if !defs.isEmpty {
                            Card(padding: 8) {
                                SectionHeader(title: category.title).padding([.top, .horizontal], 8)
                                ForEach(defs) { def in
                                    NavigationLink(value: DetailRoute.metric(def.key)) {
                                        MetricRow(def: def)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("metric-\(def.key)")
                                }
                            }
                        }
                    }
                    if model.days.isEmpty {
                        Card {
                            EmptyStateView(icon: "chart.xyaxis.line", title: "No data yet",
                                           message: "Trends appear after the first sync finishes.")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .refreshable { await model.pullToRefresh() }
            .screenBackground()
            .navigationTitle("Trends")
            .swipeBackFromAnywhere()
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done", action: onDone).fontWeight(.semibold).accessibilityIdentifier("trends-done")
                    }
                }
            }
            .navigationDestination(for: DetailRoute.self) { DetailDestination(route: $0) }
            .navigationDestination(for: TrendsRoute.self) { route in
                switch route {
                case .insights: InsightsView()
                case .calendar: CalendarHeatmapView()
                case .compare: ComparePeriodsView()
                }
            }
            .navigationDestination(for: Correlation.ID.self) { id in
                if let c = model.stats?.correlations.first(where: { $0.id == id }) {
                    CorrelationDetailView(correlation: c)
                }
            }
        }
    }

    private var toolLinks: some View {
        HStack(spacing: 10) {
            NavigationLink(value: TrendsRoute.insights) {
                toolTile("Insights", icon: "sparkles")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-insights")
            NavigationLink(value: TrendsRoute.calendar) {
                toolTile("Calendar", icon: "calendar")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-calendar")
            NavigationLink(value: TrendsRoute.compare) {
                toolTile("Compare", icon: "arrow.left.arrow.right")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("open-compare")
        }
    }

    private func toolTile(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(Font.fs(.subheadline))
                    .foregroundStyle(Theme.recoveryGreen)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
            }
            // The same height whatever the icon, so the titles line up.
            .frame(height: 22)
            Text(title)
                .font(Font.fs(.subheadline, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Glass(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func hasData(_ def: MetricDef) -> Bool {
        if let n = model.stats?.metrics[def.key]?.ranges["all"]?.n { return n > 0 }
        return model.days.contains { def.value($0) != nil }
    }
}

private struct MetricRow: View {
    let def: MetricDef
    @EnvironmentObject var model: AppModel

    var body: some View {
        let stats = model.stats?.metrics[def.key]
        // The same 30 days as the average: day totals cover the 30 complete days before today.
        let recent = model.series(def, from: Format.addDays(model.today, def.isDayTotal ? -30 : -29), through: model.today).map(\.value)
        HStack(spacing: 12) {
            Image(systemName: def.icon)
                .font(Font.fs(.subheadline))
                .frame(width: 32, height: 32)
                .background(Circle().fill(def.category.color.opacity(0.16)))
                .foregroundStyle(def.category.color)
            VStack(alignment: .leading, spacing: 2) {
                FittingText(def.shortLabel, short: def.compactLabel).font(Font.fs(.subheadline, .medium))
                HStack(spacing: 6) {
                    Text(def.formatted(stats?.ranges["30"]?.mean))
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.secondary)
                    Text("30d avg").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                }
            }
            Spacer(minLength: 8)
            if recent.count >= 3 {
                SparklineView(values: recent, color: def.category.color).frame(width: 70, height: 26)
            }
            RangeChangeBadge(def: def, range: stats?.ranges["30"])
                .frame(minWidth: 44, alignment: .trailing)
            Image(systemName: "chevron.right").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

/// A range's change against the range before it: a percentage, or for clock times and the skin
/// temperature deviation the absolute change ("48m", "0.11 °C"), as a percent of an arbitrary zero
/// means nothing.
private struct RangeChangeBadge: View {
    let def: MetricDef
    let range: RangeStats?

    var body: some View {
        if def.comparesAbsolute {
            if let change = absoluteChange, let text = changeText(change) {
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                    Text(text)
                }
                .font(Font.fs(.caption2, .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.secondary.opacity(0.16)))
                .foregroundStyle(Theme.secondary)
            }
        } else {
            DeltaBadge(change: range?.changePct, better: def.better)
        }
    }

    /// The server's change, or mean − previous mean in stats cached before it sent one.
    private var absoluteChange: Double? {
        if let change = range?.change { return change }
        guard let mean = range?.mean, let prev = range?.prevMean else { return nil }
        return mean - prev
    }

    /// Nil when the change rounds to nothing.
    private func changeText(_ change: Double) -> String? {
        let size = abs(change)
        switch def.format {
        case .clock, .duration:
            return size.rounded() >= 1 ? Format.duration(size) : nil
        case .number, .signed, .percent:
            let scale = pow(10, Double(def.decimals))
            guard (size * scale).rounded() >= 1 else { return nil }
            let number = Format.number(size, decimals: def.decimals)
            return def.unit.isEmpty || def.unit == "%" ? "\(number)\(def.unit)" : "\(number) \(def.unit)"
        }
    }
}

struct MetricDetailView: View {
    let def: MetricDef
    @EnvironmentObject var model: AppModel
    @State var range = "30"

    private struct RangeOption: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private let ranges = [
        RangeOption(key: "7", label: "7D"), RangeOption(key: "30", label: "30D"), RangeOption(key: "90", label: "90D"),
        RangeOption(key: "365", label: "1Y"), RangeOption(key: "all", label: "All"),
    ]

    var body: some View {
        let stats = model.stats?.metrics[def.key]
        let rs = stats?.ranges[range]
        let from: String = {
            // Day totals cover the complete days before today, so their window starts a day earlier.
            if let days = Int(range) { return Format.addDays(model.today, def.isDayTotal ? -days : -(days - 1)) }
            return model.days.first?.date ?? Format.addDays(model.today, -365)
        }()
        let points = model.series(def, from: from, through: model.today)
        ScrollView {
            VStack(spacing: 14) {
                Picker("Range", selection: $range) {
                    ForEach(ranges) { Text($0.label).tag($0.key) }
                }
                .pickerStyle(.segmented)

                Card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Average").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                            Text(def.formatted(rs?.mean)).font(Font.fredoka(30))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            RangeChangeBadge(def: def, range: rs)
                            if let prev = rs?.prevMean {
                                Text("prev. \(def.formatted(prev))").font(Font.fs(.caption2)).foregroundStyle(Theme.tertiary)
                            }
                        }
                    }
                    if points.count >= 2 {
                        DailyMetricChart(points: points, def: def, average: rs?.mean, color: def.category.color, height: 220)
                    } else {
                        Text("Not enough data in this range yet.").font(Font.fs(.footnote)).foregroundStyle(Theme.tertiary)
                    }
                }

                if let rs { statsCard(rs) }

                if let weekday = stats?.weekday, weekday.contains(where: { $0 != nil }) {
                    Card {
                        SectionHeader(title: "By weekday", subtitle: "Last 90 days")
                        WeekdayChart(values: weekday, def: def, color: def.category.color)
                    }
                }

                if stats?.best != nil || stats?.worst != nil {
                    Card {
                        SectionHeader(title: "Records")
                        if let best = stats?.best {
                            KeyValueRow(key: "Best · \(Format.shortDay(best.date))", value: def.formatted(best.value), color: Theme.recoveryGreen)
                        }
                        if let worst = stats?.worst {
                            KeyValueRow(key: "Worst · \(Format.shortDay(worst.date))", value: def.formatted(worst.value), color: Theme.recoveryRed)
                        }
                    }
                }

                if def.isDayTotal {
                    Text("Today is excluded from these numbers until the day is over.")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .screenBackground()
        .navigationTitle(def.label)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AskCoachButton(text: "About my \(def.label) trend: what's changed, why, and what should I do about it?")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statsCard(_ rs: RangeStats) -> some View {
        Card {
            SectionHeader(title: "Statistics", subtitle: "\(rs.n) days with data")
            KeyValueRow(key: "Median", value: def.formatted(rs.median))
            KeyValueRow(key: "Lowest · \(Format.shortDay(rs.minDate))", value: def.formatted(rs.min))
            KeyValueRow(key: "Highest · \(Format.shortDay(rs.maxDate))", value: def.formatted(rs.max))
            if let sd = rs.sd {
                KeyValueRow(key: "Variability (SD)", value: spreadText(sd))
            }
            if let sum = rs.sum {
                KeyValueRow(key: "Total", value: def.formatted(sum))
            }
            if let slope = rs.slopePerWeek {
                KeyValueRow(key: "Trend per week", value: trendText(slope))
            }
        }
    }

    /// A standard deviation is a size, so it never gets a sign or a clock format.
    private func spreadText(_ sd: Double) -> String {
        switch def.format {
        case .clock: return Format.duration(sd)
        case .signed: return Format.number(sd, decimals: def.decimals) + (def.unit.isEmpty ? "" : " \(def.unit)")
        default: return def.formatted(sd)
        }
    }

    private func trendText(_ slope: Double) -> String {
        switch def.format {
        case .duration, .clock:
            return (slope >= 0 ? "+" : "−") + Format.duration(abs(slope))
        case .percent:
            return Format.signed(slope, decimals: 1) + " pts"
        case .number, .signed:
            let unit = def.unit.isEmpty ? "" : " \(def.unit)"
            return Format.signed(slope, decimals: max(def.decimals, 1)) + unit
        }
    }
}

/// Trends in a sheet from Today, with a Done button.
struct TrendsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TrendsView(onDone: { dismiss() })
    }
}
