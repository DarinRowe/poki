import SwiftUI

/// Who is calling Poki: an outside agent's provider logo (Poki/ProviderIcons, in both asset catalogs)
/// on the provider's colour, or its initials on grey. One look for the sessions list, the Activity Log,
/// the connectors and the Live Activity.
enum Caller {
    /// The provider logo for an agent's name ("Claude Code", "Codex", "Gemini CLI").
    static func logo(_ name: String) -> String? {
        let n = name.lowercased()
        if n.contains("claude") || n.contains("anthropic") { return "Provider-anthropic" }
        if n.contains("codex") || n.contains("chatgpt") || n.contains("openai") { return "Provider-openai" }
        if n.contains("gemini") || n.contains("google") { return "Provider-googlegemini" }
        if n.contains("deepseek") { return "Provider-deepseek" }
        if n.contains("openrouter") { return "Provider-openrouter" }
        return nil
    }

    /// The provider's colour, a calm grey otherwise.
    static func tint(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("claude") || n.contains("anthropic") { return Color(hex: 0xD97757) }
        if n.contains("codex") || n.contains("chatgpt") || n.contains("openai") { return Color(hex: 0x10A37F) }
        if n.contains("gemini") || n.contains("google") { return Color(hex: 0x4285F4) }
        if n.contains("deepseek") { return Color(hex: 0x4D6BFE) }
        if n.contains("cursor") { return Color(hex: 0x111111) }
        return Color(hex: 0x8E8E93)
    }

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
