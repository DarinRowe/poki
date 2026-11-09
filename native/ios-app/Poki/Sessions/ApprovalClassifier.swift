import Foundation
import PiSwiftAI

/// Testing only (Diagnostics → Approvals, off by default): a step PokiCore's rules would ask the owner
/// about is put to the chat model instead, out of sight. The model gets the step and what the owner
/// said in the chat and the live call, and answers allow or refuse; nothing is shown to tap. A refusal
/// stands until the owner says yes in the chat or the call: the agent asks, the owner answers, and the
/// next try is read with that answer in it. A tap anywhere is not taken as the owner's intent.
@MainActor
enum ApprovalClassifier {
    nonisolated static let onKey = "approvals.classifier"
    nonisolated static let levelKey = "approvals.classifier.level"
    /// Read once: PokiCore's rules are set up from it when Poki starts.
    nonisolated static let isOn = UserDefaults.standard.bool(forKey: onKey)
    static let deadline: Double = 12

    enum Level: String, CaseIterable, Identifiable {
        case strict, balanced, permissive
        var id: String { rawValue }
        var title: String {
            switch self {
            case .strict: String(localized: "Strict")
            case .balanced: String(localized: "Balanced")
            case .permissive: String(localized: "Permissive")
            }
        }
        static var saved: Level { Level(rawValue: UserDefaults.standard.string(forKey: levelKey) ?? "") ?? .balanced }
        var rule: String {
            switch self {
            case .strict: "ALLOW only if the owner explicitly asked for this exact action, or said yes when asked about it. Otherwise REFUSE."
            case .balanced: "ALLOW if the action directly serves what the owner asked for in this conversation. REFUSE if it is unrelated, goes further than the request, or the owner said no."
            case .permissive: "ALLOW unless the action is clearly unrelated to what the owner asked, or the owner said no or not to do it."
            }
        }
    }

    struct Verdict { let allowed: Bool; let reason: String }

    /// The latest decisions by approval id, for the chat's grey line.
    private(set) static var verdicts: [String: Verdict] = [:]

    static func decide(_ approval: PendingApproval, level: Level, voice: [VoiceLine]) async -> Verdict {
        let verdict = await ask(approval, level: level, voice: voice)
        verdicts[approval.id] = verdict
        if verdicts.count > 50 { verdicts.removeAll() }
        return verdict
    }

    private static func ask(_ approval: PendingApproval, level: Level, voice: [VoiceLine]) async -> Verdict {
        let provider = ModelKeys.selectedProvider
        guard provider.wired, ModelKeys.key(provider) != nil || provider == .custom,
              let model = provider.piModel(ModelKeys.selectedModel) else {
            return Verdict(allowed: false, reason: "no chat model to ask")
        }
        var said: [String] = AskPoki.chat?.ownerContext ?? []
        for line in voice.suffix(12) {
            switch line.role {
            case .you: said.append("Owner (live call): \(line.text)")
            case .poki: said.append("Assistant (live call): \(line.text)")
            default: break
            }
        }
        let conversation = said.isEmpty ? "(the owner has said nothing in Poki; the request came from an outside agent)" : said.suffix(20).joined(separator: "\n")
        let instructions = """
        You decide, fast, whether an AI agent driving the owner's iPhone may do one sensitive step. \
        \(level.rule) A yes from the owner to a question about this step counts as asking for it. \
        Reply with one line: ALLOW or REFUSE, a colon, and at most ten words why.
        """
        let prompt = """
        Step: \(approval.summary) in \(approval.app) (\(approval.reason)).
        Conversation, oldest first:
        \(String(conversation.suffix(4000)))
        """
        let loop = PiLoop(provider: provider, model: model, tools: []) { _ in
            .init(text: "No tools.", jpeg: nil, isError: true)
        }
        // The first of the model's reply and the deadline answers; a late reply is dropped.
        let reply: String? = await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            let once = Once(done)
            let run = Task { @MainActor in
                var first: String?
                _ = await loop.run(prompt, instructions: instructions, maxTurns: 1) { text in if first == nil { first = text } }
                once.finish(first)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(deadline))
                run.cancel()
                once.finish(nil)
            }
        }
        guard let text = reply?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return Verdict(allowed: false, reason: "the model did not answer in time")
        }
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        let allowed = line.uppercased().hasPrefix("ALLOW")
        let why = line.split(separator: ":", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return Verdict(allowed: allowed, reason: why.isEmpty ? (allowed ? "allowed" : "refused") : String(why.prefix(120)))
    }

}

/// Resumes a continuation once.
@MainActor
private final class Once {
    private var continuation: CheckedContinuation<String?, Never>?
    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }
    func finish(_ value: String?) { continuation?.resume(returning: value); continuation = nil }
}
