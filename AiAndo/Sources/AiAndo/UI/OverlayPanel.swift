import AppKit
import Observation
import SwiftUI

/// Borderless, non-activating floating panel. It never activates the app, so Cursor keeps focus,
/// but it can still receive clicks (and ESC once the user clicked it).
final class OverlayPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// Owns the overlay window. By default it follows `model.phase` (shown when not `.idle`),
/// so the App layer only has to mutate the model; `show()` / `hide()` are idempotent.
@MainActor
final class OverlayPanelController {
    static let size = CGSize(width: 520, height: 640)
    static let margin: CGFloat = 24

    let model: OverlayModel
    private let panel: OverlayPanel
    private let mover = WindowMover()
    private let followsModelPhase: Bool
    private var escMonitor: Any?
    private(set) var isShown = false

    init(model: OverlayModel, followsModelPhase: Bool = true) {
        self.model = model
        self.followsModelPhase = followsModelPhase

        let panel = OverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.animationBehavior = .none
        self.panel = panel

        // Real glass: behind-window blur, clipped to a rounded rect.
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.maskImage = Self.roundedMask(radius: AA.cornerRadius)
        glass.autoresizingMask = [.width, .height]

        mover.window = panel
        let hosting = NSHostingView(rootView: OverlayRootView(model: model, mover: mover))
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = AA.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        if #available(macOS 13.0, *) { hosting.sizingOptions = [] }
        glass.addSubview(hosting)
        panel.contentView = glass

        panel.onEscape = { [weak model] in model?.dismiss() }

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.isShown else { return event }
            self.model.dismiss()
            return nil
        }

        if followsModelPhase {
            observePhase()
            syncWithPhase()
        }
    }

    deinit {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    /// Shows the panel at the top-right of the screen containing the mouse (no focus steal).
    func show() {
        guard !isShown else {
            panel.orderFrontRegardless()
            return
        }
        isShown = true
        let target = targetFrame()
        panel.setFrame(target.offsetBy(dx: 0, dy: 14), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    /// Fades the panel out and orders it off screen.
    func hide() {
        guard isShown else { return }
        isShown = false
        mover.end()
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(frame.offsetBy(dx: 0, dy: 10), display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    // MARK: - Private

    private func observePhase() {
        withObservationTracking {
            _ = model.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.syncWithPhase()
                self.observePhase()
            }
        }
    }

    private func syncWithPhase() {
        if model.phase == .idle { hide() } else { show() }
    }

    private func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = Self.size
        return NSRect(
            x: visible.maxX - size.width - Self.margin,
            y: visible.maxY - size.height - Self.margin,
            width: size.width,
            height: size.height
        )
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
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
