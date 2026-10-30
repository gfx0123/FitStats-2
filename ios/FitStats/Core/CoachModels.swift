import Foundation

// Shapes returned by the coach routes of the `fitstats` Edge Function (lib/coach.ts).

struct CoachStatus: Codable {
    let configured: Bool
    let model: String
    let models: [CoachModelOption]
    let usage: CoachUsage?
    let dailyLimit: Int?

    enum CodingKeys: String, CodingKey {
        case configured, model, models, usage
        case dailyLimit = "daily_limit"
    }
}

struct CoachModelOption: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let note: String
}

struct CoachUsage: Codable {
    let requests: Int
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let costUsd: Double
    let month: String?
    let dayRequests: Int?

    enum CodingKeys: String, CodingKey {
        case requests, input, output, month
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case costUsd = "cost_usd"
        case dayRequests = "day_requests"
    }
}

struct CoachThread: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CoachThreadsResponse: Codable {
    let threads: [CoachThread]
}

struct CoachMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: String
    let content: String
    let createdAt: String?
    /// Which coach wrote a reply (CoachPersona's raw value); nil on questions and older replies.
    var persona: String? = nil
    /// Previews of the screenshots sent with a question.
    var attachments: [CoachAttachment]? = nil

    enum CodingKeys: String, CodingKey {
        case id, role, content, persona, attachments
        case createdAt = "created_at"
    }

    var isUser: Bool { role == "user" }

    var coach: CoachPersona? { persona.flatMap(CoachPersona.init(rawValue:)) }
}

/// A screenshot sent with a question: its small preview (base64), kept with the message.
/// A screenshot's preview, or an attached file by name (a workout CSV the server imported).
struct CoachAttachment: Codable, Equatable {
    let mediaType: String
    let thumb: String?
    var name: String? = nil

    enum CodingKeys: String, CodingKey {
        case thumb, name
        case mediaType = "media_type"
    }

    var isFile: Bool { name != nil }
}

struct CoachThreadResponse: Codable {
    let thread: CoachThread
    let messages: [CoachMessage]
}

struct CoachBrief: Codable, Equatable {
    let date: String
    let text: String
    let createdAt: String
    let model: String?

    enum CodingKeys: String, CodingKey {
        case date, text, model
        case createdAt = "created_at"
    }
}

struct CoachBriefResponse: Codable {
    let brief: CoachBrief?
}

/// The week's summary: written by the server on Sunday evening, or on request (lib/coach.ts).
struct CoachWeekly: Codable, Equatable {
    /// Monday of the week it is about.
    let week: String
    let date: String
    let text: String
    let createdAt: String
    let model: String?

    enum CodingKeys: String, CodingKey {
        case week, date, text, model
        case createdAt = "created_at"
    }
}

struct CoachWeeklyResponse: Codable {
    let weekly: CoachWeekly?
}

/// One server-sent event from the `coach` route: status, text, done or error.
struct CoachEvent: Decodable {
    let type: String
    let text: String?
    let message: String?
    let code: String?
    let threadId: String?
    let messageId: String?
    let brief: CoachBrief?
    let weekly: CoachWeekly?
    let usage: CoachUsage?
    let persona: String?
    /// "changed": which of their data a tool changed.
    let what: String?

    enum CodingKeys: String, CodingKey {
        case type, text, message, code, brief, weekly, usage, persona, what
        case threadId = "thread_id"
        case messageId = "message_id"
    }
}

struct CoachFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
