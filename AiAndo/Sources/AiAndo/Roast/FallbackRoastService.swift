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

    /// `AIANDO_WS_URL` env var (or UserDefaults "wsURL") → Fallback(WebSocket, Mock); otherwise Mock.
    static func make() -> any RoastService {
        guard let url = configuredURL() else { return MockRoastService() }
        return FallbackRoastService(primary: WebSocketRoastService(url: url), fallback: MockRoastService())
    }

    static func configuredURL() -> URL? {
        let raw = ProcessInfo.processInfo.environment[envKey]
            ?? UserDefaults.standard.string(forKey: defaultsKey)
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              ["ws", "wss"].contains(scheme) else { return nil }
        return url
    }
}
