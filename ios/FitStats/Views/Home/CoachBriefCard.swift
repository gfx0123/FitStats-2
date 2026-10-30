import SwiftUI

/// Home: today's coach briefing (`CoachStore.brief`), written on request by the server, which
/// holds the Claude API key and keeps one briefing per day. Shows the finished briefing (first few
/// lines, expandable), the text while it streams in, or a button to write it. Nothing here is
/// computed from health data: the text is the coach's own, shown as written, with the same look as
/// BriefingCard on the Coach tab. A briefing from another day is never shown as today's.
struct CoachBriefCard: View {
    let date: String
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var coach: CoachStore
    @State private var expanded = false

    /// Lines of a finished briefing shown before "Show more".
    private static let collapsedLines = 4

    var body: some View {
        Card {
            header
            if date != model.today {
                Text("The coach writes a briefing for today only.")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            } else if coach.isBriefing {
                streaming
            } else if let brief = todaysBrief {
                briefView(brief)
            } else {
                writePrompt
            }
            if let error = coach.briefError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.recoveryYellow)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-brief-card")
        .task(id: date) { await loadIfNeeded() }
        .onChange(of: coach.isBriefing) { _, writing in
            // A briefing written from here stays fully open once it's done.
            if writing { expanded = true }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            SectionHeader(title: "Coach briefing", subtitle: "From your AI coach, not medical advice")
            Spacer(minLength: 8)
            if date == model.today && todaysBrief != nil && !coach.isBriefing {
                Button { coach.generateBrief() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Font.fs(.footnote, .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(coach.isConfigured ? Theme.sleep : Theme.tertiary)
                .disabled(!coach.isConfigured)
                .accessibilityLabel("Write a new briefing")
            }
        }
    }

    @ViewBuilder private var streaming: some View {
        if coach.briefStreaming.isEmpty {
            HStack(spacing: 8) {
                TypingDots()
                Text("Reading your night and your trends…")
                    .font(Font.fs(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Writing your briefing")
        } else {
            CoachMarkdown(text: coach.briefStreaming, linesAsParagraphs: true)
                .font(Font.fs(.subheadline))
            TypingDots()
        }
    }

    @ViewBuilder private func briefView(_ brief: CoachBrief) -> some View {
        let lines = Self.contentLines(brief.text)
        let collapsible = lines.count > Self.collapsedLines
        let shown = (collapsible && !expanded) ? Array(lines.prefix(Self.collapsedLines)) : lines
        CoachMarkdown(text: shown.joined(separator: "\n"), linesAsParagraphs: true)
            .font(Font.fs(.subheadline))
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(writtenText(brief))
                .font(Font.fs(.caption2))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if collapsible {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(Font.fs(.caption, .semibold))
                .foregroundStyle(Theme.sleep)
                .accessibilityHint(expanded ? "Shows only the first lines of the briefing" : "Shows the whole briefing")
            }
        }
    }

    @ViewBuilder private var writePrompt: some View {
        Text("A short read on your recovery, what to do today and when to sleep tonight.")
            .font(Font.fs(.footnote))
            .foregroundStyle(Theme.secondary)
        Button { coach.generateBrief() } label: {
            Label("Write today's briefing", systemImage: "sparkles")
                .font(Font.fs(.subheadline, .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.sleep.opacity(coach.isConfigured ? 0.22 : 0.08)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(coach.isConfigured ? Theme.sleep : Theme.tertiary)
        .disabled(!coach.isConfigured)
        .accessibilityIdentifier("coach-brief-write")
        if !coach.isConfigured {
            setupNote
        }
    }

    /// Why the button is off: still checking, the server can't be reached, or no Claude key yet.
    @ViewBuilder private var setupNote: some View {
        if coach.status != nil {
            Label("The coach needs a Claude API key, added in Supabase (Edge Functions → Secrets). See Settings → Coach.", systemImage: "key.fill")
                .font(Font.fs(.caption))
                .foregroundStyle(Theme.tertiary)
        } else if coach.error != nil {
            HStack(spacing: 8) {
                Text("Couldn't reach the coach.")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 8)
                Button("Try again") { Task { await coach.refresh() } }
                    .buttonStyle(.plain)
                    .font(Font.fs(.caption, .semibold))
                    .foregroundStyle(Theme.sleep)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.secondary)
                Text("Checking the coach…")
                    .font(Font.fs(.caption))
                    .foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: data

    /// The stored briefing, only when it was written for this day.
    private var todaysBrief: CoachBrief? {
        guard let brief = coach.brief, brief.date == date else { return nil }
        return brief
    }

    private func writtenText(_ brief: CoachBrief) -> String {
        let byModel = coach.label(for: brief.model).map { " · \($0)" } ?? ""
        return "Written \(Format.relative(brief.createdAt))\(byModel)"
    }

    /// Non-blank lines. With `linesAsParagraphs` every line is its own block and blank lines only
    /// separate blocks, so a prefix of these renders exactly like the start of the full briefing.
    private static func contentLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The coach status and briefing load on the Coach tab; fetch them here when Home is first.
    @MainActor private func loadIfNeeded() async {
        guard date == model.today, !coach.isBriefing else { return }
        let stale = coach.brief.map { $0.date != date } ?? false
        if coach.status == nil || stale {
            await coach.refresh()
        }
    }
}
