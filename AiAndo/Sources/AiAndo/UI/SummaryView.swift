import AppKit
import Charts
import SwiftUI

/// Final "Ai-Ando wrapped": one centered glass card that fits without scrolling.
struct SummaryView: View {
    let model: OverlayModel
    @State private var cardShown = false

    var body: some View {
        ZStack {
            // Slight dim; clicking outside the card closes the overlay.
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { model.dismiss() }
                .ignoresSafeArea()

            SummaryCard(model: model)
                .blur(radius: cardShown ? 0 : 20)
                .opacity(cardShown ? 1 : 0)
                .scaleEffect(cardShown ? 1 : 0.96)
                .offset(y: cardShown ? 0 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.15)) { cardShown = true }
        }
    }
}

private struct SummaryCard: View {
    let model: OverlayModel
    @State private var copied = false

    var body: some View {
        let stats = model.stats
        let summary = model.summary
        VStack(alignment: .leading, spacing: 26) {
            // Title
            VStack(alignment: .leading, spacing: 6) {
                (Text("Ai-Ando ")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
                 + Text("wrapped")
                    .font(.system(size: 38, weight: .regular, design: .serif).italic())
                    .foregroundColor(Color(red: 0.55, green: 1.0, blue: 0.78)))
                Text("Tu hai scritto un prompt. L'AI ha fatto il resto.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .staggered(0, step: 0.22, base: 0.45)

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

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                .staggered(4, step: 0.22, base: 0.45)

            if let stats, !stats.leaderboard.isEmpty {
                Leaderboard(entries: stats.leaderboard, rank: stats.leaderboardRank)
                    .staggered(4, step: 0.22, base: 0.45)
            }

            TimeSplitBar(summary: summary)
                .staggered(5, step: 0.22, base: 0.45)

            HStack {
                Text("Esc per chiudere")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
                if let better = model.texts[.promptMigliore], !better.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(better, forType: .string)
                        copied = true
                    } label: {
                        Text(copied ? "Copiato" : "Copia prompt")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .focusable(false)
                }
                Button {
                    model.dismiss()
                } label: {
                    Text("Chiudi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AA.ink)
                        .padding(.horizontal, 26)
                        .frame(height: 38)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .focusable(false)
            }
            .staggered(6, step: 0.22, base: 0.45)
        }
        .padding(34)
        .frame(width: 660)
        .background(BehindWindowBlur(radius: 28))
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
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
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
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
            .foregroundStyle(.white.opacity(0.45))
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

    private func name(_ e: LeaderboardEntry) -> String { e.isMe ? "tu · #\(rank)" : e.name }

    var body: some View {
        let rows = self.rows
        let maxTokens = Double(rows.map(\.tokens).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Classifica Ai-Ando · token")
            Chart(rows) { entry in
                BarMark(
                    x: .value("Token", Double(entry.tokens) * progress),
                    y: .value("Nome", name(entry)),
                    height: .fixed(12)
                )
                .cornerRadius(6)
                .foregroundStyle(
                    entry.isMe
                        ? AnyShapeStyle(AA.accent)
                        : AnyShapeStyle(Color.white.opacity(0.22))
                )
                .annotation(position: .trailing, spacing: 8) {
                    Text(Fmt.int(Double(entry.tokens)))
                        .font(AA.rounded(11.5, .semibold))
                        .foregroundStyle(entry.isMe ? Color.white : Color.white.opacity(0.5))
                        .opacity(progress)
                }
            }
            .chartXScale(domain: 0...(maxTokens * 1.2))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let n = value.as(String.self) {
                            Text(n)
                                .font(.system(size: 12.5, weight: n.hasPrefix("tu") ? .bold : .medium))
                                .foregroundStyle(n.hasPrefix("tu") ? Color.white : Color.white.opacity(0.6))
                        }
                    }
                }
            }
            .frame(height: CGFloat(rows.count) * 28)
        }
        .onAppear {
            withAnimation(.spring(response: 1.6, dampingFraction: 0.85).delay(1.5)) { progress = 1 }
        }
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
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .frame(height: 8)
            HStack(spacing: 22) {
                ForEach(slices, id: \.0) { slice in
                    HStack(spacing: 7) {
                        Circle().fill(slice.2).frame(width: 7, height: 7)
                        Text(slice.0)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(total > 0 ? "\(Int((slice.1 / total * 100).rounded()))%" : "–")
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }
                }
                Spacer()
                Text("\(summary.toolCount) tool · \(summary.thoughtCount) pensieri")
                    .foregroundStyle(.white.opacity(0.4))
            }
            .font(.system(size: 12, weight: .medium))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).delay(2.0)) { progress = 1 }
        }
    }
}
