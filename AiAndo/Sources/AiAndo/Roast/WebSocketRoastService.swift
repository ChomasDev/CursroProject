import Foundation

/// Streams a roast from the WebSocket backend, one JSON frame per update.
struct WebSocketRoastService: RoastService {
    let url: URL
    /// Max silence between two frames before giving up.
    var idleTimeout: TimeInterval

    init(url: URL, idleTimeout: TimeInterval = 20) {
        self.url = url
        self.idleTimeout = idleTimeout
    }

    func roast(_ request: RoastRequest) -> AsyncThrowingStream<RoastUpdate, Error> {
        let url = self.url
        let idleTimeout = self.idleTimeout

        return AsyncThrowingStream { continuation in
            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: url)

            let worker = Task {
                defer {
                    task.cancel(with: .normalClosure, reason: nil)
                    session.invalidateAndCancel()
                }
                do {
                    task.resume()
                    let json = try RoastWireRequest(request).jsonString()
                    try await task.send(.string(json))

                    while !Task.isCancelled {
                        let message = try await Self.receive(task, timeout: idleTimeout)
                        let data: Data
                        switch message {
                        case .string(let s): data = Data(s.utf8)
                        case .data(let d): data = d
                        @unknown default: continue
                        }
                        guard let wire = RoastWireMessage.decode(data) else { continue }
                        switch wire {
                        case .error(let msg):
                            throw RoastServiceError.server(msg)
                        case .done:
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        default:
                            if let update = wire.update { continuation.yield(update) }
                        }
                    }
                    continuation.finish(throwing: CancellationError())
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                    } else if task.closeCode != .invalid, !(error is RoastServiceError) {
                        continuation.finish(throwing: RoastServiceError.closed)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    /// Receives one frame, or throws `.timeout` after `timeout` seconds of silence.
    private static func receive(_ task: URLSessionWebSocketTask,
                                timeout: TimeInterval) async throws -> URLSessionWebSocketTask.Message {
        let flag = TimeoutFlag()
        return try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await task.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                flag.value = true
                // receive() ignores task cancellation; closing the socket unblocks it.
                task.cancel(with: .goingAway, reason: nil)
                throw RoastServiceError.timeout
            }
            defer { group.cancelAll() }
            do {
                guard let first = try await group.next() else { throw RoastServiceError.closed }
                return first
            } catch {
                // If the timeout fired, the receive child may fail first with a URL error.
                if flag.value { throw RoastServiceError.timeout }
                throw error
            }
        }
    }
}

/// Thread-safe bool used to tell a timeout apart from a socket failure.
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
