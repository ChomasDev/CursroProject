import Foundation
import Observation

/// The Cursor CLI (`agent`) runs roasts on the user's own Cursor account, so no API key is needed.
/// Ai-Ando installs it and starts its browser sign-in by itself; the user only approves once in Cursor.
enum CursorAgent {
    static let binFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true)

    /// Newer installs name the binary `agent`; older ones `cursor-agent`.
    static var executable: URL? {
        ["agent", "cursor-agent"].map { binFolder.appendingPathComponent($0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Ai-Ando's own CLI config (sign-in is shared with the user's Cursor CLI). It forces HTTP/1,
    /// because the CLI's default HTTP/2 stream drops on many networks ("Connection lost… WritableIterable is closed").
    static var configFolder: URL {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AiAndo/cursor-cli", isDirectory: true)
        let file = folder.appendingPathComponent("cli-config.json")
        var config = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [String: Any] ?? ["version": 1]
        var network = config["network"] as? [String: Any] ?? [:]
        if network["useHttp1ForAgent"] as? Bool != true {
            network["useHttp1ForAgent"] = true
            config["network"] = network
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: file, options: .atomic)
            }
        }
        return folder
    }

    /// Model IDs the signed-in account can use, from `agent --list-models` ("id - Display name").
    static func models(_ executable: URL) -> [CursorModel] {
        guard let result = try? run(executable, ["--list-models"], timeout: 30), result.status == 0 else { return [] }
        return result.output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: " - ")
            guard parts.count >= 2, !parts[0].contains(" "), !parts[0].isEmpty else { return nil }
            let name = parts.dropFirst().joined(separator: " - ")
                .replacingOccurrences(of: " (current, default)", with: "").replacingOccurrences(of: " (current)", with: "")
                .replacingOccurrences(of: " (default)", with: "")
            return CursorModel(id: parts[0], name: name)
        }
    }

    static func install() throws -> URL {
        let result = try run(URL(fileURLWithPath: "/bin/bash"), ["-c", "curl -fsSL https://cursor.com/install | bash"], timeout: 300)
        guard result.status == 0, let executable else {
            throw RoastServiceError.server("Could not install the Cursor CLI. Check your internet connection and try again.")
        }
        return executable
    }

    static func isSignedIn(_ executable: URL) -> Bool {
        guard let result = try? run(executable, ["status"], timeout: 30), result.status == 0 else { return false }
        let text = result.output.lowercased()
        return !["not logged in", "not authenticated", "unauthenticated", "login", "sign in"].contains { text.contains($0) }
    }

    /// Opens the browser on Cursor's approval page and waits until the user approves.
    static func signIn(_ executable: URL) throws {
        let result = try run(executable, ["login"], timeout: 600)
        guard result.status == 0, isSignedIn(executable) else {
            throw RoastServiceError.server("Cursor sign-in was not completed. Click Connect Cursor to try again.")
        }
    }

    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = [
            "PATH": "\(binFolder.path):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "CURSOR_CONFIG_DIR": configFolder.path,
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

struct CursorModel: Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor @Observable
final class CursorConnection {
    enum State: Equatable { case unknown, checking, installing, signingIn, connected, failed(String) }
    static let shared = CursorConnection()
    private(set) var state: State = .unknown
    private(set) var models: [CursorModel] = []
    private var running: Task<URL, Error>?

    var isBusy: Bool { [.checking, .installing, .signingIn].contains(state) }

    var statusText: String {
        switch state {
        case .unknown: return "Not connected yet"
        case .checking: return "Checking your Cursor account…"
        case .installing: return "Installing Cursor CLI…"
        case .signingIn: return "Approve Ai-Ando in your browser…"
        case .connected: return "Connected to Cursor"
        case .failed(let message): return message
        }
    }

    func loadModels() async {
        guard models.isEmpty, let executable = CursorAgent.executable else { return }
        models = await Task.detached { CursorAgent.models(executable) }.value
    }

    /// Installs and signs in only when needed. Concurrent callers share one attempt.
    @discardableResult
    func connect() async throws -> URL {
        if let running { return try await running.value }
        let task = Task<URL, Error> {
            if state != .connected { state = .checking }
            if let executable = CursorAgent.executable,
               await Task.detached(operation: { CursorAgent.isSignedIn(executable) }).value {
                return executable
            }
            var executable = CursorAgent.executable
            if executable == nil {
                state = .installing
                executable = try await Task.detached(priority: .userInitiated) { try CursorAgent.install() }.value
            }
            state = .signingIn
            let signedIn = executable!
            try await Task.detached(priority: .userInitiated) { try CursorAgent.signIn(signedIn) }.value
            return signedIn
        }
        running = task
        defer { running = nil }
        do {
            let executable = try await task.value
            state = .connected
            AppSettings.shared.refreshCursor()
            if models.isEmpty { models = await Task.detached { CursorAgent.models(executable) }.value }
            return executable
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }
}
