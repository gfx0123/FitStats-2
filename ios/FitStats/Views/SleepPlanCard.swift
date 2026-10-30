import SwiftUI

/// Today: tonight's sleep need and the bedtime that fits your usual wake time (Core/SleepPlanner.swift).
struct SleepPlanCard: View {
    let plan: SleepPlan
    @EnvironmentObject private var model: AppModel
    @AppStorage(Reminders.bedtimeKey) private var reminderOn = false
    @State private var denied = false
    @State private var editingWakeTimes = false

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Tonight")
                Spacer()
                reminderButton
            }
            HStack(alignment: .top) {
                stat("Need tonight", Format.duration(plan.needMin))
                Spacer()
                stat("In bed by", plan.bedtimeMin.map { Format.clock($0) } ?? "–")
                Spacer()
                stat("Wake at", plan.wakeMin.map { Format.clock($0) } ?? "–")
            }
            FlowLayout(spacing: 6) {
                part("Base \(Format.duration(plan.baseMin))")
                if plan.strainMin > 0 { part("+\(Format.duration(plan.strainMin)) for today's strain") }
                if plan.debtMin > 0 { part("+\(Format.duration(plan.debtMin)) to repay debt") }
                if plan.napMin > 0 { part("−\(Format.duration(plan.napMin)) naps") }
            }
            Text(explanation)
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
            Button { editingWakeTimes = true } label: {
                Label(model.wakeTimes == nil ? "Set your wake-up times" : "Wake-up times", systemImage: "alarm")
                    .font(Font.fs(.caption, .semibold))
                    .foregroundStyle(Theme.sleep)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tonight-wake-times")
            if denied {
                Button("Notifications are off for FitStats. Open Settings") { Reminders.openSystemSettings() }
                    .font(Font.fs(.caption, .semibold))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sleep-plan")
        .sheet(isPresented: $editingWakeTimes) {
            NavigationStack {
                WakeTimesView(closesOnSave: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { editingWakeTimes = false } }
                    }
            }
            .environmentObject(model)
            .preferredColorScheme(.dark)
        }
    }

    /// Turns the bedtime reminder on or off (Settings has its lead time).
    private var reminderButton: some View {
        Button {
            let on = !reminderOn
            Task {
                if on, !(await Reminders.requestPermission()) {
                    denied = true
                    return
                }
                denied = false
                reminderOn = on
                await Reminders.update(model)
            }
        } label: {
            Label(reminderOn ? "Reminder on" : "Remind me",
                  systemImage: reminderOn ? "bell.fill" : (denied ? "bell.slash" : "bell"))
                .font(Font.fs(.caption, .semibold))
                .foregroundStyle(reminderOn ? Theme.sleep : Theme.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(denied ? "Notifications are off for FitStats in iOS Settings" : "A notification before bedtime"))
        .accessibilityIdentifier("tonight-reminder")
    }

    private var explanation: String {
        let inBed = "\(Format.duration(plan.inBedMin)) in bed at your \(Int((plan.efficiency * 100).rounded()))% sleep efficiency"
        guard plan.bedtimeMin != nil, let basis = plan.wakeBasis else {
            return "\(inBed). A bedtime appears once 3 recent nights have a wake time, or set your wake-up times."
        }
        let usual: String
        switch basis {
        case .set: usual = "the time you set for \(WakeTimesView.dayNames[SleepPlan.weekdayIndex(Format.addDays(model.today, 1))])"
        case .all: usual = "your usual wake time"
        default: usual = "your usual \(basis.rawValue) wake time"
        }
        return "\(inBed), to wake at \(usual). Today's strain and a quarter of the last week's sleep debt (up to 1h) add to your base need; today's naps take some off."
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
            Text(value).font(Font.fredoka(22))
        }
    }

    private func part(_ text: String) -> some View {
        Text(text)
            .font(Font.fs(.caption2, .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.sleep.opacity(0.16)))
            .foregroundStyle(Theme.sleep)
    }
}
