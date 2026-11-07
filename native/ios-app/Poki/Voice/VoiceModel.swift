import Foundation
import Observation
import PokiCore
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
    struct ToolResult: Decodable {
        let state: String
        var output = ""
        var replayed = false
        /// state "check" (tap_text before the phone cleared it): the app in front and the element it would tap.
        var app: App?
        var target: Target?
        struct App: Decodable { let bundle_id: String?; let name: String? }
        struct Target: Decodable { let text: String; let says: String }

        enum CodingKeys: CodingKey { case state, output, replayed, app, target }
        init(state: String, output: String) { self.state = state; self.output = output }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            state = try c.decode(String.self, forKey: .state)
            output = try c.decodeIfPresent(String.self, forKey: .output) ?? ""
            replayed = try c.decodeIfPresent(Bool.self, forKey: .replayed) ?? false
            app = try c.decodeIfPresent(App.self, forKey: .app)
            target = try c.decodeIfPresent(Target.self, forKey: .target)
        }
    }

    func token() async throws -> Token {
        let (data, response) = try await URLSession.shared.data(from: base.appending(path: "token"))
        try Self.check(response, data)
        return try JSONDecoder().decode(Token.self, from: data)
    }

    /// `checked`: for tap_text, the app and element text the phone cleared; without it tap_text only answers "check".
    func run(callID: String, name: String, arguments: String, checked: [String: String]? = nil) async throws -> ToolResult {
        var request = URLRequest(url: base.appending(path: "tool"), timeoutInterval: 75)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) ?? [String: Any]()
        var body: [String: Any] = ["call_id": callID, "name": name, "arguments": args]
        if let checked { body["checked"] = checked }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(ToolResult.self, from: data)
    }

    /// Test runs only: recorded utterance n (24 kHz mono PCM16), served by a bridge started with --test-dir.
    func utterance(_ n: Int) async throws -> Data {
        var parts = URLComponents(url: base.appending(path: "utterance"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "n", value: String(format: "%02d", n))]
        let (data, response) = try await URLSession.shared.data(from: parts.url!)
        try Self.check(response, data)
        return data
    }

    func report(_ turn: [String: Any]) async throws {
        var request = URLRequest(url: base.appending(path: "report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: turn)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
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

/// When each step of one turn happened. `said` is the end of the person's speech (or when recorded
/// speech was sent); the rest are measured from it.
struct TurnClock {
    var said: Date?
    var heard: Date?
    var call: Date?
    var toolDone: Date?
    var delivered: Date?
    var spoken: Date?
    var callNames: [String] = []
    var reply = ""
    /// Tokens the turn's responses used, from `response.done` (text_in, audio_in, text_cached, audio_cached, text_out, audio_out).
    var tokens: [String: Int] = [:]

    mutating func add(usage: [String: Any]) {
        let input = usage["input_token_details"] as? [String: Any] ?? [:]
        let cached = input["cached_tokens_details"] as? [String: Any] ?? [:]
        let output = usage["output_token_details"] as? [String: Any] ?? [:]
        for (key, source, field) in [("text_in", input, "text_tokens"), ("audio_in", input, "audio_tokens"), ("text_cached", cached, "text_tokens"),
                                     ("audio_cached", cached, "audio_tokens"), ("text_out", output, "text_tokens"), ("audio_out", output, "audio_tokens")] {
            tokens[key, default: 0] += source[field] as? Int ?? 0
        }
    }

    func ms(_ step: KeyPath<TurnClock, Date?>) -> Int? {
        guard let said, let at = self[keyPath: step] else { return nil }
        return Int(at.timeIntervalSince(said) * 1000)
    }
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
    /// Timestamps of the current turn, from the end of the person's speech.
    private(set) var clock = TurnClock()

    private var link: VoiceLink?
    /// session.created arrived on the current link: it takes events now.
    private var ready = false
    private var session = 0
    private var activeResponse: String?
    private var wantsResponse = false
    private var localTools: Set<String> = []
    private let log = AppLog.shared
    /// Poki's approval for a tap (PokiCore's rules and approval card): text, app bundle id, app name.
    private let clearTap: @MainActor (String, String?, String?) async -> TapClearance

    /// How long a tap waits for the owner's OK on the phone.
    static let approvalWait: Double = 60

    init(clearTap: @escaping @MainActor (String, String?, String?) async -> TapClearance) {
        self.clearTap = clearTap
    }

    var isOn: Bool { link != nil }

    func setBridge(_ text: String) -> Bool {
        guard let bridge = VoiceBridge(text) else { return false }
        self.bridge = bridge
        VoiceBridge.saved = bridge
        return true
    }

    /// `poki://voice?bridge=<address>&start=1&muted=1`, or `&test=1-20` for a test run.
    func open(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let address = value("bridge") { log.add("voice", setBridge(address) ? "bridge set from a link" : "the link's bridge address was not valid") }
        if value("muted") == "1" { muted = true }
        if let test = value("test"), let range = Self.range(test) { Task { await runTest(range) } }
        else if value("start") == "1", !isOn { Task { await start() } }
    }

    func start(microphone: Bool = true) async {
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
            try await link.connect(secret: token.value, microphone: microphone)
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
        // Without this the next answer (say, when a running step finishes) picks the cut-off reply back up.
        if ready { link.send(Self.note(Self.stoppedNote)) }
    }

    private static let stoppedNote = "The user pressed Stop talking. Drop the reply you were giving; do not continue or repeat it. When a running step finishes, report only its result, in one sentence."

    /// Recorded speech instead of the microphone, for test runs: 24 kHz mono PCM16, sent as one user turn.
    func say(pcm24k: Data) {
        guard let link, ready else { return }
        // A data channel message carries about 256 KB at most, so speech goes in as parts of 2 seconds.
        let part = 96_000
        var sent = true
        for start in stride(from: 0, to: pcm24k.count, by: part) {
            let audio = pcm24k.subdata(in: start..<min(start + part, pcm24k.count)).base64EncodedString()
            sent = link.send(["type": "conversation.item.create", "item": ["type": "message", "role": "user", "content": [["type": "input_audio", "audio": audio]]]]) && sent
        }
        if !sent { log.add("voice", "the recorded speech did not go out on the data channel") }
        clock = TurnClock(said: Date())
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
            clock = TurnClock(said: Date())
        case "conversation.item.added":
            if (event["item"] as? [String: Any])?["role"] as? String == "user" { clock.heard = clock.heard ?? Date() }
        case "conversation.item.input_audio_transcription.completed":
            if let text = event["transcript"] as? String, !text.isEmpty { lines.append(VoiceLine(role: .you, text: text.trimmingCharacters(in: .whitespacesAndNewlines))) }
        case "response.created":
            activeResponse = (event["response"] as? [String: Any])?["id"] as? String
        case "response.done":
            let response = event["response"] as? [String: Any]
            if let usage = response?["usage"] as? [String: Any] { clock.add(usage: usage) }
            if response?["id"] as? String == activeResponse { activeResponse = nil }
            flush()
        case "response.output_audio_transcript.done":
            if let text = event["transcript"] as? String, !text.isEmpty {
                lines.append(VoiceLine(role: .poki, text: text))
                if clock.delivered != nil { clock.reply += text }
            }
        case "output_audio_buffer.started":
            phase = .speaking
            if let said = clock.said, let delivered = clock.delivered, clock.spoken == nil {
                clock.spoken = Date()
                lastTurnMS = clock.ms(\.spoken)
                log.add("voice", "turn: end of speech to spoken result \(lastTurnMS!) ms (tool result in \(Int(delivered.timeIntervalSince(said) * 1000)) ms)")
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
        clock.call = clock.call ?? Date()
        clock.callNames.append(call.name)
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
                    var result = try await bridge.run(callID: call.id, name: call.name, arguments: call.arguments)
                    var note = ""
                    if result.state == "check", let target = result.target {
                        // A tap: Poki's approval rules first, and the owner's OK on the phone when they ask for it.
                        let app = result.app
                        let clearance = await clearTap(target.says, app?.bundle_id, app?.name)
                        if clearance.mayTap {
                            if case .approved(let why) = clearance { note = "The user allowed it on the phone (\(why)). "; log.add("voice", "tap approved: \(why)") }
                            var checked = ["text": target.text]
                            checked["app"] = app?.bundle_id
                            result = try await bridge.run(callID: call.id, name: call.name, arguments: call.arguments, checked: checked)
                        } else {
                            result = Self.refused(clearance)
                            log.add("voice", "tap not sent: \(result.output)")
                        }
                    }
                    output = note + result.output
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
        clock.toolDone = Date()
        log.add("voice", "tool \(calls[index].name) \(state == .done ? "done" : "failed")")
        deliver(index)
    }

    /// Hands a finished call to the model: as its function_call_output in the session that asked, or as a
    /// note in a later session. With no session, it waits for the next one.
    private func deliver(_ index: Int) {
        guard let link, ready, !calls[index].delivered, calls[index].state != .running else { return }
        let call = calls[index]
        let sent = call.session == session
            ? link.send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": call.id, "output": call.output]])
            : link.send(Self.note("While the connection was down, \(call.name) \(call.arguments) finished. It already ran; do not run it again. Tell the user in one sentence how it ended. Result: \(call.output)"))
        guard sent else { return }
        calls[index].delivered = true
        clock.delivered = Date()
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

    // MARK: Test runs

    /// `poki://voice?test=1-20`: each turn opens a fresh session, plays recorded utterance n from the bridge
    /// over the data channel (no microphone, Poki's voice muted), waits for the spoken result and reports
    /// the turn to the bridge.
    func runTest(_ numbers: ClosedRange<Int>) async {
        guard let bridge else { phase = .lost(VoiceError.noBridge.localizedDescription); return }
        muted = true
        // Test runs have no microphone, so no voice-chat audio session keeps Poki running while a step
        // brings another app to the front; a silent one does, as for a Poki session.
        let awake = KeepAlive()
        try? awake.start()
        defer { awake.stop() }
        log.add("voice", "test run \(numbers.lowerBound)-\(numbers.upperBound) started")
        for n in numbers {
            stop()
            var report: [String: Any] = ["n": n, "device": Self.localTool("get_ios_version")]
            await start(microphone: false)
            if await until(10, { self.ready }), let pcm = try? await bridge.utterance(n) {
                say(pcm24k: pcm)
                let ok = await until(40, { self.clock.spoken != nil && !self.clock.reply.isEmpty && self.activeResponse == nil })
                report["ok"] = ok
                report["calls"] = clock.callNames
                report["reply"] = clock.reply
                report["tokens"] = clock.tokens
                report["ms"] = ["heard": clock.ms(\.heard), "call": clock.ms(\.call), "toolDone": clock.ms(\.toolDone), "delivered": clock.ms(\.delivered), "spoken": clock.ms(\.spoken)].compactMapValues { $0 }
            } else {
                report["ok"] = false
                report["error"] = { if case .lost(let why) = self.phase { return why } else { return "no session" } }()
            }
            stop()
            try? await bridge.report(report)
        }
        log.add("voice", "test run finished")
    }

    private func until(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > end { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private static func range(_ text: String) -> ClosedRange<Int>? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard let first = parts.first, let last = parts.last, first >= 1, last >= first, last <= 99 else { return nil }
        return first...last
    }

    private static func refused(_ clearance: TapClearance) -> VoiceBridge.ToolResult {
        let output: String
        switch clearance {
        case .declined(let why): output = "not_sent: the user declined on the phone (\(why)). Nothing was tapped."
        case .unanswered(let why): output = "not_sent: the user did not allow it on the phone in time (\(why)). Nothing was tapped."
        case .clear, .approved: output = ""
        }
        return VoiceBridge.ToolResult(state: "failed", output: output)
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
