import Foundation

// MARK: - Shared contract between Input, Roast, UI and App layers.
// Do not change these types without updating every layer.

/// One Cursor prompt, from `beforeSubmitPrompt` until `stop`.
struct PromptSession: Identifiable, Equatable, Sendable {
    let id: String
    let conversationId: String?
    let prompt: String
    let startedAt: Date
    let model: String?
}

/// Events emitted by the Cursor hook log (`~/.cursor/prompt-mirror/events.jsonl`).
enum SessionEvent: Sendable {
    case started(PromptSession)
    case thought(String)
    case toolStarted(name: String)
    case toolFinished(name: String, durationMs: Int?, failed: Bool)
    case response(String)
    case stopped(durationMs: Int?)
}

/// Anything that can feed session events (file tailer, test fixture, ...).
protocol SessionEventSource: AnyObject {
    var events: AsyncStream<SessionEvent> { get }
    func start()
    func stop()
}

/// What happened during the agent turn; drives the final chart.
struct SessionSummary: Equatable, Sendable {
    var totalSeconds: Double = 0
    var thinkingSeconds: Double = 0
    var toolSeconds: Double = 0
    var respondingSeconds: Double = 0
    var thoughtCount: Int = 0
    var toolCount: Int = 0
    var failedToolCount: Int = 0
    var toolUsage: [String: Int] = [:]
    var responseCharacters: Int = 0
}

/// Sections of the roast, matching the JSON keys of `prompts/ai-ando-system-prompt.md`.
enum RoastSection: String, Codable, CaseIterable, Sendable {
    case cloni
    case funFact = "fun_fact_frase"
    case soldiGratis = "soldi_gratis"
    case invecePotevi = "invece_potevi"
    case classifica
    case promptMigliore = "prompt_migliore"
    case commentoPromptMigliore = "commento_prompt_migliore"

    var title: String {
        switch self {
        case .cloni: return "Originalità: zero"
        case .funFact: return "Fun fact"
        case .soldiGratis: return "Soldi a gratis"
        case .invecePotevi: return "Invece potevi"
        case .classifica: return "Classifica Ai-Ando"
        case .promptMigliore: return "Prompt migliore"
        case .commentoPromptMigliore: return "Il verdetto"
        }
    }

    var emoji: String {
        switch self {
        case .cloni: return "👯"
        case .funFact: return "🧙"
        case .soldiGratis: return "💸"
        case .invecePotevi: return "🍹"
        case .classifica: return "🏆"
        case .promptMigliore: return "✍️"
        case .commentoPromptMigliore: return "💀"
        }
    }
}

struct LeaderboardEntry: Codable, Equatable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let tokens: Int
    let isMe: Bool
}

/// Numbers computed by the backend (never by the LLM).
struct RoastStats: Codable, Equatable, Sendable {
    var similarCount: Int
    var tokenCount: Int
    var secondsSpent: Double
    var promptsPerDay: Int
    var hourlyWage: Double
    var euroPerDay: Double
    var euroPerMonth: Double
    var leaderboardRank: Int
    var leaderboardTotal: Int
    var peopleAbove: Int
    var leaderboard: [LeaderboardEntry]
}

/// Payload sent to the backend when a prompt starts.
struct RoastRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let conversationId: String?
    let prompt: String
    let tokenCount: Int
    let model: String?
}

/// Incremental updates from the backend, phrase by phrase.
enum RoastUpdate: Equatable, Sendable {
    /// Backend numbers; usually the first message.
    case stats(RoastStats)
    /// Streaming chunk appended to a section.
    case delta(section: RoastSection, text: String)
    /// A complete phrase for a section. For `.invecePotevi` each phrase is one list item;
    /// for the other sections it replaces the section text.
    case phrase(section: RoastSection, text: String)
    case done
}

protocol RoastService: Sendable {
    func roast(_ request: RoastRequest) -> AsyncThrowingStream<RoastUpdate, Error>
}

/// Rough token estimate (~4 chars per token) until the backend sends the real value.
func estimateTokens(_ text: String) -> Int {
    max(1, Int((Double(text.count) / 4.0).rounded(.up)))
}
