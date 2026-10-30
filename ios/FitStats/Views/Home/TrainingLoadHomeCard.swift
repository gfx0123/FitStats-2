import SwiftUI

/// Home: the latest training load from the stats payload (`model.stats?.load`, built on the
/// server in lib/stats.ts): form with its status pill, fitness and fatigue, and a small chart of
/// the two over the last 42 days. Like TopInsightCard it describes your latest stats, not the
/// day being viewed, so the subtitle names the day it runs through. Nothing is computed here;
/// no load shows an empty state. No link: the full card is on the Insights tab.
struct TrainingLoadHomeCard: View {
    let date: String
    @EnvironmentObject var model: AppModel

    var body: some View {
        let load = model.stats?.load
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeader(title: "Training load", subtitle: subtitle(load))
                Spacer(minLength: 8)
                if let load, load.latest != nil {
                    LoadStatusPill(status: load.status)
                }
            }
            if let load, let latest = load.latest {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    // 1 decimal, as sent, so form reads as fitness minus fatigue (see TrainingLoadCard).
                    figure("Form", Format.signed(latest.form, decimals: 1), color: .white)
                    figure("Fitness", Format.number(latest.ctl, decimals: 1), color: TrainingLoadChart.fitnessColor)
                    figure("Fatigue", Format.number(latest.atl, decimals: 1), color: TrainingLoadChart.fatigueColor)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                TrainingLoadChart(series: load.series, days: 42, height: 90)
                if load.status == "calibrating" {
                    Text(TrainingLoadStatus.calibratingText(load, today: model.stats?.today ?? model.today))
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.tertiary)
                } else if load.spike {
                    Label("Load spike: your last 7 days averaged at least 1.5 times your last 28.", systemImage: "exclamationmark.triangle.fill")
                        .font(Font.fs(.caption))
                        .foregroundStyle(Theme.recoveryRed)
                }
            } else {
                EmptyStateView(icon: "speedometer", title: "No training load yet", message: emptyMessage)
            }
        }
    }

    private func figure(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            Text(value)
                .font(Font.fredoka(22))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func subtitle(_ load: TrainingLoad?) -> String? {
        guard let last = load?.latest?.date else { return nil }
        if last == Format.addDays(model.today, -1) { return "Through yesterday" }
        return "Through \(Format.shortDay(last))"
    }

    private var emptyMessage: String {
        if model.stats == nil { return "Training load appears once a few days have synced." }
        if model.stats?.load == nil { return "Training load appears after the server's next statistics update." }
        return "It builds from the heart rate your band records, once days with heart rate have synced."
    }
}
