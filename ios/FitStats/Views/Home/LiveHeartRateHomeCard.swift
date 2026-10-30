import SwiftUI

/// Home: live heart rate from the band over Bluetooth. It connects by itself while Today is on
/// screen and lets go when you leave it or the app.
struct LiveHeartRateHomeCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveHeartRateMonitor
    /// In the Add cards preview the card shows but never connects.
    @Environment(\.homeCardPreview) private var isPreview

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Live heart rate", subtitle: "From your Fitbit Air over Bluetooth")
                Spacer()
                NavigationLink(value: DetailRoute.liveHeartRate) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(Font.fs(.caption))
                }
                .accessibilityLabel("Open live heart rate")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(isLive ? Theme.heart : Theme.tertiary)
                    .symbolEffect(.bounce, value: live.samples.last?.id ?? 0)
                Text(bpmText).font(Font.fredoka(40))
                Text("bpm").foregroundStyle(Theme.secondary)
                Spacer()
            }
            Text(caption).font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
        }
        .onAppear { if !isPreview { live.start() } }
        .onDisappear { if !isPreview { live.stop() } }
    }

    private var isLive: Bool {
        guard case .connected = live.state, let at = live.lastUpdate else { return false }
        return Date().timeIntervalSince(at) < 10 && live.latest?.contact != false
    }

    private var bpmText: String {
        guard isLive, let bpm = live.latest?.bpm, bpm > 0 else { return "–" }
        return "\(bpm)"
    }

    private var caption: String {
        if isLive, let bpm = live.latest?.bpm {
            return LiveZone(bpm: bpm, rhr: model.liveRestingHr, maxHr: model.liveMaxHr).name
        }
        switch live.state {
        case .connected:
            return live.latest?.contact == false ? "The band isn't on your wrist." : "Waiting for a reading…"
        case .connecting(let name): return "Connecting to \(name)…"
        case .scanning: return "Looking for your Fitbit Air. Turn on Always visible in Google Health → Share heart rate."
        case .poweredOff: return "Turn on Bluetooth."
        case .unauthorized: return "Allow Bluetooth for FitStats in Settings."
        case .unsupported: return "Bluetooth isn't available."
        case .idle: return isPreview ? "Connects to your band while Today is open." : "Starting…"
        }
    }
}
