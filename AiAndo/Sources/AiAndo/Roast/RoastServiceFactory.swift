import Foundation

enum RoastServiceFactory {
    static func make() -> any RoastService { LocalAIRoastService() }

    /// LAN mode is explicit and never carries the personal API key.
    static func configuredURL() -> URL? {
        guard let raw = ProcessInfo.processInfo.environment["AIANDO_WS_URL"],
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
