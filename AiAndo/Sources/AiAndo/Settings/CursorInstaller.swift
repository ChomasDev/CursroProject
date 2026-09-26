import Foundation

/// Installs only Ai-Ando's integration and preserves unrelated Cursor hooks.
struct CursorInstaller {
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    var hooksURL: URL { home.appendingPathComponent(".cursor/hooks.json") }
    var scriptURL: URL { home.appendingPathComponent(".cursor/prompt-mirror/prompt-mirror.py") }
    static let events = ["beforeSubmitPrompt", "afterAgentThought", "preToolUse", "postToolUse", "postToolUseFailure", "afterAgentResponse", "stop"]
    var command: String { "/usr/bin/python3 '\(scriptURL.path.replacingOccurrences(of: "'", with: "'\\''"))'" }

    var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: scriptURL.path),
              let data = try? Data(contentsOf: hooksURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.events.allSatisfy { event in
            (hooks[event] as? [[String: Any]])?.contains { $0["command"] as? String == command } == true
        }
    }

    func install(bundle: URL = Bundle.main.bundleURL) throws {
        let fm = FileManager.default
        let resource = bundle.appendingPathComponent("Contents/Resources/prompt-mirror.py")
        guard fm.fileExists(atPath: resource.path) else { throw RoastServiceError.server("Build the app first to include its Cursor integration.") }
        // Parse before touching the installation; never replace an unreadable config.
        var root: [String: Any] = ["version": 1, "hooks": [String: Any]()]
        if fm.fileExists(atPath: hooksURL.path) {
            guard let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksURL)) as? [String: Any],
                  existing["hooks"] == nil || existing["hooks"] is [String: Any] else {
                throw RoastServiceError.server("Cursor hooks.json is invalid. Fix it before installing.")
            }
            root = existing
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in Self.events {
            if let entries = hooks[event], !(entries is [[String: Any]]) {
                throw RoastServiceError.server("Cursor's \(event) hooks are invalid. Fix hooks.json before installing.")
            }
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll {
                guard let old = $0["command"] as? String else { return false }
                return old == command || old.contains("prompt-overlay/hooks/prompt-mirror.py")
                    || old.contains("/.cursor/prompt-mirror/prompt-mirror.py")
                    || old == "python3 ./hooks/prompt-mirror.py"
            }
            entries.append(["command": command, "timeout": 2, "failClosed": false])
            hooks[event] = entries
        }
        root["hooks"] = hooks
        if root["version"] == nil { root["version"] = 1 }
        let configData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let app = home.appendingPathComponent("Applications/AiAndo.app")
        try fm.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
        if bundle.standardizedFileURL.resolvingSymlinksInPath() != app.standardizedFileURL.resolvingSymlinksInPath() {
            // Stage a full copy before replacing an existing installation.
            let stage = app.deletingLastPathComponent().appendingPathComponent(".AiAndo-\(UUID().uuidString).app")
            try fm.copyItem(at: bundle, to: stage)
            defer { try? fm.removeItem(at: stage) }
            if fm.fileExists(atPath: app.path) {
                _ = try fm.replaceItemAt(app, withItemAt: stage)
            } else { try fm.moveItem(at: stage, to: app) }
        }
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: hooksURL.path) {
            let backup = hooksURL.deletingLastPathComponent().appendingPathComponent("hooks.aiando-backup-\(UUID().uuidString).json")
            try fm.copyItem(at: hooksURL, to: backup)
        }
        try Data(contentsOf: resource).write(to: scriptURL, options: .atomic)
        try configData.write(to: hooksURL, options: .atomic)
    }
}
