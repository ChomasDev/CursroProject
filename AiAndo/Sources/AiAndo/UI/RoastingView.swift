import SwiftUI

/// Vertical stream of glass cards, one per revealed roast section, plus the agent ticker.
struct RoastingView: View {
    let model: OverlayModel

    private var streamSignature: Int {
        model.texts.values.reduce(0) { $0 + $1.count }
            + model.items.values.reduce(0) { $0 + $1.count } * 1000
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let prompt = model.session?.prompt {
                        PromptEcho(prompt: prompt)
                            .staggered(0)
                    }

                    ForEach(Array(model.revealed.enumerated()), id: \.element) { index, section in
                        SectionCard(section: section, model: model, index: index)
                            .id(section)
                            .transition(.blurRise)
                    }

                    if model.revealed.isEmpty {
                        WaitingCard()
                            .transition(.blurRise)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 84)
                .animation(.spring(response: 0.65, dampingFraction: 0.82), value: model.revealed)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.035),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .onChange(of: model.revealed.count) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: streamSignature) {
                withAnimation(.easeOut(duration: 0.35)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .overlay(alignment: .bottom) {
            ActivityTicker(model: model)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - Pieces

private struct PromptEcho: View {
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IL TUO PROMPT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.45))
            Text("“\(prompt.replacingOccurrences(of: "\n", with: " "))”")
                .font(.system(size: 15, weight: .regular, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

private struct WaitingCard: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 12) {
            PulsingDot(color: AA.pink)
            Text("Sto giudicando il tuo prompt…")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
        .padding(18)
        .glassCard()
    }
}

struct SectionCard: View {
    let section: RoastSection
    let model: OverlayModel
    let index: Int

    private var text: String { model.texts[section] ?? "" }
    private var items: [String] { model.items[section] ?? [] }

    private var tint: Color {
        switch section {
        case .cloni: return AA.violet
        case .funFact: return AA.cyan
        case .soldiGratis: return AA.mint
        case .invecePotevi: return AA.orange
        case .classifica: return AA.orange
        case .promptMigliore: return AA.cyan
        case .commentoPromptMigliore: return AA.pink
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(section.emoji)
                    .font(.system(size: 20))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint.opacity(0.22)))
                    .overlay(Circle().strokeBorder(tint.opacity(0.45), lineWidth: 1))
                Text(section.title.uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }

            hero

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint)
    }

    @ViewBuilder private var hero: some View {
        if let stats = model.stats {
            switch section {
            case .cloni:
                HeroNumber(
                    value: Double(stats.similarCount), format: { Fmt.int($0) },
                    caption: "persone hanno scritto la stessa cosa", gradient: AA.cool
                )
            case .soldiGratis:
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    HeroNumber(
                        value: stats.euroPerDay, format: { Fmt.euro($0) },
                        caption: "al giorno, a gratis", gradient: LinearGradient(
                            colors: [AA.mint, AA.cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    HeroNumber(
                        value: stats.euroPerMonth, format: { Fmt.euro($0) },
                        caption: "al mese", gradient: AA.hot, size: 26
                    )
                }
            case .classifica:
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HeroNumber(
                        value: Double(stats.leaderboardRank), format: { "#" + Fmt.int($0) },
                        caption: "su \(Fmt.int(Double(stats.leaderboardTotal))) che stanno Ai-Ando",
                        gradient: AA.hot
                    )
                }
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .invecePotevi:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    ItemChip(index: i, text: item)
                        .transition(.popIn)
                }
                if items.isEmpty, !text.isEmpty {
                    StreamingText(text: text)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.68), value: items.count)
        case .promptMigliore:
            StreamingText(
                text: text,
                font: .system(size: 14.5, weight: .medium, design: .monospaced),
                style: AnyShapeStyle(Color.white.opacity(0.92)),
                wordSpacing: 7,
                lineSpacing: 5
            )
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AA.cyan.opacity(0.35), lineWidth: 1)
            )
        case .commentoPromptMigliore:
            StreamingText(
                text: text,
                font: .system(size: 21, weight: .semibold),
                style: AnyShapeStyle(Color.white),
                wordSpacing: 6,
                lineSpacing: 5
            )
        default:
            StreamingText(
                text: text,
                font: .system(size: 18, weight: .medium),
                style: AnyShapeStyle(Color.white.opacity(0.93)),
                wordSpacing: 5,
                lineSpacing: 5
            )
        }
    }
}

private struct HeroNumber: View {
    let value: Double
    let format: (Double) -> String
    let caption: String
    let gradient: LinearGradient
    var size: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CountingNumber(value: value, format: format)
                .font(AA.rounded(size, .heavy))
                .foregroundStyle(gradient)
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

private struct ItemChip: View {
    let index: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index + 1)")
                .font(AA.rounded(12, .bold))
                .foregroundStyle(AA.ink)
                .frame(width: 22, height: 22)
                .background(Circle().fill(AA.hot))
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 }
            Text(text)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Bottom ticker: what the Cursor agent is doing + elapsed time.
struct ActivityTicker: View {
    let model: OverlayModel

    var body: some View {
        let finished = model.agentFinished
        let label = finished
            ? "Cursor ha finito. Tu no."
            : (model.activity.isEmpty ? "Cursor sta lavorando per te…" : model.activity)
        HStack(spacing: 8) {
            if finished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AA.mint)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
            } else {
                PulsingDot(color: AA.pink, size: 7)
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .id(label)
                .transition(.push(from: .bottom))
            Spacer(minLength: 8)
            ElapsedLabel(
                start: model.session?.startedAt ?? Date(),
                frozen: finished && model.summary.totalSeconds > 0 ? model.summary.totalSeconds : nil
            )
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: 42)
        .background(Capsule().fill(.ultraThinMaterial))
        .background(Capsule().fill(Color.black.opacity(0.25)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: label)
    }
}

private struct ElapsedLabel: View {
    let start: Date
    let frozen: Double?

    var body: some View {
        if let frozen {
            Text(Fmt.seconds(frozen))
                .font(AA.rounded(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(AA.mint)
        } else {
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                Text(Fmt.seconds(max(0, ctx.date.timeIntervalSince(start))))
                    .font(AA.rounded(13, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
