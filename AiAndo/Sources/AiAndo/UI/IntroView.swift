import SwiftUI

/// Dia-like intro: "Hai appena scritto…" → the prompt word by word → punchline.
struct IntroView: View {
    let prompt: String
    @State private var step = 0

    private var trimmedPrompt: String {
        let flat = prompt.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let words = flat.split(separator: " ")
        if words.count > 38 { return words.prefix(38).joined(separator: " ") + "…" }
        return flat
    }

    private var promptFontSize: CGFloat {
        switch trimmedPrompt.count {
        case ..<50: return 34
        case ..<110: return 28
        case ..<200: return 23
        default: return 19
        }
    }

    var body: some View {
        let words = max(1, trimmedPrompt.split(separator: " ").count)
        VStack(alignment: .leading, spacing: 26) {
            Spacer(minLength: 0)

            if step >= 1 {
                StreamingText(
                    text: "Hai appena scritto…",
                    font: .system(size: 17, weight: .medium),
                    style: AnyShapeStyle(Color.white.opacity(0.6)),
                    stagger: 0.09
                )
                .transition(.opacity)
            }

            if step >= 2 {
                HStack(alignment: .top, spacing: 14) {
                    Capsule()
                        .fill(AA.hot)
                        .frame(width: 3)
                        .opacity(0.9)
                    StreamingText(
                        text: "“\(trimmedPrompt)”",
                        font: .system(size: promptFontSize, weight: .regular, design: .serif).italic(),
                        style: AnyShapeStyle(Color.white.opacity(0.95)),
                        wordSpacing: promptFontSize * 0.24,
                        lineSpacing: promptFontSize * 0.18,
                        stagger: min(0.075, 1.1 / Double(words))
                    )
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }

            if step >= 3 {
                VStack(alignment: .leading, spacing: 4) {
                    StreamingText(
                        text: "Aspetta.",
                        font: .system(size: 44, weight: .semibold),
                        style: AnyShapeStyle(Color.white),
                        stagger: 0.1
                    )
                    StreamingText(
                        text: "Ci pensiamo noi. 💀",
                        font: .system(size: 44, weight: .semibold),
                        style: AnyShapeStyle(AA.hot),
                        wordSpacing: 11,
                        stagger: 0.14,
                        initialDelay: 0.35
                    )
                }
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            if step >= 3 {
                HStack(spacing: 10) {
                    PulsingDot(color: AA.cyan)
                    Text("Sto preparando il roast")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .staggered(0, base: 0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .task {
            let delays: [UInt64] = [150, 700, 700 + UInt64(min(1500, words * 75)) + 250]
            var elapsed: UInt64 = 0
            for (i, d) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: (d - elapsed) * 1_000_000)
                elapsed = d
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.4)) { step = i + 1 }
            }
        }
    }
}
