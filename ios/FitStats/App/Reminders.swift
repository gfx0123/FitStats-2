import SwiftUI
import UIKit
import UserNotifications

/// Bedtime and journal reminders: local notifications made from the data on the phone and made
/// again every time FitStats refreshes, so they follow the Tonight plan. Both are off until
/// turned on in Settings (or with the bell on the Tonight card).
///
/// Tonight's bedtime reminder uses tonight's plan. The six nights after it are estimated the same
/// way from what is known now (their strain isn't, so it counts as none), and they become exact
/// when the app refreshes on those days. The journal reminder skips days already logged.
enum Reminders {
    static let bedtimeKey = "reminders.bedtime"
    /// Minutes before the plan's "In bed by" time.
    static let bedtimeLeadKey = "reminders.bedtimeLead"
    static let journalKey = "reminders.journal"
    /// Sunday at 19:00: the week's summary (the server writes it from 18:00).
    static let weeklyKey = "reminders.weekly"
    /// Minutes from midnight.
    static let journalTimeKey = "reminders.journalTime"

    static let leadChoices = [15, 30, 45, 60]
    static let defaultLead = 30
    static let defaultJournalTime = 21 * 60 + 30

    private static let prefix = "fitstats.reminder."
    private static let nights = 7

    struct Planned: Equatable {
        let id: String
        let date: Date
        let title: String
        let body: String
        var route: String? = nil
    }

    static var lead: Int {
        let v = UserDefaults.standard.integer(forKey: bedtimeLeadKey)
        return leadChoices.contains(v) ? v : defaultLead
    }

    static var journalTime: Int {
        let v = UserDefaults.standard.object(forKey: journalTimeKey) as? Int
        return v.map { min(max($0, 0), 1439) } ?? defaultJournalTime
    }

    // MARK: what to remind

    /// Local midnight starting `ymd`.
    static func midnight(_ ymd: String, _ zone: TimeZone) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// One reminder a night, `lead` minutes before the plan's bedtime, for tonight and the six
    /// nights after (estimated). Nights without a bedtime yet (fewer than 3 recent wake times) and
    /// times already past are left out.
    static func bedtimes(days: [String: DayRecord], today: String, sleepNeedMin: Double, wakeTimes: [Int?]? = nil,
                         zone: TimeZone, lead: Int, now: Date) -> [Planned] {
        (0..<nights).compactMap { offset -> Planned? in
            let night = Format.addDays(today, offset)
            // Each night uses the wake-up time set for its own next morning.
            let plan = SleepPlan.plan(days: days, today: night, sleepNeedMin: sleepNeedMin, wakeTimes: wakeTimes)
            guard let bedtime = plan.bedtimeMin, let base = midnight(Format.addDays(night, 1), zone) else { return nil }
            let fire = base.addingTimeInterval((bedtime - Double(lead)) * 60)
            guard fire > now.addingTimeInterval(60) else { return nil }
            let clock = Format.clock(bedtime)
            let need = Format.duration(plan.needMin)
            let body: String
            let wake = plan.wakeMin.map { Format.clock($0) } ?? ""
            if offset == 0 {
                let usual = plan.wakeBasis == .set ? " before your \(wake) wake-up" : " before your usual \(wake) wake-up"
                body = "Lights out by \(clock) for \(need) of sleep\(plan.wakeMin == nil ? "" : usual)."
            } else if plan.wakeBasis == .set {
                body = "Lights out around \(clock) for about \(need) of sleep before your \(wake) wake-up. Open FitStats for tonight's exact plan."
            } else {
                body = "Lights out around \(clock) for about \(need) of sleep. Open FitStats for tonight's exact plan."
            }
            return Planned(id: "\(prefix)bedtime.\(night)", date: fire, title: "Bedtime in \(lead) min", body: body)
        }
    }

    /// One reminder a day at `minute` for today and the six days after, except days with a
    /// journal entry, and times already past.
    static func journals(logged: Set<String>, today: String, zone: TimeZone, minute: Int, now: Date) -> [Planned] {
        (0..<nights).compactMap { offset -> Planned? in
            let day = Format.addDays(today, offset)
            guard !logged.contains(day), let base = midnight(day, zone) else { return nil }
            let fire = base.addingTimeInterval(Double(minute) * 60)
            guard fire > now.addingTimeInterval(60) else { return nil }
            return Planned(id: "\(prefix)journal.\(day)", date: fire, title: "How was today?",
                           body: "Tag what you did, and FitStats links it to your sleep and recovery.",
                           route: "journal")
        }
    }

    /// Sunday 19:00 this week and next (times already past are left out).
    static func weeklies(today: String, zone: TimeZone, now: Date) -> [Planned] {
        let sundays = (0..<14).map { Format.addDays(today, $0) }.filter { SleepPlan.weekdayIndex($0) == 6 }
        return sundays.compactMap { day -> Planned? in
            guard let base = midnight(day, zone) else { return nil }
            let fire = base.addingTimeInterval(19 * 3600)
            guard fire > now.addingTimeInterval(60) else { return nil }
            return Planned(id: "\(prefix)weekly.\(day)", date: fire, title: "Your week in review",
                           body: "Your coach's summary of this week's training, sleep and recovery. Tap to read it.", route: "weekly")
        }
    }

    // MARK: scheduling

    /// Replaces FitStats' pending reminders with the ones the current settings and data call for.
    @MainActor
    static func update(_ model: AppModel) async {
        guard !model.isFixture else { return }
        let defaults = UserDefaults.standard
        let zone = model.zone ?? .current
        let now = Date()
        var planned: [Planned] = []
        if defaults.bool(forKey: bedtimeKey) {
            planned += bedtimes(days: model.daysByDate, today: model.today,
                                sleepNeedMin: Double(model.status?.settings.sleepNeedMin ?? 480),
                                wakeTimes: model.wakeTimes, zone: zone, lead: lead, now: now)
        }
        if defaults.bool(forKey: weeklyKey) {
            planned += weeklies(today: model.today, zone: zone, now: now)
        }
        if defaults.bool(forKey: journalKey) {
            let logged = Set(model.journal.keys)
            planned += journals(logged: logged, today: model.today, zone: zone, minute: journalTime, now: now)
        }
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        for p in planned {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            if let route = p.route { content.userInfo = ["route": route] }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, p.date.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
        }
    }

    /// Asks for permission to notify (iOS shows its prompt only the first time). False when
    /// notifications are off for FitStats.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// FitStats' notification settings in the Settings app.
    @MainActor
    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// Shows reminders while FitStats is open too, and passes on which one was tapped.
final class ReminderDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderDelegate()
    /// Called on the main queue with a tapped reminder's route ("journal").
    var onOpen: ((String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let route = response.notification.request.content.userInfo["route"] as? String
        DispatchQueue.main.async {
            if let route { self.onOpen?(route) }
            completionHandler()
        }
    }
}

/// Turning a reminder on asks for permission first; when notifications are off for FitStats the
/// switch goes back off and the row offers iOS Settings.
struct ReminderToggle: View {
    let title: String
    let key: String
    @AppStorage private var isOn: Bool
    @State private var denied = false
    @EnvironmentObject private var model: AppModel

    init(_ title: String, key: String) {
        self.title = title
        self.key = key
        _isOn = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { set($0) }))
            .tint(Theme.recoveryGreen)
            .accessibilityIdentifier("toggle-\(key)")
        if denied {
            Button("Notifications are off for FitStats. Open Settings") { Reminders.openSystemSettings() }
                .font(Font.fs(.footnote))
        }
    }

    private func set(_ on: Bool) {
        guard on else {
            isOn = false
            Task { await Reminders.update(model) }
            return
        }
        Task {
            let allowed = await Reminders.requestPermission()
            denied = !allowed
            isOn = allowed
            await Reminders.update(model)
        }
    }
}
