import SwiftUI

/// Dia-style text: words appear one by one (blur → sharp, fade, slight rise), centered.
/// Words containing digits (48.213, 3,62€, 1323°) get the accent gradient.
struct WordRevealText: View {
    let text: String
    var font: Font = .system(size: 48, weight: .semibold)
    var color: Color = .white
    var highlightNumbers = true
    var alignment: HorizontalAlignment = .center
    var wordSpacing: CGFloat = 12
    var lineSpacing: CGFloat = 6
    /// Seconds between words.
    var perWord: Double = 0.14
    /// Delay before the first word.
    var startDelay: Double = 0

    private var words: [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }

    var body: some View {
        FlowLayout(spacing: wordSpacing, lineSpacing: lineSpacing, alignment: alignment) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                RevealWord(
                    text: word,
                    font: font,
                    style: highlightNumbers && word.contains(where: \.isNumber)
                        ? AnyShapeStyle(AA.accent) : AnyShapeStyle(color),
                    delay: startDelay + Double(index) * perWord
                )
            }
        }
    }
}

private struct RevealWord: View {
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
            .blur(radius: shown ? 0 : 12)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8).delay(delay)) { shown = true }
            }
    }
}

/// Wrapping layout with per-line alignment.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 4
    var alignment: HorizontalAlignment = .leading

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(maxWidth: CGFloat, subviews: Subviews) -> ([Line], [CGSize]) {
        var lines: [Line] = [Line()]
        var sizes: [CGSize] = []
        for (i, sub) in subviews.enumerated() {
            let size = sub.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            sizes.append(size)
            let extra = lines[lines.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if !lines[lines.count - 1].indices.isEmpty, lines[lines.count - 1].width + extra > maxWidth {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            line.width += line.indices.isEmpty ? size.width : spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(i)
            lines[lines.count - 1] = line
        }
        return (lines, sizes)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let (lines, _) = lines(maxWidth: maxWidth, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        let widest = lines.map(\.width).max() ?? 0
        let width = (proposal.width.map { $0.isFinite ? $0 : widest }) ?? widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (lines, sizes) = lines(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - line.width) / 2
            case .trailing: x = bounds.maxX - line.width
            default: x = bounds.minX
            }
            for i in line.indices {
                let size = sizes[i]
                subviews[i].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}
