import Foundation

/// Uses the bundled AI SDK worker over private pipes; no local HTTP server is needed.
struct LocalAIRoastService: RoastService {
    func roast(_ request: RoastRequest) -> AsyncThrowingStream<RoastUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let stream: AsyncThrowingStream<RoastUpdate, Error>
                    if await !AppSettings.shared.configured, let url = RoastServiceFactory.configuredURL() {
                        stream = WebSocketRoastService(url: url).roast(request)
                    } else {
                        if await AppSettings.shared.provider == .cursor { try await CursorConnection.shared.connect() }
                        let configuration = try await AppSettings.shared.configuration()
                        stream = AIWorker.run(configuration: configuration, prompt: request.prompt, user: request.user)
                    }
                    for try await update in stream {
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum AIWorker {
    static func test(_ configuration: AIConfiguration) async throws {
        for try await _ in run(configuration: configuration, prompt: nil, user: "test") {}
    }

    static func run(configuration: AIConfiguration, prompt: String?, user: String) -> AsyncThrowingStream<RoastUpdate, Error> {
        let control = WorkerControl()
        return AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let resources = Bundle.main.resourceURL,
                          FileManager.default.fileExists(atPath: resources.appendingPathComponent("ai-worker.cjs").path),
                          FileManager.default.isExecutableFile(atPath: resources.appendingPathComponent("node").path)
                    else { throw RoastServiceError.server("Build the app with AiAndo/scripts/build-app.sh to include its AI runner.") }
                    let process = Process()
                    process.executableURL = resources.appendingPathComponent("node")
                    process.arguments = [resources.appendingPathComponent("ai-worker.cjs").path]
                    let dataFolder = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Application Support/AiAndo", isDirectory: true)
                    try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
                    process.environment = [
                        "PATH": "/usr/bin:/bin",
                        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                        "AIANDO_DESKTOP": "1",
                        "SYSTEM_PROMPT_PATH": resources.appendingPathComponent("ai-ando-system-prompt.md").path,
                        "AIANDO_DATA_FILE": dataFolder.appendingPathComponent("leaderboard.json").path,
                    ]
                    let input = Pipe(), output = Pipe()
                    process.standardInput = input
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    guard try control.start(process) else { throw CancellationError() }
                    defer {
                        control.cancel()
                        try? output.fileHandleForReading.close()
                    }
                    struct Request: Encodable {
                        let operation: String
                        let prompt: String?
                        let user: String
                        let ai: AIConfiguration
                    }
                    let payload = try JSONEncoder().encode(Request(operation: prompt == nil ? "test" : "roast", prompt: prompt, user: user, ai: configuration))
                    try input.fileHandleForWriting.write(contentsOf: payload)
                    try input.fileHandleForWriting.close()
                    var buffer = Data()
                    var done = false
                    while !control.isCancelled {
                        let data = output.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        buffer.append(data)
                        while let newline = buffer.firstIndex(of: 10) {
                            let line = Data(buffer[..<newline])
                            buffer.removeSubrange(...newline)
                            guard let message = RoastWireMessage.decode(line) else { continue }
                            if case .error(let text) = message { throw RoastServiceError.server(text) }
                            if let update = message.update { continuation.yield(update) }
                            if case .done = message { done = true }
                        }
                    }
                    if control.isCancelled { throw CancellationError() }
                    process.waitUntilExit()
                    guard done, process.terminationStatus == 0 else { throw RoastServiceError.server("AI runner stopped unexpectedly. Try again.") }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in control.cancel() }
        }
    }
}

private final class WorkerControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func start(_ process: Process) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        try process.run()
        self.process = process
        return true
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}
