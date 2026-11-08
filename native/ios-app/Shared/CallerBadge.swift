import SwiftUI

/// Who is calling Poki: an outside agent's provider logo (Poki/ProviderIcons, in both asset catalogs)
/// on the provider's colour, or its initials on grey. One look for the sessions list, the Activity Log,
/// the connectors and the Live Activity.
enum Caller {
    /// The provider logo for an agent's name ("Claude Code", "Codex", "Gemini CLI").
    /// Each known agent, in match order (more specific names first: "cursor-vscode" is Cursor), with its
    /// logo in the asset catalog (nil: initials) and its colour.
    private static let known: [(match: [String], logo: String?, tint: UInt32)] = [
        (["claude", "anthropic"], "Provider-anthropic", 0xD97757),
        (["cursor"], "Provider-cursor", 0x111111),
        (["windsurf", "codeium"], "Provider-windsurf", 0x0B100F),
        (["cline", "roo code", "roo-code", "roocode"], "Provider-cline", 0x111111),
        (["codex", "chatgpt", "openai"], "Provider-openai", 0x10A37F),
        (["github", "copilot", "visual studio code", "vscode", "vs code"], "Provider-githubcopilot", 0x24292F),
        (["microsoft"], "Provider-copilot", 0x0078D4),
        (["gemini", "google"], "Provider-googlegemini", 0x4285F4),
        (["deepseek"], "Provider-deepseek", 0x4D6BFE),
        (["openrouter"], "Provider-openrouter", 0x6566F1),
        (["meta"], "Provider-metaai", 0x0866FF),
        (["perplexity"], "Provider-perplexity", 0x1FB8CD),
        (["mistral", "le chat", "le-chat", "lechat"], "Provider-mistral", 0xFA520F),
        (["grok", "xai"], "Provider-grok", 0x111111),
        (["raycast"], "Provider-raycast", 0xFF6363),
        (["goose"], "Provider-goose", 0x111111),
        (["manus"], "Provider-manus", 0x111111),
        (["kimi", "moonshot"], "Provider-kimi", 0x111111),
        (["qwen", "tongyi", "alibaba"], "Provider-qwen", 0x615CED),
        (["lm studio", "lmstudio"], "Provider-lmstudio", 0x4338CA),
        (["ollama"], "Provider-ollama", 0x111111),
        (["hugging", "hf-mcp"], "Provider-huggingface", 0xFFB000),
        (["n8n"], "Provider-n8n", 0xEA4B71),
        (["zapier"], "Provider-zapier", 0xFF4F00),
        (["openclaw"], "Provider-openclaw", 0xE5484D),
        (["poke"], nil, 0x111111),
        (["zed"], nil, 0x084CCF),
    ]

    private static func entry(_ name: String) -> (match: [String], logo: String?, tint: UInt32)? {
        let n = name.lowercased()
        return known.first { $0.match.contains { n.contains($0) } }
    }

    static func logo(_ name: String) -> String? { entry(name)?.logo }

    /// The provider's colour, a calm grey otherwise.
    static func tint(_ name: String) -> Color { Color(hex: entry(name)?.tint ?? 0x8E8E93) }

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        return String(name.prefix(1)).uppercased()
    }
}

/// The caller's round badge.
struct CallerBadge: View {
    var name: String
    var size: CGFloat
    var body: some View {
        Group {
            if let logo = Caller.logo(name) {
                Image(logo).resizable().renderingMode(.template).scaledToFit()
                    .frame(width: size * 0.54, height: size * 0.54)
            } else {
                Text(verbatim: Caller.initials(name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Caller.tint(name), in: .circle)
        .accessibilityLabel(Text(verbatim: name))
    }
}
