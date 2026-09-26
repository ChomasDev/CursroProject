import Foundation
import Observation
import Security

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case cursor, anthropic, openai, google, openrouter
    var id: String { rawValue }
    /// Cursor uses the signed-in Cursor CLI instead of an API key.
    var needsKey: Bool { self != .cursor }
    var name: String {
        switch self {
        case .cursor: return "Cursor"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .google: return "Google"
        case .openrouter: return "OpenRouter"
        }
    }
    // Suggestions only. Any model ID from the selected provider can be entered.
    var models: [String] {
        switch self {
        case .cursor: return ["auto", "composer-2.5", "gpt-5.2"]
        case .anthropic: return ["claude-sonnet-4-6", "claude-haiku-4-5", "claude-opus-4-6"]
        case .openai: return ["gpt-4.1-mini", "gpt-4.1", "gpt-4o"]
        case .google: return ["gemini-2.5-flash", "gemini-2.5-pro"]
        case .openrouter: return ["anthropic/claude-sonnet-4.6", "openai/gpt-4.1-mini", "google/gemini-2.5-flash"]
        }
    }
}

struct AIConfiguration: Codable, Sendable {
    let provider: String
    let model: String
    let apiKey: String
    var agentPath: String? = nil
}

enum APIKeyStore {
    private static func query(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.aiando.overlay.api-keys",
         kSecAttrAccount as String: provider.rawValue]
    }
    static func read(_ provider: AIProvider) throws -> String {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else { throw keychainError(status) }
        return String(decoding: data, as: UTF8.self)
    }
    static func save(_ key: String, for provider: AIProvider) throws {
        let q = query(provider)
        if key.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
            return
        }
        let data = Data(key.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw keychainError(status) }
    }
    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "Could not access macOS Keychain. \(SecCopyErrorMessageString(status, nil) as String? ?? "Try again.")"])
    }
}

@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    private(set) var provider: AIProvider
    private(set) var model: String
    private(set) var configured: Bool

    init() {
        let chosen = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .cursor
        provider = chosen
        model = UserDefaults.standard.string(forKey: "aiModel.\(chosen.rawValue)") ?? chosen.models[0]
        // Keychain is only opened when the user opens Settings or makes a request.
        configured = chosen.needsKey ? UserDefaults.standard.bool(forKey: "aiConfigured.\(chosen.rawValue)") : CursorAgent.executable != nil
    }
    func savedModel(for provider: AIProvider) -> String {
        defaults.string(forKey: "aiModel.\(provider.rawValue)") ?? provider.models[0]
    }
    func save(provider: AIProvider, model: String, key: String) throws {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw RoastServiceError.server("Enter a model ID.") }
        if provider.needsKey { try APIKeyStore.save(key, for: provider) }
        defaults.set(provider.rawValue, forKey: "aiProvider")
        defaults.set(model, forKey: "aiModel.\(provider.rawValue)")
        defaults.set(!key.isEmpty, forKey: "aiConfigured.\(provider.rawValue)")
        self.provider = provider
        self.model = model
        configured = provider.needsKey ? !key.isEmpty : CursorAgent.executable != nil
    }
    /// Called once the Cursor CLI is installed, so roasts stop falling back to the server.
    func refreshCursor() {
        if !provider.needsKey { configured = CursorAgent.executable != nil }
    }
    func configuration() throws -> AIConfiguration {
        if !provider.needsKey {
            guard let agent = CursorAgent.executable else { throw RoastServiceError.server("Click Connect Cursor in Ai-Ando to start.") }
            configured = true
            return AIConfiguration(provider: provider.rawValue, model: model, apiKey: "", agentPath: agent.path)
        }
        let key = try APIKeyStore.read(provider)
        guard !key.isEmpty else { throw RoastServiceError.server("Add your API key in Settings to start.") }
        return AIConfiguration(provider: provider.rawValue, model: model, apiKey: key)
    }
}
