import AppKit
import SwiftUI

/// Moves the hosting window while the user drags the overlay background.
@MainActor
final class WindowMover {
    weak var window: NSWindow?
    private var startOrigin: NSPoint?
    private var startMouse: NSPoint?

    func drag() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        if startOrigin == nil {
            startOrigin = window.frame.origin
            startMouse = mouse
        }
        guard let o = startOrigin, let m = startMouse else { return }
        window.setFrameOrigin(NSPoint(x: o.x + mouse.x - m.x, y: o.y + mouse.y - m.y))
    }

    func end() {
        startOrigin = nil
        startMouse = nil
    }
}

/// Root of the overlay: aurora + glass + phase content.
struct OverlayRootView: View {
    let model: OverlayModel
    var mover: WindowMover?

    private var energy: Double {
        switch model.phase {
        case .intro: return 1
        case .roasting: return 0.55
        default: return 0.35
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AA.cornerRadius, style: .continuous)
        ZStack {
            // Aurora tinted over the real behind-window blur (NSVisualEffectView in the panel).
            AuroraBackground(energy: energy)
                .opacity(model.phase == .intro ? 0.62 : 0.48)
                .saturation(1.1)
            // Legibility scrim.
            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.black.opacity(0.42)],
                startPoint: .top, endPoint: .bottom
            )
            NoiseOverlay(opacity: 0.08)

            VStack(spacing: 0) {
                HeaderBar(model: model)
                ZStack {
                    switch model.phase {
                    case .idle:
                        Color.clear
                    case .intro:
                        IntroView(prompt: model.session?.prompt ?? "")
                            .id(model.session?.id ?? "intro")
                            .transition(.blurRise)
                    case .roasting:
                        RoastingView(model: model)
                            .transition(.blurRise)
                    case .summary:
                        SummaryView(model: model)
                            .transition(.blurRise)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.35), .white.opacity(0.06), .white.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
        .animation(.spring(response: 0.85, dampingFraction: 0.86), value: model.phase)
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { _ in mover?.drag() }
                .onEnded { _ in mover?.end() }
        )
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

private struct HeaderBar: View {
    let model: OverlayModel
    @State private var hoveringClose = false

    private var phaseLabel: String {
        switch model.phase {
        case .idle: return ""
        case .intro: return "ti ho visto"
        case .roasting: return model.roastFinished ? "roast completo" : "roast in corso"
        case .summary: return "wrapped"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AA.hot)
                .frame(width: 10, height: 10)
                .shadow(color: AA.pink.opacity(0.9), radius: 6)
            Text("Ai-Ando")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(phaseLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .id(phaseLabel)
                .transition(.push(from: .bottom))
            Spacer()
            if let err = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AA.orange)
                    .help(err)
            }
            Button {
                model.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(hoveringClose ? 1 : 0.75))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(hoveringClose ? 0.22 : 0.12)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .onHover { hoveringClose = $0 }
            .help("Chiudi (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: phaseLabel)
    }
}
