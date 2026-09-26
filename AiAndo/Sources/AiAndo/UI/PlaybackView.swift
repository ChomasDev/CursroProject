import AppKit
import SwiftUI

/// Full-screen, transparent, Dia-style playback: one centered phrase at a time.
struct PlaybackView: View {
    let model: OverlayModel
    @State private var player = BeatPlayer()

    var body: some View {
        ZStack {
            // Light dim over the whole screen, so the overlay reads as one layer, edge to edge.
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Frosted blur over the whole screen: strongest behind the text, softer toward the edges, never cut off.
            SoftBlurHalo()
                .ignoresSafeArea()
                .opacity(player.current == nil && !player.showPlaceholder ? 0.6 : 1)
                .animation(.easeInOut(duration: 1.0), value: player.current == nil)
                .allowsHitTesting(false)

            // Very subtle vignette behind the centered text, for legibility. Nothing else.
            RadialGradient(
                stops: [
                    .init(color: Color.black.opacity(0.45), location: 0),
                    .init(color: Color.black.opacity(0.35), location: 0.45),
                    .init(color: Color.black.opacity(0.18), location: 0.8),
                    .init(color: .clear, location: 1),
                ],
                center: .center, startRadius: 0, endRadius: 560
            )
            .scaleEffect(x: 1.9, y: 1)
            .allowsHitTesting(false)

            ZStack {
                if let beat = player.current {
                    BeatView(beat: beat, activity: model.activity)
                        .id(beat.id)
                        .transition(.beat)
                } else if player.showPlaceholder {
                    ThinkingDots()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 60)

            VStack {
                Spacer()
                ActivityLine(model: model)
                    .padding(.bottom, 34)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: model.session?.id) {
            await player.run(model: model)
        }
    }
}

private struct BeatView: View {
    let beat: Beat
    let activity: String
    @State private var labelShown = false

    private var font: Font {
        let w = beat.wordCount
        switch beat.style {
        case .statement:
            return .system(size: w <= 10 ? 56 : (w <= 18 ? 50 : 44), weight: .semibold)
        case .quote:
            return .system(size: w <= 12 ? 50 : 42, weight: .regular, design: .serif).italic()
        case .code:
            return .system(size: w <= 20 ? 32 : 26, weight: .semibold, design: .monospaced)
        case .punchline:
            return .system(size: 64, weight: .bold)
        case .waiting:
            return .system(size: 40, weight: .medium)
        }
    }

    private var fontSize: CGFloat {
        let w = beat.wordCount
        switch beat.style {
        case .statement: return w <= 10 ? 56 : (w <= 18 ? 50 : 44)
        case .quote: return w <= 12 ? 50 : 42
        case .code: return w <= 20 ? 32 : 26
        case .punchline: return 64
        case .waiting: return 40
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            if let label = beat.label {
                Text(beat.labelIsCaps ? label.uppercased() : label)
                    .font(.system(size: beat.labelIsCaps ? 14 : 20, weight: beat.labelIsCaps ? .semibold : .medium))
                    .tracking(beat.labelIsCaps ? 3.2 : 0.3)
                    .foregroundStyle(.white.opacity(0.55))
                    .blur(radius: labelShown ? 0 : 8)
                    .opacity(labelShown ? 1 : 0)
                    .offset(y: labelShown ? 0 : 6)
            }

            WordRevealText(
                text: beat.text,
                font: font,
                color: beat.style == .code ? Color.white.opacity(0.92) : .white,
                highlightNumbers: beat.style != .code && beat.style != .quote,
                alignment: .center,
                wordSpacing: fontSize * (beat.style == .code ? 0.55 : 0.27),
                lineSpacing: fontSize * 0.2,
                perWord: beat.perWord / BeatPlayer.pace,
                startDelay: beat.startDelay / BeatPlayer.pace
            )

            if beat.style == .waiting {
                Text(activity.isEmpty ? "Cursor sta lavorando…" : activity)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .id(activity)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .animation(.easeInOut(duration: 0.6), value: activity)
                    .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.7), radius: 24, y: 2)
        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.05)) { labelShown = true }
        }
    }
}

extension AnyTransition {
    /// Beat enters via its words; it leaves by blurring/fading away upwards.
    static var beat: AnyTransition {
        .asymmetric(
            insertion: .identity,
            removal: .modifier(
                active: BlurFadeModifier(radius: 20, opacity: 0, scale: 1.02, y: -18),
                identity: BlurFadeModifier(radius: 0, opacity: 1, scale: 1, y: 0)
            )
        )
    }
}

private struct ThinkingDots: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .opacity(on ? 0.85 : 0.2)
                    .scaleEffect(on ? 1 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(Double(i) * 0.25),
                        value: on
                    )
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 10)
        .onAppear { on = true }
    }
}

/// Tiny, discreet line: what the agent is doing + elapsed.
private struct ActivityLine: View {
    let model: OverlayModel

    var body: some View {
        let finished = model.agentFinished
        let text = finished ? "Cursor ha finito" : (model.activity.isEmpty ? "Cursor sta lavorando" : model.activity)
        HStack(spacing: 8) {
            Circle()
                .fill(finished ? AA.mint : Color.white)
                .frame(width: 5, height: 5)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: true, vertical: false)
            Text("·")
            if finished, model.summary.totalSeconds > 0 {
                Text(Fmt.seconds(model.summary.totalSeconds)).monospacedDigit()
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("\(Int(max(0, ctx.date.timeIntervalSince(model.session?.startedAt ?? ctx.date))))s")
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .opacity(0.45)
        .shadow(color: .black.opacity(0.6), radius: 6)
        .animation(.easeInOut(duration: 0.5), value: text)
    }
}

/// Full-screen behind-window blur with a radial alpha mask: an ellipse stretched to the screen,
/// so it fades continuously and has no visible edge anywhere.
private struct SoftBlurHalo: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        v.maskImage = Self.mask
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    static let mask: NSImage = {
        let size = NSSize(width: 256, height: 256)
        let image = NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colorsAndLocations:
                (NSColor.black, 0.0),
                (NSColor.black.withAlphaComponent(0.85), 0.4),
                (NSColor.black.withAlphaComponent(0.45), 0.75),
                (NSColor.black.withAlphaComponent(0.2), 1.0))
            let center = NSPoint(x: rect.midX, y: rect.midY)
            // Ends at the edge midpoints; the corners keep the last (light) alpha, so nothing is clipped.
            g?.draw(fromCenter: center, radius: 0, toCenter: center, radius: rect.width / 2,
                    options: [.drawsAfterEndingLocation])
            return true
        }
        image.resizingMode = .stretch
        return image
    }()
}
