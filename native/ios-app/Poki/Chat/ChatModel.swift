import Foundation
import PokiCore
import SwiftUI

/// One thing in the conversation, in the order it is drawn.
struct ChatEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        /// "Today 9:41 AM" above a conversation.
        case time(Date)
        case you(String, delivered: Bool)
        case poki(String)
        /// The steps of a task, in one Poki bubble.
        case plan([PlanStep])
        /// One grey line, centred: waiting for, or the result of, an approval.
        case note(ChatNote)
    }
    let id: UUID
    var kind: Kind
    init(_ kind: Kind) { id = UUID(); self.kind = kind }

    var isPoki: Bool { switch kind { case .poki, .plan: true; default: false } }
}

struct PlanStep: Identifiable, Equatable {
    enum State: Equatable { case current, waiting, done, failed }
    let id: UUID
    var text: String
    var state: State
    init(_ text: String, state: State = .current) { id = UUID(); self.text = text; self.state = state }
}

enum ChatNote: Equatable {
    case waiting
    case approved(Date)
    case declined
    case expired
    case problem(String)
}

/// The chat: the owner's messages, Poki's answers and the steps it takes, and the model loop that runs
/// on this iPhone with the owner's own key (ESP-174). Its tools are PokiCore's `look` and `do`, with the
/// same approval rules as an agent on a computer.
@MainActor
@Observable
final class ChatModel {
    private(set) var entries: [ChatEntry] = []
    private(set) var running = false
    /// A board's sample conversation, for screenshots.
    let isSample = UserDefaults.standard.string(forKey: "pokiChat") != nil
    private let app: AppModel
    /// The Messages API conversation, append-only: every block the model sent goes back unchanged.
    private var history: [[String: Any]] = []
    private var task: Task<Void, Never>?
    private var stopAsked = false
    /// The plan bubble of the task under way.
    private var planID: UUID?
    private var noteID: UUID?

    /// A task stops after this many model turns: a loop that goes nowhere still ends.
    static let maxTurns = 60

    init(app: AppModel) {
        self.app = app
        if let scene = UserDefaults.standard.string(forKey: "pokiChat") { loadSample(scene) } else { greet() }
        app.onShellEvent = { [weak self] event in self?.observe(event) }
    }

    private func greet() {
        entries = [ChatEntry(.time(Date())),
                   ChatEntry(.poki(String(localized: "Hi, I’m Poki. Tell me what to do on this iPhone."))),
                   ChatEntry(.poki(String(localized: "I’ll ask before anything you can’t undo.")))]
    }

    func newConversation() {
        stop()
        history = []
        planID = nil; noteID = nil
        greet()
    }

    // MARK: Sending

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }
        let you = ChatEntry(.you(text, delivered: false))
        entries.append(you)
        guard ModelKeys.selectedProvider.wired, let key = ModelKeys.key(ModelKeys.selectedProvider) else {
            add(.poki(String(localized: "Add your Anthropic key first: tap my picture, then Model.")))
            return
        }
        history.append(["role": "user", "content": text])
        running = true
        stopAsked = false
        planID = nil; noteID = nil
        let client = AnthropicClient(key: key, model: ModelKeys.selectedModel)
        task = Task { [weak self] in
            await self?.run(client, delivered: you.id)
            self?.running = false
        }
    }

    /// Ends the task after the step under way: nothing more is sent to the phone or the model.
    func stop() {
        guard running else { return }
        stopAsked = true
        task?.cancel()
    }

    private func run(_ client: AnthropicClient, delivered youID: UUID) async {
        let tools = AnthropicClient.tools(fromCatalog: PokiCore.toolCatalogJSON)
        for _ in 0..<Self.maxTurns {
            let response: [String: Any]
            do {
                response = try await client.send(system: Self.system, tools: tools, messages: history)
            } catch is CancellationError {
                return
            } catch {
                if stopAsked { return }
                add(.note(.problem(error.localizedDescription)))
                // The question is not in the conversation the model saw; it goes again with the next message.
                if history.last?["role"] as? String == "user", history.last?["content"] is String { history.removeLast() }
                return
            }
            markDelivered(youID)
            let content = response["content"] as? [[String: Any]] ?? []
            history.append(["role": "assistant", "content": content])
            for block in content where block["type"] as? String == "text" {
                if let text = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { add(.poki(text)) }
            }
            let stop = response["stop_reason"] as? String
            switch stop {
            case "tool_use":
                var results: [[String: Any]] = []
                for block in content where block["type"] as? String == "tool_use" {
                    let id = block["id"] as? String ?? ""
                    if stopAsked || Task.isCancelled {
                        results.append(["type": "tool_result", "tool_use_id": id, "content": "The owner stopped the task in Poki; nothing was sent.", "is_error": true])
                        continue
                    }
                    let name = block["name"] as? String ?? ""
                    let input = block["input"] ?? [String: Any]()
                    let arguments = (try? JSONSerialization.data(withJSONObject: input)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                    let answer = await app.runTool(name, arguments: arguments)
                    var parts: [[String: Any]] = [["type": "text", "text": answer.text]]
                    if let jpeg = answer.jpeg {
                        parts.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
                    }
                    results.append(["type": "tool_result", "tool_use_id": id, "content": parts, "is_error": answer.isError])
                }
                history.append(["role": "user", "content": results])
                if stopAsked || Task.isCancelled { finishPlan(); add(.poki(String(localized: "Stopped."))); return }
            case "pause_turn":
                continue
            case "refusal":
                finishPlan()
                add(.poki(String(localized: "Claude declined this request.")))
                return
            case "max_tokens":
                finishPlan()
                add(.note(.problem(String(localized: "The answer was cut off."))))
                return
            default:
                finishPlan()
                return
            }
        }
        finishPlan()
        add(.poki(String(localized: "I stopped after \(Self.maxTurns) steps. Tell me how to go on.")))
    }

    static let system = """
    You are Poki, running inside the Poki app on the owner's iPhone. The owner types what they want in Poki's chat and you do it on this iPhone with the look and do tools: they read the screen and tap and type, like a person would.

    \(PokiCore.toolInstructions)

    How to work:
    - Poki is the app in front when a task starts. Leave it first with a launch action (the app's bundle id, e.g. com.apple.mobilenotes for Notes, com.apple.MobileSMS for Messages) or the home button.
    - Before the first action, say what you will do in one short sentence ("On it. Opening Notes.").
    - When do answers approval_required, the owner is approving in the Dynamic Island; do waits for it. Send the actions it lists again once approved, and do not try to approve anything yourself.
    - When the task is done, answer in one or two short sentences. Reply in the language the owner wrote in.
    """

    // MARK: Steps and approvals from PokiCore

    private func observe(_ event: ShellEvent) {
        guard running else { return }
        switch event {
        case .toolStarted(let name, let summary):
            guard name == "do" else { return }
            updatePlan { steps in
                for i in steps.indices where steps[i].state == .current { steps[i].state = .done }
                steps.append(PlanStep(ActivityWords.label(summary)))
            }
        case .toolFinished(let summary, let delivery, _, _):
            guard summary != "Look at the screen" else { return }
            let failed = delivery.hasPrefix("failed")
            let waiting = delivery.contains("approval_required")
            updatePlan { steps in
                guard let i = steps.lastIndex(where: { $0.state == .current || $0.state == .waiting }) else { return }
                steps[i].state = failed ? .failed : waiting ? .current : .done
            }
        case .approvalRequested(let approval):
            updatePlan { steps in
                if let i = steps.lastIndex(where: { $0.state == .current }) {
                    steps[i].state = .waiting
                } else {
                    steps.append(PlanStep(approval.summary, state: .waiting))
                }
            }
            setNote(.waiting)
        case .approvalEnded(_, let approved):
            switch approved {
            case true?: setNote(.approved(Date()))
            case false?: setNote(.declined)
            case nil: setNote(.expired)
            }
            updatePlan { steps in
                for i in steps.indices where steps[i].state == .waiting { steps[i].state = approved == true ? .current : .failed }
            }
        case .relay: break
        }
    }

    private func updatePlan(_ change: (inout [PlanStep]) -> Void) {
        if let id = planID, let i = entries.firstIndex(where: { $0.id == id }), case .plan(var steps) = entries[i].kind {
            change(&steps)
            entries[i].kind = .plan(steps)
            return
        }
        var steps: [PlanStep] = []
        change(&steps)
        guard !steps.isEmpty else { return }
        let entry = ChatEntry(.plan(steps))
        planID = entry.id
        entries.append(entry)
    }

    /// The task ended: a step still marked current was the last one done.
    private func finishPlan() {
        updatePlan { steps in for i in steps.indices where steps[i].state == .current { steps[i].state = .done } }
    }

    private func setNote(_ note: ChatNote) {
        if let id = noteID, let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].kind = .note(note)
        } else {
            let entry = ChatEntry(.note(note))
            noteID = entry.id
            entries.append(entry)
        }
    }

    private func add(_ kind: ChatEntry.Kind) { entries.append(ChatEntry(kind)) }

    private func markDelivered(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), case .you(let text, false) = entries[i].kind else { return }
        entries[i].kind = .you(text, delivered: true)
    }

    // MARK: Screenshots

    /// `-pokiChat empty|working|approved`: the ESP-171 boards' conversations, for the build's
    /// screenshots only. Nothing is sent.
    private func loadSample(_ scene: String) {
        let start = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
        greet()
        entries[0] = ChatEntry(.time(start))
        guard scene != "empty" else { return }
        let you = String(localized: "Text Mom “On my way”")
        if scene == "working" {
            entries = [ChatEntry(.time(start)),
                       ChatEntry(.poki(String(localized: "Hi, I’m Poki. Tell me what to do on this iPhone."))),
                       ChatEntry(.you(you, delivered: true)),
                       ChatEntry(.poki(String(localized: "On it. Opening Messages."))),
                       ChatEntry(.plan([PlanStep(String(localized: "Open Messages"), state: .done),
                                        PlanStep(String(localized: "Open the chat with Mom"), state: .done),
                                        PlanStep(String(localized: "Type “On my way”"), state: .done),
                                        PlanStep(String(localized: "Tap Send"), state: .waiting)])),
                       ChatEntry(.note(.waiting))]
        } else {
            entries = [ChatEntry(.time(start)),
                       ChatEntry(.you(you, delivered: true)),
                       ChatEntry(.plan([PlanStep(String(localized: "Open Messages"), state: .done),
                                        PlanStep(String(localized: "Open the chat with Mom"), state: .done),
                                        PlanStep(String(localized: "Type “On my way”"), state: .done),
                                        PlanStep(String(localized: "Tap Send"), state: .done)])),
                       ChatEntry(.note(.approved(start.addingTimeInterval(60)))),
                       ChatEntry(.poki(String(localized: "Sent. Mom has it. Anything else?")))]
        }
    }
}
