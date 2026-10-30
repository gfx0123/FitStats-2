import Charts
import SwiftUI
import UIKit

/// Heart-rate reserve zone of a live reading, the same bands as the workout zones (50–60 … 90 %+).
struct LiveZone {
    let name: String
    let color: Color
    /// Share of heart-rate reserve, 0–1+.
    let reserve: Double

    private static let names = ["Zone 1", "Zone 2", "Zone 3", "Zone 4", "Zone 5"]
    private static let colors: [Color] = [Theme.stress, Theme.recoveryGreen, Theme.recoveryYellow, Theme.body, Theme.recoveryRed]

    init(bpm: Int, rhr: Double, maxHr: Double) {
        let r = maxHr - rhr > 20 ? (Double(bpm) - rhr) / (maxHr - rhr) : 0
        reserve = r
        let z = Int(((r - 0.5) * 10).rounded(.down))
        if r < 0.5 {
            name = "Below zone 1"
            color = Theme.heart
        } else {
            let i = Swift.min(4, Swift.max(0, z))
            name = Self.names[i]
            color = Self.colors[i]
        }
    }
}

extension AppModel {
    /// Max heart rate for live zones: the server's value in use, else 208 − 0.7 × age, else 190.
    var liveMaxHr: Double {
        if let v = status?.maxHr?.value { return v }
        if let age = status?.profile.age { return (208 - 0.7 * Double(age)).rounded() }
        return 190
    }

    /// The latest resting heart rate, else 60.
    var liveRestingHr: Double {
        days.last(where: { $0.double("rhr") != nil })?.double("rhr") ?? 60
    }
}

struct LiveHeartRateView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveHeartRateMonitor

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                readingCard
                if !live.samples.isEmpty { chartCard }
                if case .connected = live.state { sessionCard }
                if case .scanning = live.state, !live.devices.isEmpty { devicesCard }
                helpCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("live-hr")
        }
        .screenBackground()
        .navigationTitle("Live heart rate")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    private var current: Int? {
        guard case .connected = live.state, let m = live.latest, m.bpm > 0, m.contact != false else { return nil }
        // A reading older than 10 s is no longer live.
        guard let at = live.lastUpdate, Date().timeIntervalSince(at) < 10 else { return nil }
        return m.bpm
    }

    private var readingCard: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "heart.fill")
                    .font(Font.fredoka(40, weight: .regular))
                    .foregroundStyle(zone.map(\.color) ?? Theme.tertiary)
                    .symbolEffect(.bounce, value: live.samples.last?.id ?? 0)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(current.map { "\($0)" } ?? "–").font(Font.fredoka(64))
                        Text("bpm").font(Font.fs(.title3)).foregroundStyle(Theme.secondary)
                    }
                    if let zone, current != nil {
                        Text("\(zone.name) · \(Int((zone.reserve * 100).rounded()))% of heart-rate reserve")
                            .font(Font.fs(.footnote))
                            .foregroundStyle(zone.color)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(statusText).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
            if case .unauthorized = live.state {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(Font.fs(.footnote, .semibold))
            }
        }
    }

    private var zone: LiveZone? {
        current.map { LiveZone(bpm: $0, rhr: model.liveRestingHr, maxHr: model.liveMaxHr) }
    }

    private var statusText: String {
        switch live.state {
        case .idle: return live.enabled ? "Starting…" : "Live heart rate is off. Turn it on in Settings → Live heart rate."
        case .unsupported: return "This iPhone can't use Bluetooth for this."
        case .poweredOff: return "Turn on Bluetooth to see your live heart rate."
        case .unauthorized: return "FitStats isn't allowed to use Bluetooth. Turn it on in Settings → FitStats."
        case .scanning: return "Looking for your Fitbit Air…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .connected(let name):
            if live.latest?.contact == false { return "Connected to \(name). The band isn't on your wrist." }
            if current == nil { return "Connected to \(name). Waiting for a reading…" }
            let battery = live.battery.map { " · battery \($0)%" } ?? ""
            return "Live from \(name)\(battery)"
        }
    }

    private var chartCard: some View {
        let cutoff = Date().addingTimeInterval(-300)
        let points = live.samples.filter { $0.date >= cutoff }
        return Card {
            SectionHeader(title: "Last 5 minutes")
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("Time", p.date), y: .value("BPM", p.bpm))
                        .foregroundStyle(Theme.heart)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Theme.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.track)
                    AxisValueLabel().foregroundStyle(Theme.tertiary)
                }
            }
            .frame(height: 170)
        }
    }

    private var sessionCard: some View {
        Card {
            SectionHeader(title: "This session")
            KeyValueRow(key: "Lowest", value: live.sessionMin.map { "\($0) bpm" } ?? "–")
            KeyValueRow(key: "Average", value: live.sessionAvg.map { "\(Int($0.rounded())) bpm" } ?? "–")
            KeyValueRow(key: "Highest", value: live.sessionMax.map { "\($0) bpm" } ?? "–")
            if live.sendsRR {
                KeyValueRow(key: "Live HRV (RMSSD, last minute)", value: live.liveRMSSD.map { "\(Int($0.rounded())) ms" } ?? "measuring…")
                Text("From the beat-to-beat intervals the band sends. Sitting still gives the steadiest reading; it isn't comparable with your overnight HRV.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            } else if live.samples.count >= 10 {
                Text("Your band sends heart rate only, no beat-to-beat intervals, so there is no live HRV.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private var devicesCard: some View {
        Card {
            SectionHeader(title: "Heart-rate sensors nearby", subtitle: "Tap yours to connect")
            ForEach(live.devices) { device in
                Button {
                    live.connect(device)
                } label: {
                    HStack {
                        Image(systemName: "heart.circle").foregroundStyle(Theme.heart)
                        Text(device.name).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var helpCard: some View {
        Card {
            SectionHeader(title: "How to connect")
            Text("In the Google Health app, open Fitbit Air → Share heart rate. Turn on Always visible, or keep that screen open while FitStats connects. FitStats remembers your band after that.")
                .font(Font.fs(.footnote))
                .foregroundStyle(Theme.secondary)
            Text("Live heart rate works only while FitStats is open and the band is nearby. It isn't saved; your history still comes from Google after the band syncs.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
