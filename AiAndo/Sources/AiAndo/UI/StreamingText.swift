import SwiftUI

/// Text that animates in word by word (blur → sharp, fade, slight rise).
/// When `text` grows (streaming deltas), only the newly appended words animate.
struct StreamingText: View {
    let text: String
    var font: Font = .system(size: 18, weight: .medium)
    var style: AnyShapeStyle = AnyShapeStyle(Color.white)
    var wordSpacing: CGFloat = 5
    var lineSpacing: CGFloat = 4
    /// Delay between words that arrive in the same update.
    var stagger: Double = 0.035
    /// Initial delay before the first word.
    var initialDelay: Double = 0

    @State private var knownCount = 0

    private var words: [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    var body: some View {
        let words = self.words
        let known = knownCount
        FlowLayout(spacing: wordSpacing, lineSpacing: lineSpacing) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                AnimatedWord(
                    text: word,
                    font: font,
                    style: style,
                    delay: (known == 0 ? initialDelay : 0) + Double(max(0, index - known)) * stagger
                )
            }
        }
        .onChange(of: words.count) {
            // Let the new words pick up their delays first.
            let count = words.count
            DispatchQueue.main.async { knownCount = count }
        }
        .onAppear {
            let count = words.count
            DispatchQueue.main.async { knownCount = count }
        }
    }
}

private struct AnimatedWord: View {
    let text: String
    let font: Font
    let style: AnyShapeStyle
    let delay: Double
    @State private var shown = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(style)
            .fixedSize()
            .blur(radius: shown ? 0 : 7)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55).delay(delay)) { shown = true }
            }
    }
}

/// Simple wrapping layout (left aligned).
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        let width = proposal.width.map { $0.isFinite ? $0 : widest } ?? widest
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            sub.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: min(size.width, maxWidth), height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
