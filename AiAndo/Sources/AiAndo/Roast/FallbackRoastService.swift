import Foundation

/// Uses `primary`; if it fails before yielding anything, transparently switches to `fallback`.
/// Errors after the first update are propagated as-is (no mixed roasts).
struct FallbackRoastService: RoastService {
    let primary: any RoastService
    let fallback: any RoastService

    init(primary: any RoastService, fallback: any RoastService = MockRoastService()) {
        self.primary = primary
        self.fallback = fallback
    }

    func roast(_ request: RoastRequest) -> AsyncThrowingStream<RoastUpdate, Error> {
        let primary = self.primary, fallback = self.fallback
        return AsyncThrowingStream { continuation in
            let task = Task {
                var yieldedAny = false
                do {
                    for try await update in primary.roast(request) {
                        yieldedAny = true
                        continuation.yield(update)
                    }
                    continuation.finish()
                    return
                } catch {
                    if Task.isCancelled || yieldedAny || error is CancellationError {
                        continuation.finish(throwing: error)
                        return
                    }
                    print("[AiAndo] roast backend failed (\(error.localizedDescription)), using mock")
                }
                do {
                    for try await update in fallback.roast(request) {
                        continuation.yield(update)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum RoastServiceFactory {
    static let envKey = "AIANDO_WS_URL"
    static let defaultsKey = "wsURL"

    static let defaultURL = "ws://127.0.0.1:3000/roast"

    /// Local roast socket, unless `AIANDO_WS_URL` or UserDefaults "wsURL" points somewhere else.
    /// If that socket fails before the first frame, the mock roast is used.
    static func make() -> any RoastService {
        guard let url = configuredURL() else { return MockRoastService() }
        return FallbackRoastService(primary: WebSocketRoastService(url: url), fallback: MockRoastService())
    }

    static func configuredURL() -> URL? {
        let configured = ProcessInfo.processInfo.environment[envKey]
            ?? UserDefaults.standard.string(forKey: defaultsKey)
        let raw = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = (raw?.isEmpty == false) ? raw! : defaultURL
        guard let url = URL(string: chosen), let scheme = url.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme) else { return nil }
        return url
    }
}
