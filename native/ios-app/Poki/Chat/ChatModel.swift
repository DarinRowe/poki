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
/// on this iPhone with the owner's own key (ESP-174). Its prompt and tools are the Mac Poki Agent's
/// (`Harness`): PokiCore's `look` and `do`, with the same approval rules as an agent on a computer, and
/// the agent's `report_plan` and `finish_task`, which drive the plan bubble.
@MainActor
@Observable
final class ChatModel {
    private(set) var entries: [ChatEntry] = []
    private(set) var running = false
    /// A board's sample conversation, for screenshots.
    let isSample = UserDefaults.standard.string(forKey: "pokiChat") != nil
    private let app: AppModel
    /// The model's side of the conversation: pi's loop (ESP-177), or for Anthropic and OpenAI, unless
    /// `-chatEngine pi`, the provider's own API in its own form.
    private var loop: PiLoop?
    private var client: ModelClient?
    /// The plan the model published with report_plan; the bubble shows its steps up to the current one.
    private var modelPlan: [String]?
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
        loop = nil
        client = nil
        planID = nil; noteID = nil; modelPlan = nil
        greet()
    }

    // MARK: Sending

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }
        let you = ChatEntry(.you(text, delivered: false))
        entries.append(you)
        let provider = ModelKeys.selectedProvider
        guard provider.wired, let key = ModelKeys.key(provider) else {
            add(.poki(provider.signsIn ? String(localized: "Sign in to ChatGPT first: tap my picture, then Model.")
                                       : String(localized: "Add a model key first: tap my picture, then Model.")))
            return
        }
        let model = ModelKeys.selectedModel
        running = true
        stopAsked = false
        planID = nil; noteID = nil; modelPlan = nil
        if Self.direct, provider == .anthropic || provider == .openai {
            // Another model starts a new conversation on the model's side; the chat on screen stays.
            if client?.signature != "\(provider.rawValue)/\(model)" {
                client = provider == .openai ? OpenAIClient(key: key, model: model) : AnthropicClient(key: key, model: model)
            }
            guard let client else { return }
            client.say(text)
            task = Task { [weak self] in
                await self?.run(client, delivered: you.id)
                self?.running = false
            }
            return
        }
        guard let piModel = provider.piModel(model) else {
            running = false
            add(.note(.problem(String(localized: "pi has no model \(model) for \(provider.name)."))))
            return
        }
        // Another model starts a new loop that carries the conversation over.
        if loop?.provider != provider || loop?.model.id != piModel.id {
            loop = PiLoop(provider: provider, model: piModel, instructions: Harness.instructions, tools: Harness.tools,
                          carrying: loop?.messages ?? []) { [weak self] call in
                guard let self else { return PokiCore.ToolAnswer(text: "Task stopped. Action not executed.", jpeg: nil, isError: true) }
                return await self.perform(call)
            }
        }
        guard let loop else { return }
        task = Task { [weak self] in
            let outcome = await loop.run(text, maxTurns: Self.maxTurns) { text in
                self?.markDelivered(you.id)
                self?.add(.poki(text))
            }
            self?.ended(outcome, delivered: you.id)
            self?.running = false
        }
    }

    /// Anthropic and OpenAI keep their own APIs, the phone acceptance path, until pi has run with their
    /// keys; `-chatEngine pi` sends them through pi too. ChatGPT, DeepSeek and Gemini always run on pi.
    private static var direct: Bool { UserDefaults.standard.string(forKey: "chatEngine") != "pi" }

    private func ended(_ outcome: PiLoop.Outcome, delivered youID: UUID) {
        finishPlan()
        switch outcome {
        case .done: markDelivered(youID)
        case .stopped: add(.poki(String(localized: "Stopped.")))
        case .overTurns: add(.poki(String(localized: "I stopped after \(Self.maxTurns) steps. Tell me how to go on.")))
        case .failed(let words): add(.note(.problem(words)))
        }
    }

    /// Ends the task after the step under way: nothing more is sent to the phone or the model.
    func stop() {
        guard running else { return }
        stopAsked = true
        loop?.stop()
        task?.cancel()
    }

    private func run(_ client: ModelClient, delivered youID: UUID) async {
        for _ in 0..<Self.maxTurns {
            let turn: ModelTurn
            do {
                turn = try await client.next(instructions: Harness.instructions, tools: Harness.tools)
            } catch {
                client.forgetUnansweredQuestion()
                if stopAsked || Task.isCancelled { return }
                add(.note(.problem(error.localizedDescription)))
                return
            }
            markDelivered(youID)
            for text in turn.texts { add(.poki(text)) }
            switch turn.ending {
            case .tools:
                for call in turn.calls {
                    if stopAsked || Task.isCancelled {
                        client.answer(call, PokiCore.ToolAnswer(text: "Task stopped. Action not executed.", jpeg: nil, isError: true))
                        continue
                    }
                    client.answer(call, await perform(call))
                }
                if stopAsked || Task.isCancelled { finishPlan(); add(.poki(String(localized: "Stopped."))); return }
            case .again:
                continue
            case .refused:
                finishPlan()
                add(.poki(String(localized: "The model declined this request.")))
                return
            case .cutOff:
                finishPlan()
                add(.note(.problem(String(localized: "The answer was cut off."))))
                return
            case .done:
                // A reply without tools ends the turn, as a chat does: the model may be asking the owner something.
                finishPlan()
                return
            }
        }
        finishPlan()
        add(.poki(String(localized: "I stopped after \(Self.maxTurns) steps. Tell me how to go on.")))
    }

    /// The phone's tools go to PokiCore; the harness's two are answered here, as task-runner.mjs answers them.
    private func perform(_ call: ToolCall) async -> PokiCore.ToolAnswer {
        let args = (call.arguments.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] ?? [:]
        switch call.name {
        case "report_plan":
            guard let steps = args["steps"] as? [String], (1...8).contains(steps.count), let current = args["currentStep"] as? Int, (1...steps.count).contains(current) else {
                return PokiCore.ToolAnswer(text: Harness.invalidPlan, jpeg: nil, isError: true)
            }
            showPlan(steps, current: current)
            return PokiCore.ToolAnswer(text: Harness.planPublished, jpeg: nil, isError: false)
        case "finish_task":
            guard let success = args["success"] as? Bool, args["summary"] is String else {
                return PokiCore.ToolAnswer(text: Harness.invalidResult, jpeg: nil, isError: true)
            }
            updatePlan { steps in
                for i in steps.indices where steps[i].state == .current || steps[i].state == .waiting { steps[i].state = success ? .done : .failed }
            }
            return PokiCore.ToolAnswer(text: Harness.resultRecorded, jpeg: nil, isError: false)
        default:
            return await app.runTool(call.name, arguments: call.arguments)
        }
    }

    /// The bubble shows the model's steps up to the current one: those before it done, it under way. A step
    /// appears when the model reaches it, as the board draws them.
    private func showPlan(_ plan: [String], current: Int) {
        modelPlan = plan
        updatePlan { steps in
            if steps.count > current { steps.removeLast(steps.count - current) }
            for i in 0..<current {
                let state: PlanStep.State = i < current - 1 ? .done : (steps.indices.contains(i) && steps[i].state == .waiting ? .waiting : .current)
                if steps.indices.contains(i) { steps[i].text = plan[i]; steps[i].state = state } else { steps.append(PlanStep(plan[i], state: state)) }
            }
        }
    }

    // MARK: Steps and approvals from PokiCore

    private func observe(_ event: ShellEvent) {
        guard running else { return }
        switch event {
        case .toolStarted(let name, let summary):
            guard name == "do", modelPlan == nil else { return }
            updatePlan { steps in
                for i in steps.indices where steps[i].state == .current { steps[i].state = .done }
                steps.append(PlanStep(ActivityWords.label(summary)))
            }
        case .toolFinished(let summary, let delivery, _, _):
            guard summary != "Look at the screen", modelPlan == nil else { return }
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
