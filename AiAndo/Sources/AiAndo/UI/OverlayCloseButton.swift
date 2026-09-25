import AppKit
import SwiftUI

/// Small always-clickable panel holding the X in the top-right corner. It lives in its own window
/// because the main overlay ignores mouse events during `.intro`/`.roasting`.
@MainActor
final class OverlayCloseButton {
    private static let size: CGFloat = 44
    private static let inset: CGFloat = 20
    private let panel: NSPanel

    init(action: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.contentView = FirstMouseHostingView(rootView: CloseButtonView(action: action))
        self.panel = panel
    }

    /// Places the button in the top-right corner of `screenFrame`, below the menu bar.
    func show(on screenFrame: NSRect) {
        let visible = NSScreen.screens.first { $0.frame == screenFrame }?.visibleFrame ?? screenFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - Self.size - Self.inset,
            y: visible.maxY - Self.size - Self.inset
        ))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Lets the first click on a non-key panel trigger the button.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CloseButtonView: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.black.opacity(hovering ? 0.75 : 0.55)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Chiudi (⌘L)")
        .environment(\.colorScheme, .dark)
    }
}
