import Foundation

/// Consumes `SessionEvent`s of the current session and builds a `SessionSummary`.
/// Time between consecutive events is attributed to the phase of the event that ends it:
/// thought / toolStarted -> thinking, toolFinished -> tool (prefers durationMs),
/// response / stopped -> responding.
struct SessionTracker: Sendable {
    private(set) var session: PromptSession?
    private(set) var summary = SessionSummary()
    private(set) var isFinished = false
    private var lastMark: Date?

    init() {}

    /// Resets the tracker and starts tracking `session`.
    mutating func begin(_ session: PromptSession) {
        self = SessionTracker()
        self.session = session
        self.lastMark = session.startedAt
    }

    /// Feed an event. `.started` resets the tracker. Events before any `.started` are still counted.
    mutating func consume(_ event: SessionEvent, at now: Date = Date()) {
        if case .started(let s) = event {
            begin(s)
            return
        }
        if isFinished { return }
        let start = lastMark ?? now
        let gap = max(0, now.timeIntervalSince(start))
        if lastMark == nil, session == nil { lastMark = now }

        switch event {
        case .started:
            break
        case .thought:
            summary.thoughtCount += 1
            summary.thinkingSeconds += gap
        case .toolStarted(let name):
            summary.toolCount += 1
            summary.toolUsage[name, default: 0] += 1
            summary.thinkingSeconds += gap
        case .toolFinished(_, let ms, let failed):
            if failed { summary.failedToolCount += 1 }
            if let ms {
                let toolSecs = Double(ms) / 1000
                summary.toolSeconds += toolSecs
                summary.thinkingSeconds += max(0, gap - toolSecs)
            } else {
                summary.toolSeconds += gap
            }
        case .response(let text):
            summary.responseCharacters += text.count
            summary.respondingSeconds += gap
        case .stopped(let ms):
            summary.respondingSeconds += gap
            isFinished = true
            if let ms { summary.totalSeconds = Double(ms) / 1000 }
        }
        lastMark = now
        if !isFinished { summary.totalSeconds = elapsed(now: now) }
    }

    /// Live summary; `totalSeconds` is refreshed to `now` while the session is running.
    func summary(now: Date = Date()) -> SessionSummary {
        guard !isFinished else { return summary }
        var s = summary
        s.totalSeconds = elapsed(now: now)
        return s
    }

    private func elapsed(now: Date) -> Double {
        guard let start = session?.startedAt else { return summary.totalSeconds }
        return max(0, now.timeIntervalSince(start))
    }

    // MARK: - Ticker copy

    /// Italian Gen Z one-liner for the ticker. Returns nil for events that shouldn't change it.
    static func activity(for event: SessionEvent) -> String? {
        switch event {
        case .started:
            return "Ha ricevuto il tuo prompt... coraggio 💀"
        case .thought:
            return "Sta pensando più di te oggi 🧠"
        case .toolStarted(let name):
            return toolActivity(name)
        case .toolFinished(_, _, let failed):
            return failed ? "Ha fallito un comando. Succede anche ai migliori (non a te) 😬" : nil
        case .response:
            return "Sta scrivendo la risposta..."
        case .stopped:
            return "Ha finito. Tu invece? 🫠"
        }
    }

    static func toolActivity(_ raw: String) -> String {
        let n = raw.lowercased()
        func has(_ keys: String...) -> Bool { keys.contains { n.contains($0) } }
        if has("read", "view", "open") { return "Sta leggendo i tuoi file spaghetti 🍝" }
        if has("edit", "write", "replace", "patch", "create", "apply") {
            return "Sta riscrivendo il tuo codice (meglio di te)"
        }
        if has("delete", "remove") { return "Sta cancellando i tuoi errori (tanti) 🗑️" }
        if has("shell", "terminal", "bash", "command", "run") {
            return "Sta lanciando comandi a caso nel terminale"
        }
        if has("grep", "search", "find", "glob", "list", "ls") {
            return "Sta cercando qualcosa di sensato nel tuo repo 🔍"
        }
        if has("web", "fetch", "browser", "http") { return "Sta googlando al posto tuo 🌐" }
        if has("todo", "task") { return "Si sta organizzando la giornata, a differenza tua 📋" }
        if has("mcp") { return "Sta chiamando i rinforzi (MCP) 📞" }
        return "Sta usando \(raw), fidati 🤌"
    }
}
