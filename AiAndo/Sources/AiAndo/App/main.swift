import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = OverlayModel()
    private var panel: OverlayPanelController!
    private var coordinator: Coordinator?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = OverlayPanelController(model: model)
        installStatusItem()

        if CommandLine.arguments.contains("--demo") {
            model.onDismiss = { [weak self] in self?.panel.hide() }
            panel.show()
            UIDemo.run(model: model)
            return
        }

        let coordinator = Coordinator(
            model: model,
            panel: panel,
            source: EventLogWatcher(),
            service: RoastServiceFactory.make()
        )
        coordinator.start()
        self.coordinator = coordinator
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "💀"
        let menu = NSMenu()
        menu.addItem(withTitle: "Ai-Ando è in ascolto su Cursor", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
