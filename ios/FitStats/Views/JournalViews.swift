import SwiftUI
import UIKit

/// Lays children out left to right and wraps them onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, maxWidth: width)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = Self.size(of: view, maxWidth: bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// Its own size, or the container's width when it is wider (a long tag with large text):
    /// cut short rather than running past the card's edge.
    private static func size(of view: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth, maxWidth.isFinite else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

struct TagChip: View {
    let label: String
    let icon: String
    var selected = true
    /// Read-only and small (Today): a filled pill without the outline the selectable chips have.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            // Unknown symbol names (a newer server's tags on an older iOS) fall back to a plain tag.
            Image(systemName: UIImage(systemName: icon) == nil ? "tag.fill" : icon).font(compact ? Font.fs(.caption2) : Font.fs(.caption))
            Text(label).font(compact ? Font.fs(.caption, .medium) : Font.fs(.subheadline)).lineLimit(1)
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 4 : 8)
        .background(Capsule().fill(selected ? Theme.stress.opacity(compact ? 0.16 : 0.2) : Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(compact ? Color.clear : selected ? Theme.stress.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1))
        .foregroundStyle(compact ? Theme.stress : selected ? Color.white : Theme.secondary)
    }
}

/// The day's journal on Today: its tags and note, or a prompt to log the day.
struct JournalCard: View {
    let date: String
    @EnvironmentObject var model: AppModel
    @State private var editing = false

    var body: some View {
        let entry = model.journal[date]
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Journal")
                Spacer()
                Button(entry == nil ? "Log day" : "Edit") { editing = true }
                    .font(Font.fs(.subheadline, .semibold))
                    .accessibilityIdentifier("journal-edit")
            }
            if let entry {
                let note = entry.note ?? ""
                if entry.tags.isEmpty && note.isEmpty {
                    Text("Nothing to note.").font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
                } else if !entry.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entry.tags, id: \.self) { TagChip(label: model.tagLabel($0), icon: model.tagIcon($0), compact: true) }
                    }
                }
                if !note.isEmpty {
                    Text(note).font(Font.fs(.footnote)).foregroundStyle(Theme.secondary)
                }
            } else {
                Text("Tag alcohol, late caffeine, a late meal and more. FitStats compares the night and morning after with your other logged days.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .sheet(isPresented: $editing) { JournalSheet(date: date).environmentObject(model) }
    }
}

struct JournalSheet: View {
    let date: String
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var added: [String] = []
    @State private var note = ""
    @State private var newTag = ""
    @State private var saving = false

    /// Built-in tags, then your own, then any left on this entry.
    private var allTags: [String] {
        var seen = Set<String>()
        let candidates = model.journalTags.map(\.id) + model.customTags + added + (model.journal[date]?.tags ?? [])
        return candidates.filter { seen.insert($0.lowercased()).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tag what you did \(date == model.today ? "today" : "on \(Format.shortDay(date))"). FitStats compares the night and morning after with your other logged days.")
                        .font(Font.fs(.footnote))
                        .foregroundStyle(Theme.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(allTags, id: \.self) { tag in
                            Button { toggle(tag) } label: {
                                TagChip(label: model.tagLabel(tag), icon: model.tagIcon(tag), selected: selected.contains(tag))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("tag-\(tag)")
                            .accessibilityAddTraits(selected.contains(tag) ? .isSelected : [])
                        }
                    }
                    HStack {
                        TextField("Add your own tag", text: $newTag)
                            .submitLabel(.done)
                            .onSubmit(addTag)
                        Button("Add", action: addTag).disabled(clean(newTag).isEmpty)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note").font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                        TextField("Optional: how you felt, what was different", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                    }
                    if model.journal[date] != nil {
                        Button("Remove this day's entry", role: .destructive) {
                            Task {
                                await model.clearJournal(date: date)
                                dismiss()
                            }
                        }
                        .font(Font.fs(.footnote))
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty && clean(note).isEmpty ? "Nothing to note" : "Save", action: save)
                        .disabled(saving)
                        .accessibilityIdentifier("journal-save")
                }
            }
        }
        .onAppear {
            let entry = model.journal[date]
            selected = Set(entry?.tags ?? [])
            note = entry?.note ?? ""
        }
    }

    private func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").joined(separator: " ")
    }

    private func toggle(_ tag: String) {
        if selected.contains(tag) { selected.remove(tag) } else { selected.insert(tag) }
    }

    private func addTag() {
        let tag = String(clean(newTag).prefix(30))
        guard !tag.isEmpty else { return }
        // A built-in tag typed by its name picks that tag.
        let existing = allTags.first { $0.lowercased() == tag.lowercased() || model.tagLabel($0).lowercased() == tag.lowercased() }
        if let existing {
            selected.insert(existing)
        } else {
            added.append(tag)
            selected.insert(tag)
        }
        newTag = ""
    }

    private func save() {
        saving = true
        let tags = allTags.filter(selected.contains)
        Task {
            if await model.saveJournal(date: date, tags: tags, note: note) {
                Haptics.success()
                dismiss()
            }
            saving = false
        }
    }
}

/// Insights: each tag's night and morning after, against the other logged days.
struct JournalImpactsCard: View {
    let impacts: [TagImpact]

    var body: some View {
        Card {
            SectionHeader(title: "Journal", subtitle: "The night and morning after tagged days, against your other logged days")
            if impacts.isEmpty {
                Text("Log your days on Today. Once a tag has 3 logged days with it and 3 without, its effect shows here.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(impacts) { impact in
                    TagImpactRow(impact: impact)
                    if impact.id != impacts.last?.id { Divider().overlay(Theme.track) }
                }
            }
            Text("Green or red differences are larger than your usual night-to-night variation (Welch's t of 2 or more); grey ones are within it. A pattern in your data, not proof of cause.")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        }
    }
}

private struct TagImpactRow: View {
    let impact: TagImpact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(impact.label).font(Font.fs(.subheadline, .semibold))
                Spacer()
                Text(impact.days == 1 ? "1 day" : "\(impact.days) days").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
            }
            if impact.effects.isEmpty {
                Text("Needs 3 logged days with this tag and 3 without.").font(Font.fs(.caption)).foregroundStyle(Theme.tertiary)
            } else {
                HStack(spacing: 8) {
                    Spacer()
                    Text("tagged vs other")
                    Text("change").frame(minWidth: 58, alignment: .trailing)
                }
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
                .accessibilityHidden(true)
                ForEach(impact.effects) { EffectRow(effect: $0) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EffectRow: View {
    let effect: TagEffect

    var body: some View {
        if let def = MetricCatalog.def(effect.metric) {
            HStack(spacing: 8) {
                Text(def.shortLabel).font(Font.fs(.caption)).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(def.formatted(effect.with)) vs \(def.formatted(effect.without))")
                    .font(Font.fs(.caption).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                Text(diffText(def))
                    .font(Font.fs(.caption, .semibold).monospacedDigit())
                    .foregroundStyle(color(def))
                    .frame(minWidth: 58, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(def.label): \(def.formatted(effect.with)) after tagged days, \(def.formatted(effect.without)) after others, \(effect.clear ? "clear" : "not clear") difference")
        }
    }

    /// The difference rounded as it is shown, so a rounded zero reads "±0", never "+0" or "−0".
    private func shownDiff(_ def: MetricDef) -> Double {
        if case .duration = def.format { return effect.diff.rounded() }
        let scale = pow(10, Double(def.decimals))
        return (effect.diff * scale).rounded() / scale
    }

    private func diffText(_ def: MetricDef) -> String {
        let d = shownDiff(def)
        let sign = d > 0 ? "+" : d < 0 ? "−" : "±"
        let size = abs(d)
        // A difference between two percentages is in percentage points.
        if def.format == .percent || def.unit == "%" {
            return sign + Format.number(size, decimals: def.decimals) + " pts"
        }
        switch def.format {
        case .duration: return sign + Format.duration(size)
        default: return sign + def.formatted(size)
        }
    }

    /// Colour only clear differences; the rest stay grey.
    private func color(_ def: MetricDef) -> Color {
        let d = shownDiff(def)
        guard effect.clear, let better = def.better, d != 0 else { return Theme.tertiary }
        return (better == .higher) == (d > 0) ? Theme.recoveryGreen : Theme.recoveryRed
    }
}
