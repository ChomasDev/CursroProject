import Foundation

// MARK: - WebSocket wire protocol (JSON text frames). See WEBSOCKET_PROTOCOL.md.

/// Client → server: first (and only) message sent after the socket opens.
struct RoastWireRequest: Codable, Equatable, Sendable {
    var type: String = "roast_request"
    let sessionId: String
    let conversationId: String?
    let prompt: String
    let tokenCount: Int
    let model: String?
    let user: String

    init(_ request: RoastRequest) {
        sessionId = request.sessionId
        conversationId = request.conversationId
        prompt = request.prompt
        tokenCount = request.tokenCount
        model = request.model
        user = request.user
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case conversationId = "conversation_id"
        case prompt
        case tokenCount = "token_count"
        case model
        case user
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encode(conversationId, forKey: .conversationId) // explicit null
        try c.encode(prompt, forKey: .prompt)
        try c.encode(tokenCount, forKey: .tokenCount)
        try c.encode(model, forKey: .model)
        try c.encode(user, forKey: .user)
    }

    func jsonString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Server → client stats payload (snake_case).
struct RoastWireStats: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let name: String
        let tokens: Int
        let isMe: Bool?

        enum CodingKeys: String, CodingKey {
            case name, tokens
            case isMe = "is_me"
        }
    }

    var similarCount: Int?
    var tokenCount: Int?
    var secondsSpent: Double?
    var promptsPerDay: Int?
    var hourlyWage: Double?
    var euroPerDay: Double?
    var euroPerMonth: Double?
    var leaderboardRank: Int?
    var leaderboardTotal: Int?
    var peopleAbove: Int?
    var leaderboard: [Entry]?
    var badges: [String]?

    enum CodingKeys: String, CodingKey {
        case similarCount = "similar_count"
        case tokenCount = "token_count"
        case secondsSpent = "seconds_spent"
        case promptsPerDay = "prompts_per_day"
        case hourlyWage = "hourly_wage"
        case euroPerDay = "euro_per_day"
        case euroPerMonth = "euro_per_month"
        case leaderboardRank = "leaderboard_rank"
        case leaderboardTotal = "leaderboard_total"
        case peopleAbove = "people_above"
        case leaderboard
        case badges
    }

    init(_ s: RoastStats) {
        similarCount = s.similarCount
        tokenCount = s.tokenCount
        secondsSpent = s.secondsSpent
        promptsPerDay = s.promptsPerDay
        hourlyWage = s.hourlyWage
        euroPerDay = s.euroPerDay
        euroPerMonth = s.euroPerMonth
        leaderboardRank = s.leaderboardRank
        leaderboardTotal = s.leaderboardTotal
        peopleAbove = s.peopleAbove
        leaderboard = s.leaderboard.map { Entry(name: $0.name, tokens: $0.tokens, isMe: $0.isMe) }
        badges = s.badges
    }

    /// Tolerant mapping: missing fields default to 0 / empty.
    var model: RoastStats {
        let rank = leaderboardRank ?? 0
        return RoastStats(
            similarCount: similarCount ?? 0,
            tokenCount: tokenCount ?? 0,
            secondsSpent: secondsSpent ?? 0,
            promptsPerDay: promptsPerDay ?? 0,
            hourlyWage: hourlyWage ?? 0,
            euroPerDay: euroPerDay ?? 0,
            euroPerMonth: euroPerMonth ?? 0,
            leaderboardRank: rank,
            leaderboardTotal: leaderboardTotal ?? 0,
            peopleAbove: peopleAbove ?? max(0, rank - 1),
            leaderboard: (leaderboard ?? []).map {
                LeaderboardEntry(name: $0.name, tokens: $0.tokens, isMe: $0.isMe ?? false)
            },
            badges: badges ?? []
        )
    }
}

/// Server → client message. Decoding never throws for unknown `type`s: they become `.unknown`.
enum RoastWireMessage: Equatable, Sendable {
    case stats(RoastWireStats)
    case delta(section: RoastSection, text: String)
    case phrase(section: RoastSection, text: String)
    case done
    case error(message: String)
    case unknown(type: String)

    private struct Envelope: Decodable {
        let type: String
        let stats: RoastWireStats?
        let section: String?
        let text: String?
        let message: String?
    }

    /// Returns nil when the frame is not valid JSON / has no `type`.
    static func decode(_ data: Data) -> RoastWireMessage? {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch env.type {
        case "stats":
            guard let s = env.stats else { return .unknown(type: env.type) }
            return .stats(s)
        case "delta", "phrase":
            guard let raw = env.section, let section = RoastSection(rawValue: raw),
                  let text = env.text else { return .unknown(type: env.type) }
            return env.type == "delta" ? .delta(section: section, text: text)
                                       : .phrase(section: section, text: text)
        case "done":
            return .done
        case "error":
            return .error(message: env.message ?? env.text ?? "errore sconosciuto")
        default:
            return .unknown(type: env.type)
        }
    }

    static func decode(_ string: String) -> RoastWireMessage? {
        decode(Data(string.utf8))
    }

    /// Mapping to the app-level update. `.error` and `.unknown` map to nil.
    var update: RoastUpdate? {
        switch self {
        case .stats(let s): return .stats(s.model)
        case .delta(let section, let text): return .delta(section: section, text: text)
        case .phrase(let section, let text): return .phrase(section: section, text: text)
        case .done: return .done
        case .error, .unknown: return nil
        }
    }
}

enum RoastServiceError: Error, LocalizedError, Sendable {
    case server(String)
    case timeout
    case closed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .server(let m): return "Backend error: \(m)"
        case .timeout: return "Roast backend timed out"
        case .closed: return "WebSocket closed before the roast was done"
        case .invalidURL: return "Invalid WebSocket URL"
        }
    }
}
