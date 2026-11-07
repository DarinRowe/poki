import Foundation

/// The model providers the chat can use with the owner's own key (ESP-171 board "M Model"). Anthropic and
/// OpenAI are wired; the others store their key and address now and are wired in a later step.
enum ModelProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, gemini, openrouter, custom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .openrouter: "OpenRouter"
        case .custom: String(localized: "Custom Endpoint")
        }
    }

    /// The letter on the coloured tile, and the tile's colour (from the board).
    var mark: String {
        switch self {
        case .anthropic: "A"
        case .openai: "O"
        case .gemini: "G"
        case .openrouter: "R"
        case .custom: "{ }"
        }
    }

    var tile: UInt32 {
        switch self {
        case .anthropic: 0xD97757
        case .openai: 0x111111
        case .gemini: 0x4285F4
        case .openrouter: 0x6566F1
        case .custom: 0x8E8E93
        }
    }

    /// The chat runs on this provider today.
    var wired: Bool { self == .anthropic || self == .openai }

    /// What a key looks like, for the field's placeholder.
    var keyPrompt: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        case .openrouter: "sk-or-…"
        case .custom: String(localized: "API key, if it needs one")
        }
    }

    var models: [ChatModelChoice] {
        switch self {
        case .anthropic: [
            ChatModelChoice(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
            ChatModelChoice(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
            ChatModelChoice(id: "claude-haiku-5-5", name: "Claude Haiku 5.5"),
        ]
        // The Mac Poki Agent's pi loop model (ESP-62).
        case .openai: [ChatModelChoice(id: "gpt-6.1-sol", name: "GPT-6.1 Sol")]
        default: []
        }
    }

    /// Where the owner creates a key.
    var keyHelp: String {
        switch self {
        case .anthropic: String(localized: "Create a key at console.anthropic.com, then paste it here.")
        case .openai: String(localized: "Create a key at platform.openai.com, then paste it here.")
        default: ""
        }
    }
}

struct ChatModelChoice: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
}

/// The owner's keys, in this iPhone's keychain (the relay key's service, one account per provider). A key
/// is only ever sent to its own provider. Nothing here prints or logs a key.
enum ModelKeys {
    private static func account(_ provider: ModelProvider) -> String { "model-key.\(provider.rawValue)" }

    static func key(_ provider: ModelProvider) -> String? {
        guard let data = try? Keychain.read(account(provider)), let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func hasKey(_ provider: ModelProvider) -> Bool { key(provider) != nil }

    static func save(_ key: String, for provider: ModelProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try Keychain.write(Data(trimmed.utf8), account: account(provider))
        saved += 1
    }

    static func remove(_ provider: ModelProvider) {
        Keychain.delete(account(provider))
        saved += 1
    }

    /// The custom endpoint's address (not a secret: kept in the app's settings).
    static var customURL: String {
        get { UserDefaults.standard.string(forKey: "chat.customURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "chat.customURL") }
    }

    /// The chat can run: the chosen provider is wired and has a key.
    static var hasUsableKey: Bool { selectedProvider.wired && hasKey(selectedProvider) }

    static var selectedProvider: ModelProvider {
        get { UserDefaults.standard.string(forKey: "chat.provider").flatMap(ModelProvider.init(rawValue:)) ?? .anthropic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "chat.provider") }
    }

    /// Each provider's model: its first (Claude Sonnet 5.5, GPT-6.1 Sol) unless the owner picks another.
    static func model(for provider: ModelProvider) -> String {
        let saved = UserDefaults.standard.string(forKey: "chat.model.\(provider.rawValue)")
        return saved.flatMap { id in provider.models.contains { $0.id == id } ? id : nil } ?? provider.models.first?.id ?? ""
    }

    static var selectedModel: String {
        get { model(for: selectedProvider) }
        set { UserDefaults.standard.set(newValue, forKey: "chat.model.\(selectedProvider.rawValue)") }
    }

    static var selectedModelName: String {
        selectedProvider.models.first { $0.id == selectedModel }?.name ?? selectedModel
    }

    /// Bumped on every change, so views that read keys can redraw.
    nonisolated(unsafe) static var saved = 0
}
