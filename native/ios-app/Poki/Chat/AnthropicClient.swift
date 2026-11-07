import Foundation

/// The Claude API's Messages endpoint over plain HTTPS (Swift has no official Anthropic SDK), with the
/// owner's key. Requests are built and read as JSON objects so the model's content blocks go back
/// exactly as they came, which keeps the conversation append-only.
struct AnthropicClient: Sendable {
    let key: String
    let model: String

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2026-10-21"

    struct Failure: LocalizedError {
        var status: Int
        var message: String
        var errorDescription: String? {
            switch status {
            case 401: String(localized: "Anthropic did not accept the key. Check it in Poki › Model.")
            case 403: String(localized: "This Anthropic key can’t use \(ModelKeys.selectedModelName).")
            case 429: String(localized: "Anthropic says the key has hit its rate limit. Try again in a minute.")
            case 529: String(localized: "Anthropic is overloaded right now. Try again in a minute.")
            case 0: message
            default: String(localized: "Anthropic answered \(status): \(message)")
            }
        }
    }

    /// One Messages request. `system` is cached with the tools (they never change during a chat), so
    /// every step of a task after the first reads them from the cache.
    func send(system: String, tools: [[String: Any]], messages: [[String: Any]]) async throws -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "tools": tools,
            "messages": messages,
            "cache_control": ["type": "ephemeral"],
            // Many steps with tools: medium effort is the guide's starting point for this kind of work.
            "output_config": ["effort": "medium"],
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        // A declined request is run again on a suitable model by the API itself (Sonnet 5.5 and Opus 5.5;
        // Haiku has no server-side fallback).
        if !model.hasPrefix("claude-haiku") {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(status: 0, message: String(localized: "Poki could not reach Anthropic: \(error.localizedDescription)"))
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let json else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? String(decoding: data.prefix(200), as: UTF8.self)
            throw Failure(status: status == 0 ? -1 : status, message: message)
        }
        return json
    }

    /// PokiCore's tools in the Messages API's form.
    static func tools(fromCatalog catalog: String) -> [[String: Any]] {
        guard let data = catalog.data(using: .utf8), let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list.compactMap { tool in
            guard let name = tool["name"] as? String, let description = tool["description"] as? String, let schema = tool["inputSchema"] else { return nil }
            return ["name": name, "description": description, "input_schema": schema]
        }
    }
}
