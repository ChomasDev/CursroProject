import AppKit
import Charts
import SwiftUI

/// Final wrapped, printed like a thermal receipt that rises from the bottom.
struct SummaryView: View {
    let model: OverlayModel
    @State private var risen = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { model.dismiss() }
                .ignoresSafeArea()

            SummaryCard(model: model)
                .offset(y: risen ? 0 : 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.86).delay(0.05)) { risen = true }
        }
    }
}

private enum ReceiptPaper {
    static let color = Color(red: 0.97, green: 0.94, blue: 0.86)
}

private struct ReceiptShape: Shape {
    var tooth: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
        var x = rect.maxX
        var down = true
        while x > rect.minX + 0.5 {
            x = max(rect.minX, x - tooth)
            let y = down ? rect.maxY : rect.maxY - tooth
            path.addLine(to: CGPoint(x: x, y: y))
            down.toggle()
        }
        path.closeSubpath()
        return path
    }
}

private struct ReceiptRule: View {
    var body: some View {
        Line()
            .stroke(AA.ink.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .frame(height: 1)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct SummaryCard: View {
    let model: OverlayModel
    @State private var copied = false

    var body: some View {
        let stats = model.stats
        let summary = model.summary
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 4) {
                Text("AI-ANDO")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(AA.ink)
                Text("SCONTRINO DEL PROMPT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(AA.ink.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .staggered(0, step: 0.22, base: 0.35)
            ReceiptRule().staggered(0, step: 0.22, base: 0.4)

            // Three big numbers
            HStack(alignment: .top, spacing: 0) {
                BigStat(
                    value: summary.totalSeconds, format: { Fmt.seconds($0) },
                    caption: "di Ai-Ando"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .staggered(1, step: 0.22, base: 0.45)
                BigStat(
                    value: stats?.euroPerDay, format: { Fmt.euro($0) },
                    caption: stats.map { "rubati al giorno · \(Fmt.euro($0.euroPerMonth))/mese" } ?? "rubati al giorno"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .staggered(2, step: 0.22, base: 0.45)
                BigStat(
                    value: stats.map { Double($0.leaderboardRank) }, format: { "#" + Fmt.int($0) },
                    caption: stats.map { "su \(Fmt.int(Double($0.leaderboardTotal))) in classifica" } ?? "in classifica"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .staggered(3, step: 0.22, base: 0.45)
            }

            if let badges = stats?.badges, !badges.isEmpty {
                BadgeRow(badges: badges)
                    .staggered(4, step: 0.22, base: 0.45)
            }

            ReceiptRule().staggered(4, step: 0.22, base: 0.45)

            if let stats, !stats.leaderboard.isEmpty {
                Leaderboard(entries: stats.leaderboard, rank: stats.leaderboardRank)
                    .staggered(4, step: 0.22, base: 0.45)
            }

            TimeSplitBar(summary: summary)
                .staggered(5, step: 0.22, base: 0.45)

            Text("GRAZIE E ARRIVEDERCI")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(AA.ink)
                .frame(maxWidth: .infinity)
                .staggered(6, step: 0.22, base: 0.45)
            ReceiptRule().staggered(6, step: 0.22, base: 0.5)

            HStack {
                Text("Esc per chiudere")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AA.ink.opacity(0.4))
                Spacer()
                if let better = model.texts[.promptMigliore], !better.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(better, forType: .string)
                        copied = true
                    } label: {
                        Text(copied ? "Copiato" : "Copia prompt")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AA.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().strokeBorder(AA.ink.opacity(0.35), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .focusable(false)
                }
                Button {
                    model.dismiss()
                } label: {
                    Text("Chiudi")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(ReceiptPaper.color)
                        .padding(.horizontal, 22)
                        .frame(height: 34)
                        .background(Capsule().fill(AA.ink))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .focusable(false)
            }
            .staggered(6, step: 0.22, base: 0.45)
        }
        .padding(.init(top: 28, leading: 32, bottom: 36, trailing: 32))
        .frame(width: 640)
        .background(ReceiptPaper.color)
        .clipShape(ReceiptShape())
        .shadow(color: .black.opacity(0.28), radius: 28, y: 16)
        .contentShape(Rectangle())
        .onTapGesture {} // swallow taps so the backdrop doesn't dismiss
    }
}

private struct BadgeRow: View {
    let badges: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(badges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AA.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(AA.accent))
            }
            Spacer(minLength: 0)
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct BigStat: View {
    let value: Double?
    let format: (Double) -> String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let value {
                    CountingNumber(value: value, format: format, duration: 1.6)
                } else {
                    Text("—")
                }
            }
            .font(AA.rounded(40, .bold))
            .foregroundStyle(AA.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AA.ink.opacity(0.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 10)
        }
    }
}

private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2.2)
            .foregroundStyle(AA.ink.opacity(0.45))
    }
}

private struct Leaderboard: View {
    let entries: [LeaderboardEntry]
    let rank: Int
    @State private var progress: Double = 0

    private var rows: [LeaderboardEntry] {
        let sorted = entries.sorted { $0.tokens > $1.tokens }
        var top = Array(sorted.prefix(5))
        if !top.contains(where: { $0.isMe }), let me = sorted.first(where: { $0.isMe }) {
            top = Array(top.prefix(4)) + [me]
        }
        return top
    }

    private static let palette: [Color] = [AA.violet, AA.cyan, AA.pink, AA.orange]

    private func color(for entry: LeaderboardEntry, at index: Int) -> Color {
        entry.isMe ? AA.mint : Self.palette[index % Self.palette.count]
    }

    var body: some View {
        let rows = self.rows
        let maxTokens = Double(rows.map(\.tokens).max() ?? 1)
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Classifica Ai-Ando · token")
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, entry in
                    row(entry, position: entry.isMe ? rank : index + 1,
                        color: color(for: entry, at: index), maxTokens: maxTokens)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.6, dampingFraction: 0.85).delay(1.5)) { progress = 1 }
        }
    }

    private func row(_ entry: LeaderboardEntry, position: Int, color: Color, maxTokens: Double) -> some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(AA.rounded(12, .bold))
                .foregroundStyle(entry.isMe ? AA.ink : .white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(color))
            Text(entry.isMe ? "Tu" : entry.name)
                .font(.system(size: 13, weight: entry.isMe ? .bold : .medium))
                .foregroundStyle(entry.isMe ? AA.ink : AA.ink.opacity(0.7))
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * CGFloat(Double(entry.tokens) / maxTokens) * progress))
                }
            }
            .frame(height: 10)
            Text(Fmt.int(Double(entry.tokens)))
                .font(AA.rounded(12, .semibold))
                .monospacedDigit()
                .foregroundStyle(entry.isMe ? AA.ink : AA.ink.opacity(0.55))
                .frame(minWidth: 56, alignment: .trailing)
                .opacity(progress)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(entry.isMe ? AA.mint.opacity(0.22) : AA.ink.opacity(0.04))
        )
    }
}

private struct TimeSplitBar: View {
    let summary: SessionSummary
    @State private var progress: CGFloat = 0

    private var slices: [(String, Double, Color)] {
        [
            ("pensa", summary.thinkingSeconds, AA.violet),
            ("usa tool", summary.toolSeconds, AA.cyan),
            ("risponde", summary.respondingSeconds, AA.pink),
        ]
    }

    var body: some View {
        let total = slices.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Dove è finito il tempo dell'AI")
            GeometryReader { geo in
                HStack(spacing: 3) {
                    if total > 0 {
                        ForEach(slices, id: \.0) { slice in
                            Capsule()
                                .fill(slice.2)
                                .frame(width: max(0, (geo.size.width - 6) * CGFloat(slice.1 / total) * progress))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(AA.ink.opacity(0.08)))
            }
            .frame(height: 8)
            HStack(spacing: 22) {
                ForEach(slices, id: \.0) { slice in
                    HStack(spacing: 7) {
                        Circle().fill(slice.2).frame(width: 7, height: 7)
                        Text(slice.0)
                            .foregroundStyle(AA.ink.opacity(0.6))
                        Text(total > 0 ? "\(Int((slice.1 / total * 100).rounded()))%" : "–")
                            .foregroundStyle(AA.ink)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Text("\(summary.toolCount) tool · \(summary.thoughtCount) pensieri")
                    .foregroundStyle(AA.ink.opacity(0.4))
            }
            .font(.system(size: 12, weight: .medium))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).delay(2.0)) { progress = 1 }
        }
    }
}
