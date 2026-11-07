import Foundation
import Observation
import UIKit

/// The voice bridge on the person's Mac (`bin/voice-bridge.mjs`): it hands out short-lived OpenAI
/// Realtime credentials, so the phone never holds an API key, and runs the voice tools that move the
/// phone through the Mac's Poki MCP. Entered once, like the relay address.
struct VoiceBridge: Equatable {
    /// http://<Mac>:47830/voice/<secret>
    let base: URL

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        let parts = url.path().split(separator: "/")
        guard parts.count == 2, parts[0] == "voice", parts[1].count >= 16 else { return nil }
        base = url
    }

    var display: String { "\(base.host() ?? "")\(base.port.map { ":\($0)" } ?? "")" }

    static var saved: VoiceBridge? {
        get { UserDefaults.standard.string(forKey: "voiceBridge").flatMap(VoiceBridge.init) }
        set { UserDefaults.standard.set(newValue?.base.absoluteString, forKey: "voiceBridge") }
    }

    struct Token: Decodable { let value: String; let model: String; let local_tools: [String] }
    struct ToolResult: Decodable { let state: String; let output: String; let replayed: Bool }

    func token() async throws -> Token {
        let (data, response) = try await URLSession.shared.data(from: base.appending(path: "token"))
        try Self.check(response, data)
        return try JSONDecoder().decode(Token.self, from: data)
    }

    func run(callID: String, name: String, arguments: String) async throws -> ToolResult {
        var request = URLRequest(url: base.appending(path: "tool"), timeoutInterval: 75)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) ?? [String: Any]()
        request.httpBody = try JSONSerialization.data(withJSONObject: ["call_id": callID, "name": name, "arguments": args])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(ToolResult.self, from: data)
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return }
        let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw VoiceError.bridge(http.statusCode, reason ?? "no reason given")
    }
}

enum VoiceError: LocalizedError {
    case bridge(Int, String)
    case realtime(Int, String)
    case noBridge
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .bridge(404, _): "The voice bridge doesn't know this address. Copy it again from the Mac."
        case .bridge(let code, let reason): "The voice bridge answered \(code): \(reason)"
        case .realtime(let code, let reason): "OpenAI answered \(code): \(reason)"
        case .noBridge: "Enter the voice bridge address from your Mac first."
        case .timeout(let what): "\(what) took too long."
        }
    }
}

/// One function call the model asked for. Keyed by the model's call_id, it runs at most once, whatever
/// happens to the connection: a call outlives the session that asked for it, and a new session is told
/// how it ended instead of asking for it again.
struct VoiceCall: Identifiable, Equatable {
    enum State: Equatable { case running, done, failed }
    let id: String
    let name: String
    let arguments: String
    /// The connection that asked for it. Only that connection can take a function_call_output for it.
    let session: Int
    var state = State.running
    var output = ""
    /// The model has the result (as a function_call_output, or in a reconnect note).
    var delivered = false
    let started = Date()
    var finished: Date?
}

struct VoiceLine: Identifiable, Equatable {
    enum Role { case you, poki, tool, note }
    let id = UUID()
    let role: Role
    let text: String
}

enum VoicePhase: Equatable {
    case off, connecting, listening, hearing, thinking, speaking
    case lost(String)

    var label: String {
        switch self {
        case .off: "Off"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .hearing: "Hearing you"
        case .thinking: "Working"
        case .speaking: "Speaking"
        case .lost(let why): why
        }
    }
}

/// Talking to Poki: one Realtime session at a time over WebRTC, the calls it asked for, and what was
/// said. The model hears the microphone and speaks through the speaker; `get_ios_version` is answered
/// here, the other tools by the voice bridge.
@MainActor
@Observable
final class VoiceModel {
    private(set) var bridge = VoiceBridge.saved
    private(set) var phase = VoicePhase.off
    private(set) var lines: [VoiceLine] = []
    private(set) var calls: [VoiceCall] = []
    /// Model audio off: for silent test runs. Speech is still transcribed into `lines`.
    var muted = false { didSet { link?.setRemoteVolume(muted ? 0 : 1) } }
    /// The last measured turn: from the end of speech to the first audio of the answer that carries a tool result.
    private(set) var lastTurnMS: Int?

    private var link: VoiceLink?
    /// session.created arrived on the current link: it takes events now.
    private var ready = false
    private var session = 0
    private var activeResponse: String?
    private var wantsResponse = false
    private var localTools: Set<String> = []
    private var speechStopped: Date?
    private var resultDelivered: Date?
    private let log = AppLog.shared

    var isOn: Bool { link != nil }

    func setBridge(_ text: String) -> Bool {
        guard let bridge = VoiceBridge(text) else { return false }
        self.bridge = bridge
        VoiceBridge.saved = bridge
        return true
    }

    /// `poki://voice?bridge=<address>&start=1&muted=1`
    func open(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let address = value("bridge") { log.add("voice", setBridge(address) ? "bridge set from a link" : "the link's bridge address was not valid") }
        if value("muted") == "1" { muted = true }
        if value("start") == "1", !isOn { Task { await start() } }
    }

    func start() async {
        guard link == nil else { return }
        guard let bridge else { phase = .lost(VoiceError.noBridge.localizedDescription); return }
        phase = .connecting
        session += 1
        let number = session
        do {
            let token = try await bridge.token()
            localTools = Set(token.local_tools)
            let link = VoiceLink(onEvent: { [weak self] event in self?.handle(event, session: number) },
                                 onClosed: { [weak self] reason in self?.closed(reason, session: number) })
            self.link = link
            try await link.connect(secret: token.value)
            link.setRemoteVolume(muted ? 0 : 1)
            log.add("voice", "connected (\(token.model)), session \(number)")
        } catch {
            link?.close()
            link = nil
            phase = .lost(error.localizedDescription)
            log.add("voice", "could not connect: \(error.localizedDescription)")
        }
    }

    /// Ends the conversation. Calls already running keep running; the next session hears how they ended.
    func stop() {
        link?.close()
        link = nil
        ready = false
        activeResponse = nil
        wantsResponse = false
        phase = .off
    }

    /// Stops Poki's voice reply. Anything running on the phone keeps running.
    func stopTalking() {
        guard let link else { return }
        if activeResponse != nil { link.send(["type": "response.cancel"]) }
        link.send(["type": "output_audio_buffer.clear"])
    }

    /// Recorded speech instead of the microphone, for test runs: 24 kHz mono PCM16, sent as one user turn.
    func say(pcm24k: Data) {
        guard let link, ready else { return }
        link.send(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": [["type": "input_audio", "audio": pcm24k.base64EncodedString()]]]])
        speechStopped = Date()
        wantsResponse = true
        flush()
    }

    private func closed(_ reason: String, session number: Int) {
        guard number == session, link != nil else { return }
        link?.close()
        link = nil
        ready = false
        activeResponse = nil
        wantsResponse = false
        phase = .lost("Connection lost")
        lines.append(VoiceLine(role: .note, text: "Connection lost (\(reason)). Nothing is sent again; reconnect to hear how running steps ended."))
        log.add("voice", "connection lost: \(reason)")
    }

    // MARK: Events

    private func handle(_ event: [String: Any], session number: Int) {
        guard number == session, let link, let type = event["type"] as? String else { return }
        switch type {
        case "session.created":
            ready = true
            phase = .listening
            catchUp(link)
        case "input_audio_buffer.speech_started":
            phase = .hearing
        case "input_audio_buffer.speech_stopped":
            phase = .thinking
            speechStopped = Date()
            resultDelivered = nil
        case "conversation.item.input_audio_transcription.completed":
            if let text = event["transcript"] as? String, !text.isEmpty { lines.append(VoiceLine(role: .you, text: text.trimmingCharacters(in: .whitespacesAndNewlines))) }
        case "response.created":
            activeResponse = (event["response"] as? [String: Any])?["id"] as? String
        case "response.done":
            let id = (event["response"] as? [String: Any])?["id"] as? String
            if id == activeResponse { activeResponse = nil }
            flush()
        case "response.output_audio_transcript.done":
            if let text = event["transcript"] as? String, !text.isEmpty { lines.append(VoiceLine(role: .poki, text: text)) }
        case "output_audio_buffer.started":
            phase = .speaking
            if let delivered = resultDelivered, let stopped = speechStopped {
                lastTurnMS = Int(Date().timeIntervalSince(stopped) * 1000)
                log.add("voice", "turn: end of speech to spoken result \(lastTurnMS!) ms (tool result in \(Int(delivered.timeIntervalSince(stopped) * 1000)) ms)")
                resultDelivered = nil
            }
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared":
            phase = calls.contains { $0.state == .running } ? .thinking : .listening
        case "response.output_item.done":
            guard let item = event["item"] as? [String: Any], item["type"] as? String == "function_call",
                  let id = item["call_id"] as? String, let name = item["name"] as? String else { return }
            run(VoiceCall(id: id, name: name, arguments: item["arguments"] as? String ?? "{}", session: number))
        case "error":
            let message = ((event["error"] as? [String: Any])?["message"] as? String) ?? "unknown error"
            log.add("voice", "realtime error: \(message)")
        default:
            break
        }
    }

    /// Runs a call once. The same call_id again (a repeated event) is ignored.
    private func run(_ call: VoiceCall) {
        guard !calls.contains(where: { $0.id == call.id }) else { return }
        calls.append(call)
        phase = .thinking
        lines.append(VoiceLine(role: .tool, text: Self.describe(call)))
        log.add("voice", "tool \(call.name) \(call.arguments)")
        let local = localTools.contains(call.name)
        let bridge = bridge
        Task {
            var state = VoiceCall.State.done
            var output: String
            if local {
                output = Self.localTool(call.name)
            } else if let bridge {
                do {
                    let result = try await bridge.run(callID: call.id, name: call.name, arguments: call.arguments)
                    output = result.output
                    if result.state != "done" { state = .failed }
                } catch {
                    // The bridge may have run it; never send it again. The model hears that the outcome is unknown.
                    output = "unknown: the bridge did not answer (\(error.localizedDescription)); the action may have run. Read the screen before trying again."
                    state = .failed
                }
            } else {
                output = "error: no voice bridge"
                state = .failed
            }
            finish(call.id, state: state, output: output)
        }
    }

    private func finish(_ id: String, state: VoiceCall.State, output: String) {
        guard let index = calls.firstIndex(where: { $0.id == id }) else { return }
        calls[index].state = state
        calls[index].output = output
        calls[index].finished = Date()
        log.add("voice", "tool \(calls[index].name) \(state == .done ? "done" : "failed")")
        deliver(index)
    }

    /// Hands a finished call to the model: as its function_call_output in the session that asked, or as a
    /// note in a later session. With no session, it waits for the next one.
    private func deliver(_ index: Int) {
        guard let link, ready, !calls[index].delivered, calls[index].state != .running else { return }
        let call = calls[index]
        if call.session == session {
            link.send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": call.id, "output": call.output]])
        } else {
            link.send(Self.note("While the connection was down, \(call.name) \(call.arguments) finished. It already ran; do not run it again. Result: \(call.output)"))
        }
        calls[index].delivered = true
        resultDelivered = Date()
        wantsResponse = true
        flush()
    }

    /// A new session after a drop: say what already ran, so the model reports it instead of asking again.
    private func catchUp(_ link: VoiceLink) {
        let running = calls.filter { $0.state == .running }
        if !running.isEmpty {
            link.send(Self.note("Before the connection dropped, these were started and are still running; their results will follow. Do not start them again: " + running.map { "\($0.name) \($0.arguments)" }.joined(separator: "; ")))
        }
        for index in calls.indices where calls[index].state != .running && !calls[index].delivered { deliver(index) }
    }

    /// Asks for a response once none is active (the API takes one at a time).
    private func flush() {
        guard wantsResponse, activeResponse == nil, ready, let link else { return }
        wantsResponse = false
        link.send(["type": "response.create"])
    }

    private static func note(_ text: String) -> [String: Any] {
        ["type": "conversation.item.create", "item": ["type": "message", "role": "system", "content": [["type": "input_text", "text": text]]]]
    }

    private static func describe(_ call: VoiceCall) -> String {
        switch call.name {
        case "get_ios_version": "Reading the iOS version"
        case "open_settings": "Opening Settings"
        case "read_screen": "Reading the screen"
        case "open_app": "Opening an app"
        case "tap_text": "Tapping"
        case "go_home": "Going Home"
        default: call.name
        }
    }

    /// Tools the phone answers itself. They change nothing.
    static func localTool(_ name: String) -> String {
        switch name {
        case "get_ios_version":
            var info = utsname()
            uname(&info)
            let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return #"{"model":"\#(machine)","ios_version":"\#(UIDevice.current.systemVersion)"}"#
        default:
            return "error: \(name) is not a phone tool"
        }
    }
}
