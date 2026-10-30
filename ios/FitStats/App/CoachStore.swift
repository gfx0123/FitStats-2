import Foundation
import UIKit

/// Coach conversations, the daily briefing and model/usage info. Replies stream in
/// from the server, which holds the Claude API key and looks up your data.
@MainActor
final class CoachStore: ObservableObject {
    @Published private(set) var status: CoachStatus?
    @Published private(set) var threads: [CoachThread] = []
    @Published private(set) var threadId: String?
    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var streamingText = ""
    @Published private(set) var toolStatus: String?
    @Published private(set) var isSending = false
    @Published private(set) var failedQuestion: String?
    @Published var error: String?
    /// The coach you talk to (Coach → switch coach); kept on the phone.
    @Published var persona: CoachPersona = .saved {
        didSet { UserDefaults.standard.set(persona.rawValue, forKey: CoachPersona.storageKey) }
    }

    @Published private(set) var weekly: CoachWeekly?
    @Published private(set) var weeklyStreaming = ""
    @Published private(set) var isWritingWeekly = false
    @Published var weeklyError: String?
    @Published private(set) var brief: CoachBrief?
    @Published private(set) var briefStreaming = ""
    @Published private(set) var isBriefing = false
    @Published var briefError: String?

    var apiProvider: @MainActor () -> APIClient? = { nil }
    var onUnauthorized: @MainActor () -> Void = {}
    /// A tool changed their data (event "changed"): "training", "journal", "settings" or "all".
    var onDataChanged: @MainActor (String) -> Void = { _ in }

    private var fixtureDir: URL?
    private var fixtureMessages: [CoachMessage] = []
    private var sendTask: Task<Void, Never>?
    /// The current question and briefing: a stream that ends after a newer one started (or after
    /// a new conversation) leaves the newer one's state alone.
    private var sendGeneration = 0
    private var briefGeneration = 0
    /// The screenshots and files of the question that failed, sent again with "Try again".
    private var failedImages: [CoachImageUpload] = []
    private var failedFiles: [CoachFileUpload] = []
    /// The files of the question being answered (failedFiles if it fails).
    private var sentFiles: [CoachFileUpload] = []

    var isConfigured: Bool { status?.configured ?? false }

    /// "12h" or "24h", sent with every request so the coach writes times the way the phone does.
    static var clock: String { Format.uses24HourClock ? "24h" : "12h" }

    var modelLabel: String? { label(for: status?.model) }

    func label(for modelId: String?) -> String? {
        guard let modelId else { return nil }
        return status?.models.first { $0.id == modelId }?.label ?? modelId
    }

    // MARK: loading

    /// Screenshot fixtures (see supabase/tests/make-fixtures.ts).
    func loadFixtures(from dir: URL) {
        fixtureDir = dir
        func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        status = load(CoachStatus.self, "coach-status.json")
        threads = load(CoachThreadsResponse.self, "coach-threads.json")?.threads ?? []
        brief = load(CoachBriefResponse.self, "coach-brief.json")?.brief
        weekly = load(CoachWeeklyResponse.self, "coach-weekly.json")?.weekly
        fixtureMessages = load(CoachThreadResponse.self, "coach-thread.json")?.messages ?? []
    }

    func refresh() async {
        guard fixtureDir == nil, let api = apiProvider() else { return }
        do {
            status = try await api.fetch(CoachStatus.self, "coach_status").0
            threads = try await api.fetch(CoachThreadsResponse.self, "coach_threads").0.threads
            brief = try await api.fetch(CoachBriefResponse.self, "coach_brief").0.brief
            // Servers before 1.11.0 don't have it.
            if let w = try? await api.fetch(CoachWeeklyResponse.self, "coach_weekly").0 { weekly = w.weekly }
        } catch {
            handle(error)
        }
    }

    private func refreshStatusAndThreads() async {
        guard fixtureDir == nil, let api = apiProvider() else { return }
        if let s = try? await api.fetch(CoachStatus.self, "coach_status").0 { status = s }
        if let t = try? await api.fetch(CoachThreadsResponse.self, "coach_threads").0 { threads = t.threads }
    }

    func reset() {
        newChat()
        status = nil
        threads = []
        brief = nil
        briefStreaming = ""
        briefError = nil
    }

    // MARK: conversations

    func newChat() {
        sendTask?.cancel()
        sendTask = nil
        sendGeneration += 1
        threadId = nil
        messages = []
        streamingText = ""
        toolStatus = nil
        isSending = false
        failedQuestion = nil
        error = nil
    }

    func open(_ thread: CoachThread) async {
        newChat()
        threadId = thread.id
        if fixtureDir != nil {
            messages = fixtureMessages
            return
        }
        guard let api = apiProvider() else { return }
        do {
            messages = try await api.fetch(CoachThreadResponse.self, "coach_thread", query: ["id": thread.id]).0.messages
        } catch {
            handle(error)
        }
    }

    func delete(_ thread: CoachThread) async {
        threads.removeAll { $0.id == thread.id }
        if threadId == thread.id { newChat() }
        guard fixtureDir == nil, let api = apiProvider() else { return }
        do {
            _ = try await api.post("coach_delete", query: ["id": thread.id])
        } catch {
            handle(error)
        }
    }

    func send(_ text: String, images: [CoachImageUpload] = [], files: [CoachFileUpload] = []) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !images.isEmpty || !files.isEmpty, !isSending else { return }
        error = nil
        failedQuestion = nil
        failedImages = []
        failedFiles = []
        sentFiles = files
        let attachments = files.map(\.attachment) + images.map(\.attachment)
        messages.append(CoachMessage(id: "local-\(UUID().uuidString)", role: "user", content: question, createdAt: nil,
                                     attachments: attachments.isEmpty ? nil : attachments))
        streamingText = ""
        toolStatus = nil
        isSending = true
        sendGeneration += 1
        let generation = sendGeneration
        let thread = threadId
        sendTask = Task { await stream(question, images: images, files: files, thread: thread, generation: generation) }
    }

    /// The answer is in (or failed): the composer opens again and no "Thinking…" row is left.
    private func endSending(_ generation: Int) {
        guard generation == sendGeneration else { return }
        isSending = false
        toolStatus = nil
    }

    func retry() {
        guard let question = failedQuestion else { return }
        let images = failedImages
        let files = failedFiles
        if let i = messages.lastIndex(where: { $0.isUser && $0.content == question }) {
            messages.removeSubrange(i...)
        }
        failedQuestion = nil
        send(question, images: images, files: files)
    }

    private func stream(_ question: String, images: [CoachImageUpload], files: [CoachFileUpload], thread: String?, generation: Int) async {
        defer { endSending(generation) }
        if fixtureDir != nil { return await fixtureAnswer(generation: generation) }
        guard let api = apiProvider() else { return }
        // A little time to finish if the app is left mid-answer; past that the server finishes
        // the answer on its own and it is read from the thread when the app is back.
        let background = BackgroundTime("coach-answer")
        defer { background.end() }
        var body: [String: Any] = ["message": question, "persona": persona.rawValue, "clock": Self.clock]
        if let thread { body["thread_id"] = thread }
        if !images.isEmpty {
            body["images"] = images.map { ["media_type": "image/jpeg", "data": $0.data, "thumb": $0.thumb] }
        }
        if !files.isEmpty {
            body["files"] = files.map { ["name": $0.name, "text": $0.text] }
        }
        var started: (thread: String, question: String)?
        var finished = false
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            for try await event in api.events("coach", body: data) {
                switch event.type {
                case "started":
                    if let t = event.threadId, let q = event.messageId {
                        started = (thread: t, question: q)
                        threadId = t
                    }
                case "status":
                    toolStatus = event.text
                case "text":
                    streamingText += event.text ?? ""
                    toolStatus = nil
                case "changed":
                    onDataChanged(event.what ?? "all")
                case "done":
                    finished = true
                    let reply = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    messages.append(CoachMessage(id: event.messageId ?? UUID().uuidString, role: "assistant", content: reply, createdAt: nil,
                                                 persona: event.persona ?? persona.rawValue))
                    streamingText = ""
                    if let id = event.threadId { threadId = id }
                    // In the same update as the reply, so nothing else shows up for a moment
                    // while the conversation list refreshes below.
                    endSending(generation)
                case "error":
                    throw CoachFailure(message: event.message ?? "The coach couldn't answer.")
                default:
                    break
                }
            }
            if finished {
                await refreshStatusAndThreads()
            } else if let started {
                // The connection ended before the answer did: the server is still on it.
                await pickUp(started, question: question, images: images, generation: generation)
            }
        } catch let e as CoachFailure {
            // The server said the answer failed; it kept nothing, so it can be sent again.
            fail(question, images: images, e)
        } catch {
            if Task.isCancelled {
                // A new conversation was started: drop this one.
                streamingText = ""
            } else if let started, !error.isUnauthorized {
                // Backgrounded or the network dropped: the server finishes and saves the answer.
                await pickUp(started, question: question, images: images, generation: generation)
            } else {
                fail(question, images: images, error)
            }
        }
    }

    /// Screenshots (no server): a sample answer written out word by word after a moment of
    /// thinking, so the coach's thinking and talking and the end of an answer can be seen.
    private func fixtureAnswer(generation: Int) async {
        try? await Task.sleep(for: .seconds(1.5))
        let sample = "This is a sample answer for the screenshots. With your server connected, \(persona.name) reads your recovery, sleep, " +
            "training and journal and answers here.\n\n- It cites your own numbers and baselines\n- It can save routines to your Training tab"
        for word in sample.split(separator: " ") {
            guard generation == sendGeneration, !Task.isCancelled else { return }
            streamingText += (streamingText.isEmpty ? "" : " ") + word
            try? await Task.sleep(for: .milliseconds(70))
        }
        guard generation == sendGeneration else { return }
        messages.append(CoachMessage(id: "sample-\(UUID().uuidString)", role: "assistant", content: streamingText, createdAt: nil,
                                     persona: persona.rawValue))
        streamingText = ""
        endSending(generation)
    }

    /// Waits for an answer the server is finishing after the connection was lost, reading the
    /// thread every few seconds (for up to three minutes, also after the app was in the
    /// background). The answer replaces the partial text; a failed one can be sent again.
    private func pickUp(_ started: (thread: String, question: String), question: String, images: [CoachImageUpload],
                        generation: Int) async {
        toolStatus = "Finishing your answer…"
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, !Task.isCancelled {
            guard let api = apiProvider() else { break }
            do {
                let thread = try await api.fetch(CoachThreadResponse.self, "coach_thread", query: ["id": started.thread]).0
                guard let q = thread.messages.firstIndex(where: { $0.id == started.question }) else {
                    // The question was taken back: the answer failed.
                    return fail(question, images: images, CoachFailure(message: "The coach couldn't finish that answer."))
                }
                if thread.messages[q...].contains(where: { !$0.isUser }) {
                    guard generation == sendGeneration else { return }
                    messages = thread.messages
                    streamingText = ""
                    endSending(generation)
                    await refreshStatusAndThreads()
                    return
                }
            } catch APIError.server(404, _) {
                return fail(question, images: images, CoachFailure(message: "The coach couldn't finish that answer."))
            } catch {
                // Offline for now, or still waking up from the background: try again.
            }
            try? await Task.sleep(for: .seconds(2.5))
        }
        if !Task.isCancelled {
            fail(question, images: images, CoachFailure(message: "The answer is taking too long. Open the conversation again in a minute, or try again."))
        }
    }

    private func fail(_ question: String, images: [CoachImageUpload], _ error: Error) {
        // Keep whatever arrived, marked as cut off; the question can be sent again.
        if !streamingText.isEmpty {
            messages.append(CoachMessage(id: UUID().uuidString, role: "assistant", content: streamingText + "\n\n_(interrupted)_", createdAt: nil,
                                         persona: persona.rawValue))
            streamingText = ""
        }
        failedQuestion = question
        failedImages = images
        failedFiles = sentFiles
        handle(error.isCancellation ? CoachFailure(message: "The connection was interrupted. Try again.") : error)
    }

    // MARK: briefing

    var hasTodaysBrief: Bool { brief != nil }

    func generateBrief() {
        guard !isBriefing, fixtureDir == nil, let api = apiProvider() else { return }
        isBriefing = true
        briefStreaming = ""
        briefError = nil
        briefGeneration += 1
        let generation = briefGeneration
        let before = brief?.createdAt
        Task {
            defer { endBriefing(generation) }
            let background = BackgroundTime("coach-brief")
            defer { background.end() }
            var finished = false
            do {
                let request = (try? JSONSerialization.data(withJSONObject: ["kind": "brief", "clock": Self.clock])) ?? Data(#"{"kind":"brief"}"#.utf8)
                for try await event in api.events("coach", body: request) {
                    switch event.type {
                    case "text":
                        briefStreaming += event.text ?? ""
                    case "done":
                        finished = true
                        // The briefing replaces the streamed text in the same update, so the
                        // card never shows the "Reading your night…" placeholder in between.
                        if let b = event.brief { brief = b }
                        endBriefing(generation)
                    case "error":
                        throw CoachFailure(message: event.message ?? "The briefing couldn't be written.")
                    default:
                        break
                    }
                }
                if finished {
                    await refreshStatusAndThreads()
                } else if !(await pickUpBrief(newerThan: before, generation: generation)) {
                    briefError = "The connection was interrupted. Try again."
                }
            } catch let e as CoachFailure {
                briefError = e.localizedDescription
            } catch {
                if error.isUnauthorized {
                    onUnauthorized()
                } else if !(await pickUpBrief(newerThan: before, generation: generation)) {
                    briefError = error.isCancellation ? "The connection was interrupted. Try again." : error.localizedDescription
                }
            }
        }
    }

    private func endBriefing(_ generation: Int) {
        guard generation == briefGeneration else { return }
        isBriefing = false
        briefStreaming = ""
    }

    /// The server finishes a briefing the app stopped listening to; read it once it's saved.
    /// What already streamed in stays on screen until then.
    private func pickUpBrief(newerThan before: String?, generation: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if let api = apiProvider(), let b = try? await api.fetch(CoachBriefResponse.self, "coach_brief").0.brief, b.createdAt != before {
                if generation == briefGeneration {
                    brief = b
                    endBriefing(generation)
                }
                return true
            }
            try? await Task.sleep(for: .seconds(2.5))
        }
        return false
    }

    // MARK: weekly summary

    /// Writes this week's summary now (the server also writes it on Sunday evening).
    func generateWeekly() {
        guard !isWritingWeekly, fixtureDir == nil, let api = apiProvider() else { return }
        isWritingWeekly = true
        weeklyStreaming = ""
        weeklyError = nil
        let before = weekly?.createdAt
        Task {
            let background = BackgroundTime("coach-weekly")
            defer {
                background.end()
                isWritingWeekly = false
                weeklyStreaming = ""
            }
            do {
                let request = try JSONSerialization.data(withJSONObject: ["kind": "weekly", "clock": Self.clock])
                for try await event in api.events("coach", body: request) {
                    switch event.type {
                    case "text":
                        weeklyStreaming += event.text ?? ""
                    case "done":
                        if let w = event.weekly { weekly = w }
                        isWritingWeekly = false
                        weeklyStreaming = ""
                    case "error":
                        throw CoachFailure(message: event.message ?? "The weekly summary couldn't be written.")
                    default:
                        break
                    }
                }
            } catch let e as CoachFailure {
                weeklyError = e.localizedDescription
            } catch {
                if error.isUnauthorized {
                    onUnauthorized()
                    return
                }
                // The server finishes it anyway; read it once it's saved.
                let deadline = Date().addingTimeInterval(120)
                while Date() < deadline {
                    if let w = try? await api.fetch(CoachWeeklyResponse.self, "coach_weekly").0.weekly, w.createdAt != before {
                        weekly = w
                        return
                    }
                    try? await Task.sleep(for: .seconds(2.5))
                }
                weeklyError = "The connection was interrupted. Try again."
            }
        }
    }

    // MARK: settings

    func setModel(_ id: String) async {
        guard fixtureDir == nil, let api = apiProvider(), id != status?.model else { return }
        do {
            let data = try JSONEncoder().encode(["coach_model": id])
            _ = try await api.post("settings", body: data)
            await refreshStatusAndThreads()
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if error.isCancellation { return }
        if case APIError.unauthorized = error {
            onUnauthorized()
        } else {
            self.error = error.localizedDescription
        }
    }
}

/// Extra time from iOS to finish a request after the app is left (about 30 seconds). Ends
/// itself when that time runs out, as iOS requires.
final class BackgroundTime: @unchecked Sendable {
    private var id: UIBackgroundTaskIdentifier = .invalid

    @MainActor
    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    @MainActor
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
