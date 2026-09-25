import Foundation
import SwiftUI

/// One Dia-style "slide": an optional small label and one phrase.
struct Beat: Identifiable, Equatable {
    enum Style: Equatable {
        case statement, quote, code, punchline, waiting
    }

    let id = UUID()
    var label: String?
    var labelIsCaps = true
    var text: String
    var style: Style = .statement

    var wordCount: Int { max(1, text.split(separator: " ").count) }

    /// Seconds between two words.
    var perWord: Double {
        switch style {
        case .statement: return 0.14
        case .quote: return min(0.14, 2.4 / Double(wordCount))
        case .code: return 0.07
        case .punchline: return 0.22
        case .waiting: return 0.12
        }
    }

    /// Delay before the first word (the label fades in first).
    var startDelay: Double { label == nil ? 0.15 : 0.55 }
}

/// Plays the roast as a local queue of beats, at its own calm pace, regardless of how fast the
/// stream arrives. When the queue is drained and both the roast and the agent are done, it moves
/// the model to `.summary`.
@MainActor
@Observable
final class BeatPlayer {
    /// Global pace multiplier (> 1 = faster). `AIANDO_PACE` env var, for testing.
    static let pace: Double = {
        if let s = ProcessInfo.processInfo.environment["AIANDO_PACE"], let v = Double(s), v > 0 { return v }
        return 1
    }()

    private(set) var current: Beat?
    /// True while waiting for more roast text (shows a pulsing "…").
    private(set) var showPlaceholder = false

    private var consumedSections = 0
    private var consumedItems = 0
    private var shownError = false

    func run(model: OverlayModel) async {
        current = nil
        showPlaceholder = false
        consumedSections = 0
        consumedItems = 0
        shownError = false
        guard let session = model.session else { return }

        for beat in Self.introBeats(prompt: session.prompt) {
            await play(beat)
            if Task.isCancelled { return }
        }

        var idleSince: Date?
        while !Task.isCancelled {
            guard model.phase == .intro || model.phase == .roasting else { return }

            if let beats = nextBeats(model) {
                idleSince = nil
                if showPlaceholder { withAnimation(.easeOut(duration: 0.5)) { showPlaceholder = false } }
                for beat in beats {
                    await play(beat)
                    if Task.isCancelled { return }
                }
                continue
            }

            let roastDrained = model.roastFinished && consumedSections >= model.revealed.count
            if roastDrained {
                if showPlaceholder { withAnimation(.easeOut(duration: 0.5)) { showPlaceholder = false } }
                if let err = model.errorMessage, !shownError {
                    shownError = true
                    await play(Beat(label: "⚠️  Ops", text: err, style: .statement))
                    continue
                }
                if model.agentFinished {
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.9)) {
                        model.phase = .summary
                    }
                    return
                }
                await playWaiting(model)
                continue
            }

            // Waiting for the stream: gentle placeholder after a short grace period.
            if idleSince == nil { idleSince = Date() }
            if let since = idleSince, Date().timeIntervalSince(since) > 0.6, !showPlaceholder {
                withAnimation(.easeInOut(duration: 0.6)) { showPlaceholder = true }
            }
            await sleep(0.2, scaled: false)
        }
    }

    // MARK: - Queue

    private func nextBeats(_ model: OverlayModel) -> [Beat]? {
        guard consumedSections < model.revealed.count else { return nil }
        let section = model.revealed[consumedSections]
        let complete = consumedSections < model.revealed.count - 1 || model.roastFinished
        let label = "\(section.emoji)  \(section.title)"

        if section == .invecePotevi {
            let items = model.items[section] ?? []
            if consumedItems < items.count {
                let item = items[consumedItems]
                consumedItems += 1
                return [Beat(label: label, text: item, style: .statement)]
            }
            guard complete else { return nil }
            consumedSections += 1
            consumedItems = 0
            if items.isEmpty, let text = model.texts[section], !text.isEmpty {
                return Self.sentences(text).map { Beat(label: label, text: $0) }
            }
            return []
        }

        guard complete else { return nil }
        consumedSections += 1
        let text = (model.texts[section] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        switch section {
        case .promptMigliore:
            return [Beat(label: label, text: text, style: .code)]
        case .commentoPromptMigliore:
            let parts = Self.sentences(text)
            return parts.enumerated().map { i, s in
                Beat(label: label, text: s, style: i == parts.count - 1 ? .punchline : .statement)
            }
        default:
            return Self.sentences(text).map { Beat(label: label, text: $0) }
        }
    }

    // MARK: - Playback

    private func play(_ beat: Beat) async {
        withAnimation(.easeOut(duration: 0.4)) { current = beat }
        let words = Double(beat.wordCount)
        let reveal = beat.startDelay + words * beat.perWord + 0.8
        let hold = min(6.5, 1.8 + 0.28 * words)
        await sleep(reveal + hold)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.9)) { current = nil }
        await sleep(1.0)
    }

    private func playWaiting(_ model: OverlayModel) async {
        let beat = Beat(
            label: nil,
            text: "L'AI sta ancora lavorando per te… e tu sei qui a guardare 💀",
            style: .waiting
        )
        withAnimation(.easeOut(duration: 0.4)) { current = beat }
        let started = Date()
        while !Task.isCancelled, !model.agentFinished,
              model.phase == .intro || model.phase == .roasting {
            await sleep(0.3, scaled: false)
        }
        // Let it be read at least once.
        let minShown = (beat.startDelay + Double(beat.wordCount) * beat.perWord + 2.5) / Self.pace
        let left = minShown - Date().timeIntervalSince(started)
        if left > 0 { await sleep(left, scaled: false) }
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.9)) { current = nil }
        await sleep(1.0)
    }

    private func sleep(_ seconds: Double, scaled: Bool = true) async {
        let s = scaled ? seconds / Self.pace : seconds
        try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000))
    }

    // MARK: - Text shaping

    static func introBeats(prompt: String) -> [Beat] {
        let words = prompt.replacingOccurrences(of: "\n", with: " ").split(separator: " ")
        var flat = words.prefix(20).joined(separator: " ")
        if words.count > 20 { flat += "…" }
        return [
            Beat(label: "Hai appena scritto…", labelIsCaps: false, text: "“\(flat)”", style: .quote),
            Beat(label: nil, text: "Aspetta. 💀", style: .punchline),
        ]
    }

    /// Splits into sentences, then merges short ones so each beat is ~9–24 words.
    static func sentences(_ text: String) -> [String] {
        var raw: [String] = []
        var cur = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            cur.append(c)
            if ".!?…".contains(c) {
                let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
                if next == " " || next == "\n" {
                    let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { raw.append(t) }
                    cur = ""
                }
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { raw.append(tail) }

        func wc(_ s: String) -> Int { s.split(separator: " ").count }
        var merged: [String] = []
        for s in raw {
            if let last = merged.last, wc(last) < 9, wc(last) + wc(s) <= 24 {
                merged[merged.count - 1] = last + " " + s
            } else {
                merged.append(s)
            }
        }
        if merged.count > 1, let last = merged.last, wc(last) < 5, wc(merged[merged.count - 2]) + wc(last) <= 28 {
            merged.removeLast()
            merged[merged.count - 1] += " " + last
        }
        return merged.isEmpty ? [text] : merged
    }
}
