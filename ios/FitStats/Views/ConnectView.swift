import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var model: AppModel
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 36)
                logo
                VStack(spacing: 8) {
                    Text("FitStats").font(Font.fredoka(38))
                    Text("Recovery, strain, sleep and stress from your Fitbit — and every metric turned into statistics.")
                        .font(Font.fs(.subheadline))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                }
                if let message = model.connectMessage {
                    Banner(icon: "exclamationmark.triangle.fill", text: message, color: Theme.recoveryRed)
                }
                Button {
                    working = true
                    Task {
                        await model.connect()
                        working = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if working { ProgressView().tint(.black) }
                        Text("Connect Google Health").font(Font.fs(.headline))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Theme.recoveryGreen))
                    .foregroundStyle(.black)
                }
                .disabled(working)
                checklist
                Text("While your Google Cloud app is in Testing mode, Google ends access after 7 days. When that happens FitStats shows a Reconnect button.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .screenBackground()
    }

    private var logo: some View {
        ZStack {
            RingGauge(progress: 0.82, color: Theme.recoveryGreen, lineWidth: 12) { EmptyView() }
                .frame(width: 120, height: 120)
            RingGauge(progress: 0.64, color: Theme.strain, endColor: Theme.strainEnd, lineWidth: 12) { EmptyView() }
                .frame(width: 84, height: 84)
            RingGauge(progress: 0.74, color: Theme.sleep, lineWidth: 12) { EmptyView() }
                .frame(width: 48, height: 48)
        }
    }

    private var checklist: some View {
        Card {
            SectionHeader(title: "Before you connect")
            step(1, "A Google Cloud project with the Google Health API enabled and a Web OAuth client.")
            step(2, "Its Client ID and secret saved in Supabase as GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET.")
            step(3, "Your Google account added as a test user.")
            Text("Step-by-step instructions are in SETUP.md in the repository.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(Font.fs(.caption, .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.track))
            Text(text).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
        }
    }
}
