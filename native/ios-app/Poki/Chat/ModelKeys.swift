import Foundation
import PiSwiftAI

/// The model providers the chat can use with the owner's own key or account (ESP-171 board "M Model").
/// The wired ones run through pi (PiLoop); the others store their key and address for a later step.
enum ModelProvider: String, CaseIterable, Identifiable, Sendable {
    case anthropic, openai, chatgpt, deepseek, gemini, openrouter, custom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        case .chatgpt: "ChatGPT"
        case .deepseek: "DeepSeek"
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
        case .chatgpt: "C"
        case .deepseek: "D"
        case .gemini: "G"
        case .openrouter: "R"
        case .custom: "{ }"
        }
    }

    var tile: UInt32 {
        switch self {
        case .anthropic: 0xD97757
        case .openai: 0x111111
        case .chatgpt: 0x10A37F
        case .deepseek: 0x4D6BFE
        case .gemini: 0x4285F4
        case .openrouter: 0x6566F1
        case .custom: 0x8E8E93
        }
    }

    /// pi's provider id (PiSwiftAI's catalog).
    var piProvider: String? {
        switch self {
        case .anthropic: "anthropic"
        case .openai: "openai"
        case .chatgpt: "openai-codex"
        case .deepseek: "deepseek"
        case .gemini: "google"
        default: nil
        }
    }

    /// The chat runs on this provider today. ChatGPT, DeepSeek and Gemini run only through pi.
    var wired: Bool { piProvider != nil }

    /// ChatGPT is an account the owner signs in to; the others take a key.
    var signsIn: Bool { self == .chatgpt }

    /// What a key looks like, for the field's placeholder.
    var keyPrompt: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openai, .deepseek: "sk-…"
        case .chatgpt: ""
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
        // GPT-6.1 Terra first, the owner's choice for the chat (ESP-174); Sol stays selectable.
        case .openai: [
            ChatModelChoice(id: "gpt-6.1-terra", name: "GPT-6.1 Terra"),
            ChatModelChoice(id: "gpt-6.1-sol", name: "GPT-6.1 Sol"),
        ]
        // The ChatGPT plan's models, as pi's openai-codex provider lists them; gpt-6.1-terra is also Poki
        // Agent's default on the Mac (agent/model-config.mjs).
        case .chatgpt: [
            ChatModelChoice(id: "gpt-6.1-terra", name: "ChatGPT GPT-6.1 Terra"),
            ChatModelChoice(id: "gpt-6.1-sol", name: "ChatGPT GPT-6.1 Sol"),
        ]
        // DeepSeek's current names (api-docs.deepseek.com, 2026-11-07); deepseek-chat is retired. V4 Pro
        // reads text only, so it does not see the screenshots.
        case .deepseek: [
            ChatModelChoice(id: "deepseek-flash", name: "DeepSeek V4.1 Flash"),
            ChatModelChoice(id: "deepseek-v4-pro", name: String(localized: "DeepSeek V4 Pro (no screenshots)")),
        ]
        // pi's google provider (Gemini API), both reading screenshots.
        case .gemini: [
            ChatModelChoice(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash"),
            ChatModelChoice(id: "gemini-4-argon", name: "Gemini 4 Argon"),
        ]
        default: []
        }
    }

    /// Where the owner creates a key.
    var keyHelp: String {
        switch self {
        case .anthropic: String(localized: "Create a key at console.anthropic.com, then paste it here.")
        case .openai: String(localized: "Create a key at platform.openai.com, then paste it here.")
        case .deepseek: String(localized: "Create a key at platform.deepseek.com, then paste it here.")
        case .gemini: String(localized: "Create a key at aistudio.google.com, then paste it here.")
        default: ""
        }
    }

    /// pi's model for one of `models`.
    func piModel(_ id: String) -> Model? {
        guard let piProvider else { return nil }
        if let model = getModel(provider: piProvider, modelId: id) { return model }
        // PiSwift's catalog (pi-mono, October 2026) lacks gpt-6.1-terra, which pi-ai 1.5.0 lists with the
        // same API and inputs as gpt-6.1-sol.
        guard self == .openai || self == .chatgpt, id == "gpt-6.1-terra", let sol = getModel(provider: piProvider, modelId: "gpt-6.1-sol"),
              var json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(sol))) as? [String: Any] else { return nil }
        json["id"] = id
        json["name"] = "GPT-6.1 Terra"
        return (try? JSONSerialization.data(withJSONObject: json)).flatMap { try? JSONDecoder().decode(Model.self, from: $0) }
    }
}

struct ChatModelChoice: Hashable, Identifiable, Sendable {
    var id: String
    var name: String
}

/// The owner's keys and the ChatGPT sign-in, in this iPhone's keychain (the relay key's service, one
/// account per provider). A key is only ever sent to its own provider. Nothing here prints or logs a key
/// or a token.
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

    /// Each provider's model: its first (Claude Sonnet 5.5, GPT-6.1 Terra) unless the owner picks another.
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

/// The credential pi sends for a provider: the key, or for ChatGPT the signed-in access token, refreshed
/// a minute before it runs out (pi's rule; `expires` is in milliseconds).
enum ModelCredential {
    static func apiKey(forPiProvider piProvider: String) async -> String? {
        guard let provider = ModelProvider.allCases.first(where: { $0.piProvider == piProvider }), let stored = ModelKeys.key(provider) else { return nil }
        guard provider.signsIn else { return stored }
        guard var credentials = ChatGPTAccount.decode(stored) else { return nil }
        if credentials.expires < Date().timeIntervalSince1970 * 1000 + 60_000, !credentials.refresh.isEmpty {
            guard let fresh = try? await refreshOpenAICodexToken(credentials.refresh) else { return nil }
            credentials = fresh
            try? ChatGPTAccount.save(credentials)
        }
        return credentials.access
    }
}
