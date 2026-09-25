import Charts
import SwiftUI

/// Final "Ai-Ando wrapped" dashboard.
struct SummaryView: View {
    let model: OverlayModel

    var body: some View {
        let stats = model.stats
        let summary = model.summary
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ai-Ando")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                    + Text(" wrapped")
                        .font(.system(size: 40, weight: .regular, design: .serif).italic())
                        .foregroundStyle(AA.hot)
                    Text("Ecco quanto hai lavorato tu (poco) e quanto ha lavorato l'AI (tanto).")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .staggered(0)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(
                        title: "Tempo Ai-Ando", value: summary.totalSeconds, format: { Fmt.seconds($0) },
                        caption: "l'AI ha sgobbato, tu no", gradient: AA.cool
                    ).staggered(1)
                    StatTile(
                        title: "Tool usati", value: Double(summary.toolCount), format: { Fmt.int($0) },
                        caption: toolCaption(summary), gradient: LinearGradient(
                            colors: [AA.mint, AA.cyan], startPoint: .leading, endPoint: .trailing)
                    ).staggered(2)
                    StatTile(
                        title: "Rubati al capo", value: stats?.euroPerDay, format: { Fmt.euro($0) },
                        caption: stats.map { "al giorno · \(Fmt.euro($0.euroPerMonth)) al mese" } ?? "in attesa dei numeri",
                        gradient: AA.hot
                    ).staggered(3)
                    StatTile(
                        title: "Classifica", value: stats.map { Double($0.leaderboardRank) },
                        format: { "#" + Fmt.int($0) },
                        caption: stats.map { "su \(Fmt.int(Double($0.leaderboardTotal)))" } ?? "in attesa dei numeri",
                        gradient: LinearGradient(colors: [AA.orange, AA.pink], startPoint: .leading, endPoint: .trailing)
                    ).staggered(4)
                }

                TimeSplitCard(summary: summary)
                    .staggered(5)

                if let stats, !stats.leaderboard.isEmpty {
                    LeaderboardCard(entries: stats.leaderboard, rank: stats.leaderboardRank)
                        .staggered(6)
                }

                Button {
                    model.dismiss()
                } label: {
                    Text("Chiudi")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AA.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.cancelAction)
                .staggered(7)
                .padding(.top, 4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
            .padding(.bottom, 22)
        }
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.03),
                    .init(color: .black, location: 0.97),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private func toolCaption(_ s: SessionSummary) -> String {
        if let top = s.toolUsage.max(by: { $0.value < $1.value }) {
            return s.failedToolCount > 0 ? "top: \(top.key) · \(s.failedToolCount) falliti" : "top: \(top.key)"
        }
        return s.failedToolCount > 0 ? "\(s.failedToolCount) falliti" : "manco un tool, pigro"
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

private struct StatTile: View {
    let title: String
    let value: Double?
    let format: (Double) -> String
    let caption: String
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.55))
            Group {
                if let value {
                    CountingNumber(value: value, format: format, duration: 1.4)
                } else {
                    Text("—")
                }
            }
            .font(AA.rounded(30, .heavy))
            .foregroundStyle(gradient)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(caption)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .glassCard(radius: 18)
    }
}

private struct TimeSlice: Identifiable {
    let id: String
    let seconds: Double
    let color: Color
}

private struct TimeSplitCard: View {
    let summary: SessionSummary
    @State private var appeared = false

    private var slices: [TimeSlice] {
        [
            TimeSlice(id: "Pensa", seconds: summary.thinkingSeconds, color: AA.violet),
            TimeSlice(id: "Tool", seconds: summary.toolSeconds, color: AA.cyan),
            TimeSlice(id: "Risponde", seconds: summary.respondingSeconds, color: AA.pink),
        ]
    }

    var body: some View {
        let total = slices.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(emoji: "⏱️", title: "Dove è finito il tempo")
            HStack(spacing: 22) {
                ZStack {
                    if total > 0 {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Secondi", slice.seconds),
                                innerRadius: .ratio(0.64),
                                angularInset: 2.5
                            )
                            .cornerRadius(5)
                            .foregroundStyle(slice.color.gradient)
                        }
                        .chartLegend(.hidden)
                    } else {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 18)
                    }
                    VStack(spacing: 0) {
                        Text(Fmt.seconds(summary.totalSeconds > 0 ? summary.totalSeconds : total))
                            .font(AA.rounded(20, .heavy))
                            .foregroundStyle(.white)
                        Text("totale")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(appeared ? 0 : -90))
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(slices) { slice in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(slice.color)
                                .frame(width: 10, height: 10)
                            Text(slice.id)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer(minLength: 4)
                            Text(total > 0 ? "\(Int((slice.seconds / total * 100).rounded()))%" : "–")
                                .font(AA.rounded(14, .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                    }
                    Text("\(summary.thoughtCount) pensieri · \(summary.toolCount) tool · \(Fmt.int(Double(summary.responseCharacters))) caratteri")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: AA.violet)
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.75).delay(0.55)) { appeared = true }
        }
    }
}

private struct LeaderboardCard: View {
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

    var body: some View {
        let rows = self.rows
        let maxTokens = Double(rows.map(\.tokens).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(emoji: "🏆", title: "Classifica Ai-Ando")
            Chart(rows) { entry in
                BarMark(
                    x: .value("Token", Double(entry.tokens) * progress),
                    y: .value("Nome", entry.isMe ? "Tu (#\(rank))" : entry.name),
                    height: .ratio(0.62)
                )
                .cornerRadius(7)
                .foregroundStyle(
                    entry.isMe
                        ? AnyShapeStyle(LinearGradient(colors: [AA.pink, AA.orange], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.22))
                )
                .annotation(position: .trailing, spacing: 6) {
                    Text(Fmt.int(Double(entry.tokens)))
                        .font(AA.rounded(11, .semibold))
                        .foregroundStyle(entry.isMe ? AnyShapeStyle(AA.orange) : AnyShapeStyle(Color.white.opacity(0.55)))
                        .opacity(progress)
                }
            }
            .chartXScale(domain: 0...(maxTokens * 1.22))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.system(size: 12, weight: name.hasPrefix("Tu") ? .bold : .medium))
                                .foregroundStyle(name.hasPrefix("Tu") ? Color.white : Color.white.opacity(0.65))
                        }
                    }
                }
            }
            .frame(height: CGFloat(rows.count) * 34)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: AA.orange)
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.8)) { progress = 1 }
        }
    }
}

private struct CardHeader: View {
    let emoji: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(emoji).font(.system(size: 15))
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}
