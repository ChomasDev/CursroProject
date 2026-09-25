import AppKit
import SwiftUI

/// Root of the full-screen overlay. Transparent; playback (intro + roasting) or the summary card.
struct OverlayRootView: View {
    let model: OverlayModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .idle:
                Color.clear
            case .intro, .roasting:
                // Same identity for both phases: the playback owns the intro beats.
                PlaybackView(model: model)
                    .transition(.opacity)
            case .summary:
                SummaryView(model: model)
                    .transition(.opacity)
            }

            if let line = model.dizzyLine {
                DizzyCaption(text: line)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 1.0), value: model.phase == .summary)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: model.dizzyLine)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
    }
}

/// Real behind-window blur for the summary card.
struct BehindWindowBlur: NSViewRepresentable {
    var radius: CGFloat = 28

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        v.maskImage = Self.mask(radius: radius)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
