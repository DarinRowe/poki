import Foundation
import PokiCore

/// `ask_poki`: an outside agent (Claude, Codex, any MCP client) hands a whole task to Poki's own agent,
/// which runs it on this iPhone with the owner's model (their key or ChatGPT sign-in) and answers with
/// the result. The agent can still call look and do itself; this is the other way of working. It is
/// listed only once the owner has set up a model, and it waits while the owner's own chat runs a task.
@MainActor
enum AskPoki {
    static let schema = #"{"type":"object","properties":{"task":{"type":"string","description":"What to do on the iPhone, in plain words, as you would ask a person. Include every detail Poki needs (names, text to type); Poki cannot ask you back."}},"required":["task"],"additionalProperties":false}"#

    static let description = "Hand a whole task to Poki, the agent on this iPhone: it looks, taps and types by itself with the owner's own model and approvals, then answers with the result (and what it said). Use it for a self-contained phone task when you do not need to see each step; use look and do when you want to drive the phone yourself. One task at a time; it can take a few minutes."

    private static weak var app: AppModel?
    /// The owner's chat (the Debug probe's `chat` mode sends to it).
    private(set) static weak var chat: ChatModel?
    private static var running: [String: ChatModel] = [:]

    static func install(app: AppModel, chat: ChatModel) {
        self.app = app
        self.chat = chat
        refresh()
        NotificationCenter.default.addObserver(forName: ModelKeys.changed, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { refresh() }
        }
    }

    /// Listed when the chosen model is set up; unlisted otherwise.
    static func refresh() {
        guard let app else { return }
        guard ModelKeys.hasUsableKey || ModelKeys.selectedProvider == .custom && !ModelKeys.customURL.isEmpty else { app.setHostTools([]); return }
        app.setHostTools([HostTool(name: "ask_poki", description: description, schemaJSON: schema) { arguments, session in
            await run(arguments: arguments, session: session)
        }])
    }

    static func run(arguments: String, session: String?) async -> PokiCore.ToolAnswer {
        let args = (arguments.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        guard let task = (args["task"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !task.isEmpty else {
            return PokiCore.ToolAnswer(text: "error: task is empty; nothing was done", jpeg: nil, isError: true)
        }
        guard let app else { return PokiCore.ToolAnswer(text: "error: Poki is not ready", jpeg: nil, isError: true) }
        if chat?.running == true || ChatModel.delegatedBusy != nil {
            return PokiCore.ToolAnswer(text: "busy: Poki's agent is already working on a task on this iPhone; nothing was done. Try again in a minute, or use look and do.", jpeg: nil, isError: true)
        }
        let store = SessionStore.shared
        let requester = store.client(of: session)
        let id = store.handoffID(for: session)
        let handoff = ChatModel(app: app, kind: .handoff, requester: requester, sessionID: id)
        running[id] = handoff
        defer { running[id] = nil }
        AppLog.shared.add("chat", "\(requester) handed a task to Poki (\(task.count) characters)")
        let answer = await handoff.runDelegated(task)
        return PokiCore.ToolAnswer(text: answer.text, jpeg: nil, isError: false)
    }

    /// The hand-off running in this session, for its live transcript.
    static func live(_ id: String) -> ChatModel? { running[id] }
}
