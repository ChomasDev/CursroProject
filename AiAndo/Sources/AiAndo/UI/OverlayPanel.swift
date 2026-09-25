import AppKit
import Observation
import SwiftUI

/// Borderless, transparent, non-activating full-screen panel. It never activates the app, so Cursor
/// keeps focus.
final class OverlayPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if Self.closesOverlay(event) { onEscape?() } else { super.keyDown(with: event) }
    }

    /// Esc, or Command+L.
    static func closesOverlay(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { return true }
        let isL = event.keyCode == 37 || event.charactersIgnoringModifiers?.lowercased() == "l"
        return isL && event.modifierFlags.contains(.command)
    }
}

/// Owns the overlay window. By default it follows `model.phase`: shown when not `.idle`,
/// click-through during `.intro`/`.roasting`, clickable only in `.summary`.
/// `show()` / `hide()` are idempotent.
@MainActor
final class OverlayPanelController {
    let model: OverlayModel
    private let panel: OverlayPanel
    private let followsModelPhase: Bool
    private var localEsc: Any?
    private var globalEsc: Any?
    private let frenzy: MouseFrenzyMonitor
    private var closeHotKey: OverlayHotKey?
    private(set) var isShown = false

    init(model: OverlayModel, followsModelPhase: Bool = true) {
        self.model = model
        self.followsModelPhase = followsModelPhase
        self.frenzy = MouseFrenzyMonitor(model: model)

        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
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
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.animationBehavior = .none
        self.panel = panel

        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        panel.onEscape = { [weak model] in model?.dismiss() }
        closeHotKey = OverlayHotKey { [weak model] in model?.dismiss() }

        localEsc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, OverlayPanel.closesOverlay(event), self.isShown else { return event }
            self.model.dismiss()
            return nil
        }
        // Works only if the app has Accessibility permission; harmless otherwise.
        globalEsc = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard OverlayPanel.closesOverlay(event) else { return }
            Task { @MainActor in
                guard let self, self.isShown, self.model.phase == .summary else { return }
                self.model.dismiss()
            }
        }

        if followsModelPhase {
            observePhase()
            syncWithPhase()
        }
    }

    deinit {
        if let localEsc { NSEvent.removeMonitor(localEsc) }
        if let globalEsc { NSEvent.removeMonitor(globalEsc) }
    }

    /// Shows the panel over the whole screen containing the mouse (no focus steal).
    func show() {
        frenzy.start()
        closeHotKey?.register()
        panel.ignoresMouseEvents = model.phase != .summary
        guard !isShown else {
            panel.orderFrontRegardless()
            return
        }
        isShown = true
        panel.setFrame(targetFrame(), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// Fades the panel out and orders it off screen.
    func hide() {
        guard isShown else { return }
        isShown = false
        frenzy.stop()
        closeHotKey?.unregister()
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
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
        if model.phase == .idle {
            hide()
        } else {
            show()
        }
    }

    private func targetFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
