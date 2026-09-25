import Foundation

/// Generates a plausible roast locally, with realistic streaming delays. No backend needed.
struct MockRoastService: RoastService {
    /// Delay range per streamed word, in seconds.
    var wordDelay: ClosedRange<Double> = 0.04...0.07
    /// Pause between sections.
    var sectionPause: Double = 0.6
    /// Delay before the first `.stats`.
    var initialDelay: Double = 0.35

    init() {}

    init(wordDelay: ClosedRange<Double>, sectionPause: Double, initialDelay: Double) {
        self.wordDelay = wordDelay
        self.sectionPause = sectionPause
        self.initialDelay = initialDelay
    }

    func roast(_ request: RoastRequest) -> AsyncThrowingStream<RoastUpdate, Error> {
        let config = self
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stats = MockRoastGenerator.stats(for: request)
                    try await Self.sleep(config.initialDelay)
                    continuation.yield(.stats(stats))

                    let script = MockRoastGenerator.script(for: request, stats: stats)
                    for (index, item) in script.enumerated() {
                        if index > 0 { try await Self.sleep(config.sectionPause) }
                        switch item {
                        case .text(let section, let text):
                            let words = text.split(separator: " ", omittingEmptySubsequences: true)
                            for (i, word) in words.enumerated() {
                                try Task.checkCancellation()
                                continuation.yield(.delta(section: section, text: (i == 0 ? "" : " ") + word))
                                try await Self.sleep(Double.random(in: config.wordDelay))
                            }
                        case .phrases(let section, let phrases):
                            for phrase in phrases {
                                try Task.checkCancellation()
                                continuation.yield(.phrase(section: section, text: phrase))
                                try await Self.sleep(0.35)
                            }
                        }
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

// MARK: - Content generation

enum MockRoastGenerator {
    enum Item {
        case text(RoastSection, String)
        case phrases(RoastSection, [String])
    }

    static let fakeUsers = [
        "xX_vibecoder_Xx", "giulia.prompta", "bro_del_ctrl_c", "marco404", "lasagna.dev",
        "sofi_no_bug", "tommy_ai_ando", "chiarastackoverflow", "fede.copia.incolla",
        "ale_gpt_dipendente", "nonnacursor", "pietro.semicolon", "bea_refactor",
    ]

    // MARK: Stats

    static func stats(for request: RoastRequest) -> RoastStats {
        let tokens = request.tokenCount > 0 ? request.tokenCount : estimateTokens(request.prompt)
        // ~3.5 chars/sec typing + a bit of "thinking" time.
        let seconds = max(3, (Double(request.prompt.count) / 3.5 + Double.random(in: 2...6)).rounded())
        let perDay = Int.random(in: 40...80)
        let wage = 15.5
        let euroDay = round2(Double(perDay) * seconds / 3600 * wage)
        let euroMonth = round2(euroDay * 22)

        let total = Int.random(in: 2_000...12_000)
        let rank = Int.random(in: 1...min(total, 2_500))

        // Leaderboard: top of the list + the user's neighbourhood.
        var names = fakeUsers.shuffled()
        var entries: [LeaderboardEntry] = []
        if rank <= 7 {
            for r in 1...8 {
                let isMe = r == rank
                entries.append(LeaderboardEntry(name: isMe ? "tu" : names.removeFirst(),
                                                tokens: 0, isMe: isMe))
            }
        } else {
            for _ in 1...5 {
                entries.append(LeaderboardEntry(name: names.removeFirst(), tokens: 0, isMe: false))
            }
            entries.append(LeaderboardEntry(name: names.removeFirst(), tokens: 0, isMe: false)) // rank-1
            entries.append(LeaderboardEntry(name: "tu", tokens: 0, isMe: true))
            entries.append(LeaderboardEntry(name: names.removeFirst(), tokens: 0, isMe: false)) // rank+1
        }
        // Assign strictly decreasing tokens.
        let ranks: [Int] = rank <= 7 ? Array(1...8) : [1, 2, 3, 4, 5, rank - 1, rank, rank + 1]
        var last = Int.max
        entries = zip(entries, ranks).map { entry, r in
            var t = min(max(1, 900_000 / r) + Int.random(in: 0...300), last - 1)
            t = max(t, 1)
            last = t
            return LeaderboardEntry(name: entry.name, tokens: t, isMe: entry.isMe)
        }

        return RoastStats(
            similarCount: Int.random(in: 1...5_342_534),
            tokenCount: tokens,
            secondsSpent: seconds,
            promptsPerDay: perDay,
            hourlyWage: wage,
            euroPerDay: euroDay,
            euroPerMonth: euroMonth,
            leaderboardRank: rank,
            leaderboardTotal: total,
            peopleAbove: rank - 1,
            leaderboard: entries
        )
    }

    // MARK: Script

    static func script(for request: RoastRequest, stats s: RoastStats) -> [Item] {
        let better = betterPrompt(request.prompt)
        let saved = max(0, s.tokenCount - estimateTokens(better))
        return [
            .text(.cloni, cloni(s)),
            .text(.funFact, funFact(request.prompt)),
            .text(.soldiGratis, soldi(s)),
            .phrases(.invecePotevi, invecePotevi(seconds: s.secondsSpent)),
            .text(.classifica, classifica(s)),
            .text(.promptMigliore, better),
            .text(.commentoPromptMigliore, commento(saved: saved)),
        ]
    }

    static func cloni(_ s: RoastStats) -> String {
        let n = fmt(s.similarCount)
        if s.similarCount < 10 {
            return [
                "Oh, solo \(n) persone hanno scritto una roba simile. Quasi originale, quasi. Non montarti la testa.",
                "Ok bro, \(n) cloni soltanto. Per i tuoi standard è letteralmente arte contemporanea.",
            ].randomElement()!
        }
        return [
            "No vabbè 💀 questa frase (o quasi) l'hanno già scritta altre \(n) persone. Originalità di un panino dell'Autogrill.",
            "Raga \(n) persone hanno scritto sto prompt prima di te. Sei l'NPC numero \(fmt(s.similarCount + 1)).",
            "Bro, \(n) cloni hanno avuto la stessa idea geniale. Il copia-incolla umano esiste e sei tu.",
            "Sto morendo: \(n) persone, stesso prompt. Sei un trend di TikTok ma senza i like.",
        ].randomElement()!
    }

    static func funFact(_ prompt: String) -> String {
        let lower = prompt.lowercased()
        let words = prompt.split(whereSeparator: { $0.isWhitespace }).count
        var facts: [String] = []
        if lower.contains("per favore") || lower.contains("grazie") || lower.contains("please") {
            facts.append("Hai detto 'per favore' a un'AI ma non le hai detto cosa vuoi davvero. Quando arriverà la rivoluzione dei robot ti risparmieranno, contento?")
        }
        if lower.contains("ciao") {
            facts.append("Hai salutato l'AI con 'ciao' come se fosse tua zia su WhatsApp. Manca solo il buongiornissimo ☕.")
        }
        if prompt.count > 400 {
            facts.append("Questo prompt ha \(words) parole. È più lungo del tema di maturità che non hai mai finito.")
        }
        if prompt.count < 25 {
            facts.append("\(words) parole in tutto. Nemmeno i messaggi della tua ex erano così secchi.")
        }
        facts += [
            "Cambiando una parola era letteralmente il capitolo 3 di Harry Potter. Fidati, ho controllato (non ho controllato).",
            "Se lo leggi al contrario è il testo di una hit estiva del 2007. Non chiedermi quale.",
            "Questa frase ha la stessa energia di un vocale da 4 minuti che poteva essere un 'ok'.",
            "Fun fact: con queste parole un monaco tibetano ci ha scritto un haiku. Tu ci hai scritto un bug.",
        ]
        return facts.randomElement()!
    }

    static func soldi(_ s: RoastStats) -> String {
        let day = euro(s.euroPerDay), month = euro(s.euroPerMonth)
        return [
            "Bhe ipotizziamo che fai \(s.promptsPerDay) prompt così al giorno: con uno stipendio medio ti stai prendendo \(day)€ al giorno a gratis mentre l'AI sgobba. \(month)€ al mese. Il tuo capo ringrazia (lui non lo sa).",
            "\(s.promptsPerDay) prompt al giorno × stipendio medio = \(day)€ al giorno regalati a te stesso mentre l'AI lavora. \(month)€ al mese. Praticamente l'AI ti paga Netflix e tu manco la ringrazi.",
            "Facciamo due conti bro: \(s.promptsPerDay) prompt al giorno, \(day)€ al giorno di stipendio per guardare una barra che carica. \(month)€ al mese. Slay finanziario 💸",
        ].randomElement()!
    }

    static func invecePotevi(seconds: Double) -> [String] {
        let sec = max(1, seconds)
        let spritz = sec / 120            // uno spritz in ~2 minuti
        let sigarette = sec / 300         // una sigaretta in ~5 minuti
        let tiktok = max(1, Int(sec / 12))
        let squat = max(1, Int(sec / 2))
        let storie = max(1, Int(sec / 5))
        let reel = max(1, Int(sec / 20))

        var pool = [
            "Bere \(fraction(spritz)) di spritz (la parte buona, col ghiaccio)",
            "Fumare \(fraction(sigarette)) di sigaretta, cioè praticamente annusarla",
            "Guardare \(tiktok) TikTok e dimenticarli tutti",
            "Fare \(squat) squat. Non li avresti fatti comunque",
            "Scrollare \(storie) storie della ex. Red flag 🚩",
            "Mandare \(reel) reel al gruppo che nessuno aprirà",
            "Fissare il muro per \(Int(sec)) secondi, stesso output ma gratis",
        ]
        pool.shuffle()
        return Array(pool.prefix(Int.random(in: 3...4)))
    }

    static func classifica(_ s: RoastStats) -> String {
        if s.leaderboardRank == 1 {
            return [
                "Sei 1° su \(fmt(s.leaderboardTotal)). Il re dell'Ai-Ando 👑. Bro vai a toccare l'erba, sono preoccupato.",
                "PRIMO su \(fmt(s.leaderboardTotal)). Nessuno sta Ai-Ando più di te. Tua madre sarebbe fiera? No.",
            ].randomElement()!
        }
        let rank = fmt(s.leaderboardRank), total = fmt(s.leaderboardTotal), above = fmt(s.peopleAbove)
        return [
            "Bhe coglione come sei sei solo \(rank)° su \(total), ci sono \(above) persone che stanno Ai-Ando più di te. Impegnati di più a non impegnarti.",
            "\(rank)° posto su \(total). \(above) persone stanno Ai-Ando meglio di te. Anche nel non fare niente sei mediocre, patato.",
            "Classifica Ai-Ando: \(rank)°. Davanti a te \(above) geni del copia-incolla. Ma ci sei?",
        ].randomElement()!
    }

    static func commento(saved: Int) -> String {
        if saved <= 0 {
            return [
                "Ok raga oggi non posso insultarlo troppo, il prompt era già decente. Mi fai schifo lo stesso.",
                "Bhe coglione, è lunga uguale ma almeno ora l'AI capisce cosa vuoi. E sembri pure uno che sa programmare.",
            ].randomElement()!
        }
        return [
            "Bhe coglione avresti potuto scriverla così, risparmiavi \(saved) token e sembravi pure intelligente.",
            "No vabbè, \(saved) token buttati in convenevoli 💀 Scritta così l'AI sa cosa fare e tu sembri un senior.",
            "Ecco, così. \(saved) token in meno e zero 'per favore'. L'AI non è tua nonna, bro.",
        ].randomElement()!
    }

    // MARK: Prompt rewrite heuristic

    static func betterPrompt(_ prompt: String) -> String {
        var text = " " + prompt.replacingOccurrences(of: "\n", with: " ") + " "
        let fillers = [
            "ciao", "salve", "hey", "ehi", "per favore", "per piacere", "gentilmente", "grazie mille",
            "grazie", "potresti", "puoi", "riusciresti a", "mi potresti", "mi puoi", "vorrei che tu",
            "vorrei", "please", "could you", "can you", "thanks", "thank you", "ti prego", "se riesci",
            "un attimo", "per caso", "bro", "raga",
        ]
        for filler in fillers {
            let pattern = "(?i)(?<![\\p{L}])" + NSRegularExpression.escapedPattern(for: filler) + "(?![\\p{L}])[,!.]*"
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        if text.isEmpty { text = "[descrivi il task]" }
        let task = text.prefix(1).uppercased() + text.dropFirst()
        let ending = task.hasSuffix(".") || task.hasSuffix("?") ? "" : "."
        return "\(task)\(ending) Contesto: [file/linguaggio/framework]. Vincoli: [cosa non toccare]. Output atteso: [diff minimo + breve spiegazione]."
    }

    // MARK: Formatting helpers

    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func fmt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func euro(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "it_IT")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    /// Human fraction for small quantities ("1/20", "mezzo", "2").
    static func fraction(_ v: Double) -> String {
        if v >= 1.5 { return "\(Int(v.rounded()))" }
        if v >= 0.75 { return "1" }
        if v >= 0.4 { return "mezzo" }
        let d = max(2, Int((1 / max(v, 0.01)).rounded()))
        return "1/\(d)"
    }
}
