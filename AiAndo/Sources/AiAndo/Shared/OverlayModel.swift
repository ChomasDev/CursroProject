import Foundation
import Observation

/// Single source of truth for the overlay. The App layer mutates it, the UI layer only reads it
/// (plus calls `dismiss()`).
@MainActor
@Observable
final class OverlayModel {
    enum Phase: Equatable {
        /// Hidden.
        case idle
        /// Prompt captured, intro animation (Dia-style) plays.
        case intro
        /// Roast sections stream in while the agent is still working.
        case roasting
        /// Agent finished: final chart + summary.
        case summary
    }

    var phase: Phase = .idle
    var session: PromptSession?

    /// Sections in the order they were first revealed.
    var revealed: [RoastSection] = []
    /// Text per section (for `.invecePotevi` items are joined in `items`).
    var texts: [RoastSection: String] = [:]
    var items: [RoastSection: [String]] = [:]

    var stats: RoastStats?
    var summary = SessionSummary()

    /// Last thing the agent is doing ("Sta leggendo file...", tool name, ...), shown as a ticker.
    var activity: String = ""
    var agentFinished = false
    var roastFinished = false
    var errorMessage: String?

    /// TikTok caption while the pointer is thrashing on the overlay. Nil when calm.
    var dizzyLine: String?

    /// Set by the UI close button / ESC.
    var onDismiss: (() -> Void)?

    func reset(for session: PromptSession) {
        self.session = session
        phase = .intro
        revealed = []
        texts = [:]
        items = [:]
        stats = nil
        summary = SessionSummary()
        activity = ""
        agentFinished = false
        roastFinished = false
        errorMessage = nil
        dizzyLine = nil
    }

    func apply(_ update: RoastUpdate) {
        switch update {
        case .stats(let s):
            stats = s
        case .delta(let section, let text):
            reveal(section)
            texts[section, default: ""] += text
        case .phrase(let section, let text):
            reveal(section)
            if section == .invecePotevi {
                items[section, default: []].append(text)
            } else {
                texts[section] = text
            }
        case .done:
            roastFinished = true
        }
    }

    func dismiss() {
        phase = .idle
        onDismiss?()
    }

    private func reveal(_ section: RoastSection) {
        if !revealed.contains(section) { revealed.append(section) }
    }
}
