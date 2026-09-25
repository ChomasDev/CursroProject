import Foundation

/// Feeds the model a fake session so the UI can be demoed without Cursor/backend (`--demo`).
@MainActor
enum UIDemo {
    private static var current: Task<Void, Never>?

    /// Plays: reset → intro → roasting (stats, deltas, phrases, agent activity) → agentFinished → summary.
    /// `speed` > 1 makes it faster (e.g. 2 = twice as fast). `loop` replays forever.
    static func run(model: OverlayModel, speed: Double = 1, loop: Bool = false) {
        current?.cancel()
        current = Task { @MainActor in
            repeat {
                await play(model: model, speed: max(0.1, speed))
                if loop { await sleep(6, speed) }
            } while loop && !Task.isCancelled
        }
    }

    static func stop() {
        current?.cancel()
        current = nil
    }

    // MARK: - Script

    private static let prompt = "ciao potresti per favore sistemare questo bug che non va il login grazie mille"

    private static let script: [(RoastSection, String)] = [
        (.cloni, "No vabbè 💀 questa frase (o quasi) l'hanno già scritta altre 48.213 persone. Originalità di un panino dell'Autogrill."),
        (.funFact, "Hai detto 'per favore' E 'grazie mille' a un'AI ma non le hai detto QUALE bug. Cambiando una parola era la lettera d'amore di un personaggio secondario di Harry Potter. Fidati."),
        (.soldiGratis, "Bhe ipotizziamo che fai 60 prompt così al giorno: ti stai prendendo 3,62€ al giorno a gratis mentre l'AI sgobba. L'AI ti paga Netflix e tu manco la ringrazi. Ah no, la ringrazi pure."),
    ]

    private static let items = [
        "Bere mezzo spritz (il mezzo buono, quello col ghiaccio) 🍹",
        "Fumare 1/20 di sigaretta, cioè annusarla",
        "Guardare 2 TikTok e dimenticarli entrambi",
        "Fare 7 squat. Non li avresti fatti comunque",
    ]

    private static let tail: [(RoastSection, String)] = [
        (.classifica, "Bhe coglione come sei sei solo 1323° su 8741, ci sono 1322 persone che stanno Ai-Ando più di te. Impegnati di più a non impegnarti."),
        (.promptMigliore, "Il login fallisce: [errore]. Atteso: [comportamento]. Trova la causa in `auth/` e proponi il fix minimo."),
        (.commentoPromptMigliore, "Bhe coglione avresti potuto scriverla così. E sembravi pure uno che sa programmare. 💀"),
    ]

    private static let activities = [
        "Sta pensando…",
        "Legge auth/LoginView.swift",
        "Cerca \"login\" nel progetto",
        "Legge auth/SessionStore.swift",
        "Sta pensando…",
        "Modifica auth/SessionStore.swift",
        "Esegue swift build",
        "Scrive la risposta…",
    ]

    private static func play(model: OverlayModel, speed: Double) async {
        let session = PromptSession(
            id: UUID().uuidString, conversationId: "demo", prompt: prompt, startedAt: Date(), model: "claude-4.5-sonnet"
        )
        model.reset(for: session)
        model.activity = "Sta pensando…"
        await sleep(3.4, speed)
        guard !Task.isCancelled else { return }

        model.phase = .roasting
        await sleep(0.8, speed)

        model.apply(.stats(RoastStats(
            similarCount: 48213, tokenCount: 19, secondsSpent: 14, promptsPerDay: 60, hourlyWage: 15.5,
            euroPerDay: 3.62, euroPerMonth: 79.64, leaderboardRank: 1323, leaderboardTotal: 8741,
            peopleAbove: 1322,
            leaderboard: [
                LeaderboardEntry(name: "giulia.dev", tokens: 912_400, isMe: false),
                LeaderboardEntry(name: "marco_vibes", tokens: 804_120, isMe: false),
                LeaderboardEntry(name: "ale.codes", tokens: 655_900, isMe: false),
                LeaderboardEntry(name: "fede", tokens: 512_300, isMe: false),
                LeaderboardEntry(name: "Tu", tokens: 388_750, isMe: true),
            ]
        )))

        var activityIndex = 0
        func tickActivity() {
            activityIndex = (activityIndex + 1) % activities.count
            model.activity = activities[activityIndex]
            model.summary.toolCount = min(6, activityIndex)
        }

        for (section, text) in script {
            await stream(section, text, into: model, speed: speed)
            tickActivity()
            await sleep(0.5, speed)
        }

        for item in items {
            model.apply(.phrase(section: .invecePotevi, text: item))
            await sleep(0.55, speed)
        }
        tickActivity()

        for (section, text) in tail {
            if section == .promptMigliore {
                model.apply(.phrase(section: section, text: text))
                await sleep(1.2, speed)
            } else {
                await stream(section, text, into: model, speed: speed)
            }
            tickActivity()
            await sleep(0.4, speed)
        }
        model.apply(.done)
        guard !Task.isCancelled else { return }

        let total = Date().timeIntervalSince(session.startedAt)
        model.summary = SessionSummary(
            totalSeconds: total, thinkingSeconds: total * 0.34, toolSeconds: total * 0.46,
            respondingSeconds: total * 0.20, thoughtCount: 5, toolCount: 6, failedToolCount: 1,
            toolUsage: ["read_file": 3, "grep": 1, "edit_file": 1, "run_terminal_cmd": 1],
            responseCharacters: 1834
        )
        model.agentFinished = true
        model.activity = ""
        await sleep(2.2, speed)
        guard !Task.isCancelled else { return }
        model.phase = .summary
    }

    /// Streams text in 1–3 word chunks, like a token stream.
    private static func stream(_ section: RoastSection, _ text: String, into model: OverlayModel, speed: Double) async {
        let words = text.split(separator: " ").map(String.init)
        var i = 0
        while i < words.count {
            guard !Task.isCancelled else { return }
            let n = Int.random(in: 1...3)
            let chunk = words[i..<min(words.count, i + n)].joined(separator: " ")
            model.apply(.delta(section: section, text: (i == 0 ? "" : " ") + chunk))
            i += n
            await sleep(Double.random(in: 0.08...0.18), speed)
        }
    }

    private static func sleep(_ seconds: Double, _ speed: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds / speed * 1_000_000_000))
    }
}
