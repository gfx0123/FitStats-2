import SwiftUI

/// A Home card's settings, like "Edit Widget" on iOS: opened by tapping a card while Home is
/// being edited. Every change shows on Home right away (behind the sheet).
struct HomeCardSettingsView: View {
    @State var draft: HomeItem
    let canRemove: Bool
    var onChange: (HomeItem) -> Void
    var onRemove: () -> Void
    /// A Smart Stack's card back onto Home on its own.
    var onExtract: (StackEntry) -> Void = { _ in }
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let dayChoices = [7, 14, 30, 90]

    var body: some View {
        NavigationStack {
            Form {
                Section("Size") {
                    Picker("Size", selection: $draft.size) {
                        ForEach(draft.card.sizes) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("card-settings-size")
                }
                cardSections
                if canRemove {
                    Section {
                        Button("Remove from Home", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(draft.title)
            .swipeBackFromAnywhere()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("card-settings-done")
                }
            }
        }
        .onChange(of: draft) { _, new in onChange(new) }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var cardSections: some View {
        switch draft.card {
        case .metric:
            Section("Metric") {
                NavigationLink {
                    MetricPickerList(selection: metricBinding)
                } label: {
                    LabeledContent("Metric", value: MetricCatalog.def(draft.spec.metricKey)?.label ?? "Steps")
                }
                .accessibilityIdentifier("card-settings-metric")
            }
            daysSection(card: .metric)
        case .recoveryTrend, .hrvTrend, .restingHrTrend:
            daysSection(card: draft.card)
        case .vitals:
            metricsSection(keys: VitalsGlance.keys, defaults: VitalsGlance.keys,
                           footer: "A small card shows the first 3, medium and large all you pick.")
        case .activity:
            metricsSection(keys: ActivityGlance.keys, defaults: ActivityGlance.defaultKeys,
                           footer: "Shown next to your steps: a medium card fits 3, a large card shows all you pick.")
        case .thisWeek:
            metricsSection(keys: ThisWeekGlance.keys + ["hrv_rmssd", "rhr", "sleep_score", "calories_active"],
                           defaults: ThisWeekGlance.keys,
                           footer: "Each shows its daily average against the week before. A small card shows the first 3.")
        case .stack:
            stackSections
        default:
            Section {
                Text("This card has no other settings.")
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: shared sections

    private func daysSection(card: HomeCard) -> some View {
        Section("Period") {
            Picker("Days", selection: Binding(
                get: { draft.options.days ?? card.defaultDays },
                set: { draft.options.days = $0 }
            )) {
                ForEach(Self.dayChoices, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func metricsSection(keys: [String], defaults: [String], footer: String) -> some View {
        let chosen = draft.options.metrics ?? defaults
        return Section {
            ForEach(keys, id: \.self) { key in
                if let def = MetricCatalog.def(key) {
                    Toggle(isOn: Binding(
                        get: { chosen.contains(key) },
                        set: { on in
                            var next = draft.options.metrics ?? defaults
                            if on {
                                if !next.contains(key) { next.append(key) }
                            } else if next.count > 1 {
                                next.removeAll { $0 == key }
                            }
                            // Keep the card's own order, so a toggled metric doesn't jump to the end.
                            draft.options.metrics = keys.filter(next.contains)
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(def.label)
                                if !model.recorded.contains(key) {
                                    Text("Not recorded yet").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
                                }
                            }
                        } icon: {
                            Image(systemName: def.icon).foregroundStyle(def.category.color)
                        }
                    }
                }
            }
        } header: {
            Text("Shows")
        } footer: {
            Text(footer)
        }
    }

    private var metricBinding: Binding<String> {
        Binding(
            get: { draft.options.metric ?? "steps" },
            set: { draft.options.metric = $0 }
        )
    }

    // MARK: Smart Stack

    private var entries: [StackEntry] { draft.options.stack ?? [] }

    @ViewBuilder private var stackSections: some View {
        Section {
            ForEach(entries) { entry in
                stackRow(entry)
            }
            .onMove { from, to in
                var next = entries
                next.move(fromOffsets: from, toOffset: to)
                draft.options.stack = next
            }
            .onDelete { offsets in
                var next = entries
                next.remove(atOffsets: offsets)
                if !next.isEmpty { draft.options.stack = next }
            }
            Menu {
                ForEach(HomeCard.allCases.filter { $0 != .stack }) { card in
                    Button {
                        draft.options.stack = entries + [HomeLayout.newEntry(card)]
                    } label: {
                        Label(card.title, systemImage: card.icon)
                    }
                }
            } label: {
                Label("Add a card", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("stack-add-card")
        } header: {
            Text("Cards in this stack")
        } footer: {
            Text("Swipe sideways on the stack to go through them. Drag the handles to reorder, or tap the arrow to put a card back on Home on its own. On Home, dropping a card on the stack's middle adds it too.")
        }
        .environment(\.editMode, .constant(.active))
        Section {
            Toggle("Smart rotate", isOn: Binding(
                get: { draft.options.rotate ?? true },
                set: { draft.options.rotate = $0 }
            ))
        } footer: {
            Text("Opens on the card that fits the time of day: last night and recovery in the morning, activity during the day, tonight's plan in the evening.")
        }
    }

    @ViewBuilder private func stackRow(_ entry: StackEntry) -> some View {
        HStack {
            stackLabel(entry)
            Spacer(minLength: 8)
            if entries.count > 1 {
                Button {
                    onExtract(entry)
                    draft.options.stack = entries.filter { $0.id != entry.id }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Move \(entry.card.title) to Home"))
            }
        }
    }

    @ViewBuilder private func stackLabel(_ entry: StackEntry) -> some View {
        if entry.card == .metric {
            NavigationLink {
                MetricPickerList(selection: Binding(
                    get: { entry.options.metric ?? "steps" },
                    set: { key in update(entry.id) { $0.options.metric = key } }
                ))
            } label: {
                Label(MetricCatalog.def(entry.spec.metricKey)?.label ?? "Metric", systemImage: HomeCard.metric.icon)
            }
        } else {
            Label(entry.card.title, systemImage: entry.card.icon)
        }
    }

    private func update(_ id: String, _ change: (inout StackEntry) -> Void) {
        var next = entries
        guard let i = next.firstIndex(where: { $0.id == id }) else { return }
        change(&next[i])
        draft.options.stack = next
    }
}

/// Every metric FitStats has recorded, by category, for a Metric card.
struct MetricPickerList: View {
    @Binding var selection: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(MetricCategory.allCases) { category in
                let defs = MetricCatalog.all.filter { $0.category == category && (model.recorded.isEmpty || model.recorded.contains($0.key)) }
                if !defs.isEmpty {
                    Section(category.title) {
                        ForEach(defs) { def in
                            Button {
                                selection = def.key
                                dismiss()
                            } label: {
                                HStack {
                                    Label {
                                        Text(def.label).foregroundStyle(.white)
                                    } icon: {
                                        Image(systemName: def.icon).foregroundStyle(category.color)
                                    }
                                    Spacer()
                                    if def.key == selection {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.recoveryGreen)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("metric-pick-\(def.key)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Metric")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// When each part of the day starts, for time-of-day Home layouts.
struct HomeTimesSheet: View {
    @Binding var config: HomeConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Morning starts", selection: time(\.morningStart), displayedComponents: .hourAndMinute)
                    DatePicker("Day starts", selection: time(\.dayStart), displayedComponents: .hourAndMinute)
                    DatePicker("Evening starts", selection: time(\.eveningStart), displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Home switches to that part of the day's layout at these times, by your phone's clock. Each part starts at least 30 minutes after the one before.")
                }
            }
            .navigationTitle("Times of day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    /// A start time as a Date today; setting it keeps morning < day < evening.
    private func time(_ path: WritableKeyPath<HomeConfig, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = config[keyPath: path]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var next = config
                next[keyPath: path] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                next.morningStart = min(next.morningStart, 1440 - 90)
                next.dayStart = min(max(next.dayStart, next.morningStart + 30), 1440 - 60)
                next.eveningStart = min(max(next.eveningStart, next.dayStart + 30), 1440 - 30)
                config = next
            }
        )
    }
}
