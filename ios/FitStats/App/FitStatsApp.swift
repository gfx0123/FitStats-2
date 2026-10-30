import SwiftUI
import UserNotifications

@main
struct FitStatsApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var live = LiveHeartRateMonitor()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = ReminderDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.coach)
                .environmentObject(model.workout)
                .environmentObject(live)
                .preferredColorScheme(.dark)
                .tint(Theme.recoveryGreen)
                .onOpenURL { url in model.handleCallback(url) }
                .onAppear {
                    ReminderDelegate.shared.onOpen = { [model] route in
                        if route == "journal" { model.journalRequest = model.today }
                        if route == "weekly" { model.weeklyRequest = true }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        live.resume()
                        Task { await model.refreshAll() }
                    } else if phase == .background {
                        live.pause()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.appKey == nil {
                ConnectView()
            } else {
                MainTabs()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // The body map's figures follow Settings → Sex.
        .environment(\.bodyFigure, model.status?.settings.sex == "female" ? .female : .male)
    }
}

struct MainTabs: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = "today"

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.circle.fill") }
                .tag("today")
            TrainingView()
                .tabItem { Label("Training", systemImage: "dumbbell.fill") }
                .tag("training")
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag("coach")
            BodyAgeView()
                .tabItem { Label("Body age", systemImage: "hourglass") }
                .tag("bodyage")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag("settings")
        }
        .task { await model.refreshAll(force: true) }
        // A tapped journal reminder opens Today, which shows the journal.
        .onChange(of: model.journalRequest) { _, day in
            if day != nil { tab = "today" }
        }
        // An "Ask coach" button anywhere in the app opens the Coach with the question typed in.
        .onChange(of: model.coachDraft) { _, draft in
            if draft != nil { tab = "coach" }
        }
        .onChange(of: model.weeklyRequest) { _, open in
            if open { tab = "coach" }
        }
        // A tapped Home Screen widget opens its tab.
        .onChange(of: model.tabRequest) { _, request in
            guard let request else { return }
            // Trends opens from Today.
            if request == "trends" {
                tab = "today"
                model.showTrends = true
            } else {
                tab = request
            }
            model.tabRequest = nil
        }
    }
}
