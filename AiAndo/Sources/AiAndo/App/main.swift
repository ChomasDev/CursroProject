import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = OverlayModel()
    private var panel: OverlayPanelController!
    private var coordinator: Coordinator?
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OverlayPanelController(model: model)
        installMainMenu()
        installStatusItem()
        coordinator = Coordinator(model: model, panel: panel, source: EventLogWatcher(), service: RoastServiceFactory.make())
        coordinator?.start()
        if CommandLine.arguments.contains("--demo") { showPreview() }
        else if !CommandLine.arguments.contains("--background") { showApp() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showApp()
        return true
    }
    @objc private func showApp() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 800),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Ai-Ando"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.minSize = NSSize(width: 680, height: 700)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AppPage() { [weak self] in self?.showPreview() })
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func showSettings() {
        showApp()
        NotificationCenter.default.post(name: .openAISettings, object: nil)
    }
    @objc private func showPreview() {
        guard model.phase == .idle || model.agentFinished else { return }
        UIDemo.run(model: model)
        panel.show()
    }
    /// AppKit routes text-editing shortcuts through the main menu, even in a menu-bar app.
    private func installMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Ai-Ando")
        let settings = applicationMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Hide Ai-Ando", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(withTitle: "Quit Ai-Ando", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        for (title, action, key) in [
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            // A nil target sends the action to the focused field's native editor.
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "💀"
        let menu = NSMenu()
        for (title, action, key) in [
            ("Open Ai-Ando", #selector(showApp), ""),
            ("Settings…", #selector(showSettings), ","),
            ("Preview roast", #selector(showPreview), ""),
        ] {
            let entry = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            entry.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ai-Ando", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
