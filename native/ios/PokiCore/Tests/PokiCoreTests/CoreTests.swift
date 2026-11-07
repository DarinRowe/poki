import XCTest
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import PokiCore

final class BasicsTests: XCTestCase {
    func testBase32() {
        XCTAssertEqual(base32(Data("foobar".utf8)), "mzxw6ytboi")
        XCTAssertEqual(base32(Data(count: 32)).count, 52)
    }

    func testJSONRoundTrip() throws {
        let value: JSON = ["a": [1, 2.5, "x", true, nil], "b": ["c": "d"]]
        XCTAssertEqual(try JSON.parse(value.serialized()), value)
    }

    func testDeadlineDoesNotWaitForAnOperationThatIgnoresCancellation() async {
        let started = Date()
        do {
            _ = try await withDeadline(0.2, "a stuck step") { await hang() }
            XCTFail("expected the deadline")
        } catch let error as DeadlineExceeded {
            XCTAssertEqual(error.what, "a stuck step")
        } catch { XCTFail("\(error)") }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testSensitiveWordsMatchWholeWords() {
        XCTAssertEqual(SensitivityRules.matches("Delete Photo", ["delete"]), "delete")
        XCTAssertNil(SensitivityRules.matches("Display & Brightness", ["pay"]))
        XCTAssertEqual(SensitivityRules.matches("确认支付", ["支付"]), "支付")
    }
}

/// What the agent reads while the loopback is down: the owner's way back depends on the connection.
final class LoopbackWaitTests: XCTestCase {
    func testTheBuiltInConnectionSendsTheOwnerBackToPokiNotToAProxyApp() {
        XCTAssertEqual(
            RunnerState.waitingForLoopback(since: "14:02:11", tunnelWithoutAnswer: false, connection: .builtIn),
            .starting("waiting for the loopback since 14:02:11: Poki's local connection is off, or another VPN app replaced it. The owner opens Poki and taps Enable local connection in Setup, or turns Poki's VPN back on in iOS Settings > VPN; the runner starts again by itself within seconds of that. Nothing on the phone changes meanwhile"))
        XCTAssertEqual(
            RunnerState.waitingForLoopback(since: nil, tunnelWithoutAnswer: true, connection: .builtIn),
            .starting("waiting for the loopback: Poki's local connection is on, but this iPhone's developer services do not answer at 10.7.0.1. The owner opens Poki and taps Enable local connection in Setup, or turns Poki's VPN back on in iOS Settings > VPN; the runner starts again by itself within seconds of that. Nothing on the phone changes meanwhile"))
    }

    func testAProxyAppKeepsItsOwnInstructions() {
        XCTAssertEqual(
            RunnerState.waitingForLoopback(since: "14:02:11", tunnelWithoutAnswer: false, connection: .external),
            .starting("waiting for the loopback since 14:02:11: the loopback at 10.7.0.1 is not answering. The owner turns the proxy app's tunnel (Surge, Loon, Shadowrocket or sing-box) back on; the runner starts again by itself within seconds of that. Nothing on the phone changes meanwhile"))
        XCTAssertEqual(
            RunnerState.waitingForLoopback(since: nil, tunnelWithoutAnswer: true, connection: .external),
            .starting("waiting for the loopback: the proxy app's tunnel is on but does not reflect 10.7.0.1. The owner turns the proxy app's tunnel (Surge, Loon, Shadowrocket or sing-box) back on; the runner starts again by itself within seconds of that. Nothing on the phone changes meanwhile"))
    }
}

final class ToolTests: XCTestCase {
    func testLookListsElementsWithAPicture() async {
        let (core, _, _) = makeCore()
        let result = await core.call("look", [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.hasPrefix("app: Settings"), result.text)
        XCTAssertTrue(result.text.contains("1 Button \"General\" [16,100,358,44]"), result.text)
        XCTAssertNotNil(result.jpeg)
    }

    func testAStuckTreeStillAnswersInTimeWithThePicture() async {
        let (core, wda, _) = makeCore()
        wda.set("GET /source") { _ in await hang() }
        let started = Date()
        let result = await core.call("look", [:])
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertNotNil(result.jpeg, "the screenshot still comes back")
        XCTAssertTrue(result.text.contains("no element tree"), result.text)
    }

    func testANothingRunnerAnswersFastAndAsksForARestart() async {
        let (core, wda, host) = makeCore()
        let gone: FakeWDA.Route = { _ in throw TransportError.refused }
        for key in ["GET /source", "GET /screenshot", "GET /wda/activeAppInfo", "GET /wda/screen", "POST /session"] { wda.set(key, gone) }
        let started = Date()
        let result = await core.call("look", [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("read: failed"), result.text)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertGreaterThanOrEqual(host.restarts.value, 1)
        // A failed runner is answered at once, with its fix, and nothing is sent.
        host.state.value = .failed("Poki Runner is not installed", fix: "Install it")
        let count = wda.sent.count
        let quick = Date()
        let next = await core.call("do", ["actions": [["tap": [10, 10]]]])
        XCTAssertTrue(next.text.contains("runner: failed: Poki Runner is not installed. Fix on the phone: Install it"), next.text)
        XCTAssertLessThan(Date().timeIntervalSince(quick), 0.5)
        XCTAssertEqual(wda.sent.count, count)
    }

    func testACallWaitsForARunnerThatIsStartingThenGoesOn() async {
        let (core, wda, host) = makeCore()
        host.state.value = .starting("launching the runner")
        Task { try? await Task.sleep(nanoseconds: 600_000_000); host.state.value = .running }
        let started = Date()
        let result = await core.call("look", [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertFalse(wda.sent.isEmpty)
    }

    func testARunnerThatNeverStartsIsAnsweredWithinTheCap() async {
        let (core, wda, host) = makeCore { $0.runnerWait = 0.5 }
        host.state.value = .starting("mounting the developer disk image")
        let started = Date()
        let result = await core.call("do", ["actions": [["tap": [10, 10]]]])
        XCTAssertTrue(result.text.contains("still starting"), result.text)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
        XCTAssertTrue(wda.sent.isEmpty)
    }

    func testTapByNumberHitsTheCentre() async {
        let (core, wda, _) = makeCore()
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 2]]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").last, ["x": 195, "y": 166])
        XCTAssertTrue(result.text.contains("did: tap tap \"Privacy\" (sent"), result.text)
    }

    func testAStaleNumberSendsNothing() async {
        let (core, wda, _) = makeCore()
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 9]]])
        XCTAssertFalse(result.isError, "the screen was read, so the answer is not an error; its error line says what was wrong")
        XCTAssertTrue(result.text.contains("element 9 is not in the latest read"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
    }

    func testAStuckTapIsReportedAsMaybeDeliveredAndNothingAfterItIsSent() async {
        let (core, wda, _) = makeCore()
        wda.set("POST /wda/tap") { _ in await hang() }
        _ = await core.call("look", [:])
        let started = Date()
        let result = await core.call("do", ["actions": [["tap": 1], ["key": "return"]]])
        XCTAssertLessThan(Date().timeIntervalSince(started), 6)
        XCTAssertTrue(result.text.contains("may have been delivered"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/keys").isEmpty)
        XCTAssertNotNil(result.jpeg, "the screen is still read after the failure")
    }

    func testTypingClearsWithDeletesInOneRequest() async {
        let (core, wda, _) = makeCore()
        wda.tree([Node("TextField", nil, [16, 100, 358, 44], value: "abc"), Node("Keyboard", nil, [0, 500, 390, 344])], app: "Notes")
        _ = await core.call("look", [:])
        _ = await core.call("do", ["actions": [["type": "hi", "clear": true]]])
        XCTAssertEqual(wda.bodies("POST /wda/keys").last, ["value": ["\u{8}", "\u{8}", "\u{8}", "h", "i"]])
    }

    func testTheSecondCallIsBusyInsteadOfQueued() async {
        let (core, wda, _) = makeCore()
        wda.set("GET /source") { _ in try await Task.sleep(nanoseconds: 800_000_000); return (200, ["value": ["type": "XCUIElementTypeApplication"]]) }
        async let first = core.call("look", [:])
        try? await Task.sleep(nanoseconds: 100_000_000)
        let second = await core.call("look", [:])
        XCTAssertTrue(second.text.hasPrefix("busy"), second.text)
        _ = await first
    }
}

final class ApprovalTests: XCTestCase {
    func screenWithDelete() -> FakeWDA {
        let wda = FakeWDA()
        wda.source([("Button", "Delete Photo"), ("Button", "Share")], app: "Photos")
        return wda
    }

    func testADeletionWaitsForTheOwnerAndSendsNothing() async {
        let (core, wda, _) = makeCore(screenWithDelete())
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("approval_required"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
        let pending = core.pendingApproval
        XCTAssertEqual(pending?.reason, "deleting (\"delete\")")
        // Approved on the phone: the same actions sent again run once.
        core.resolveApproval(id: pending!.id, approved: true)
        let again = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertFalse(again.isError, again.text)
        XCTAssertTrue(again.text.contains("approved on the phone"), again.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 1)
        // Used up: a third time asks again.
        let third = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(third.text.contains("approval_required"), third.text)
    }

    func testApprovalDuringTheWaitRunsTheActionsInTheSameCall() async {
        let (core, wda, _) = makeCore(screenWithDelete()) { $0.approvalWait = 2 }
        _ = await core.call("look", [:])
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let p = core.pendingApproval { core.resolveApproval(id: p.id, approved: true) }
        }
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(wda.bodies("POST /wda/tap").count, 1)
    }

    func testDeclinedSendsNothing() async {
        let (core, wda, _) = makeCore(screenWithDelete()) { $0.approvalWait = 2 }
        _ = await core.call("look", [:])
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let p = core.pendingApproval { core.resolveApproval(id: p.id, approved: false) }
        }
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(result.text.contains("declined"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
    }

    func testOtherActionsWithdrawThePendingRequestSoTheAutomationCannotApproveIt() async {
        let (core, _, _) = makeCore(screenWithDelete())
        _ = await core.call("look", [:])
        _ = await core.call("do", ["actions": [["tap": 1]]])
        let id = core.pendingApproval!.id
        _ = await core.call("do", ["actions": [["tap": 2]]])
        XCTAssertNil(core.pendingApproval)
        core.resolveApproval(id: id, approved: true)  // a press that arrives late does nothing
        let again = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(again.text.contains("approval_required"), again.text)
    }

    func testTappingAContactInPhonePlacesNoCallWithoutTheOwner() async {
        let wda = FakeWDA()
        wda.source([("Cell", "Mom, mobile"), ("Button", "Keypad")], app: "Phone")
        wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "com.apple.mobilephone", "name": "Phone"]]) }
        let (core, _, _) = makeCore(wda)
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(result.text.contains("approval_required"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
        XCTAssertEqual(core.pendingApproval?.reason, "a call (in Phone)")
    }

    /// The Voice tab's "tap Send" goes through the Mac, not `do`; it is held by the same rules and the same approval.
    func testAVoiceTapOnSendInMessagesWaitsForTheOwner() async {
        let (core, _, _) = makeCore()
        let unanswered = await core.clearTap(on: "Send", inApp: "com.apple.MobileSMS", named: "Messages", waiting: 0.2)
        XCTAssertEqual(unanswered, .unanswered("sending a message (\"send\")"))
        XCTAssertFalse(unanswered.mayTap)
        XCTAssertNil(core.pendingApproval, "a request nobody answered is withdrawn")

        Task {
            _ = await eventually { core.pendingApproval != nil }
            XCTAssertEqual(core.pendingApproval?.summary, "Tap “Send”")
            XCTAssertEqual(core.pendingApproval?.app, "Messages")
            core.resolveApproval(id: core.pendingApproval!.id, approved: true)
        }
        let approved = await core.clearTap(on: "Send", inApp: "com.apple.MobileSMS", named: "Messages", waiting: 2)
        XCTAssertTrue(approved.mayTap, "\(approved)")

        let settings = await core.clearTap(on: "Display & Brightness", inApp: "com.apple.Preferences", named: "Settings", waiting: 2)
        XCTAssertEqual(settings, .clear)
    }

    /// The approval card is in Poki: a voice "tap Allow" with Poki in front taps nothing, and the request
    /// it would have granted stays for the owner.
    func testAVoiceTapInPokiCannotApproveThePendingRequest() async throws {
        let (core, _, _) = makeCore()
        let send = Task { await core.clearTap(on: "Send", inApp: "com.apple.MobileSMS", named: "Messages", waiting: 3) }
        let asked = await eventually { core.pendingApproval != nil }
        XCTAssertTrue(asked, "the Send tap asks the owner")
        let pending = try XCTUnwrap(core.pendingApproval)

        let allow = await core.clearTap(on: "Allow", inApp: "nz.zheha.poki", named: "Poki", waiting: 1)
        XCTAssertFalse(allow.mayTap, "\(allow)")
        XCTAssertEqual(core.pendingApproval?.id, pending.id, "the owner still decides the Send tap")

        core.resolveApproval(id: pending.id, approved: false)
        let sent = await send.value
        XCTAssertFalse(sent.mayTap)
    }

    /// Like `do`: another voice tap withdraws the request still waiting, so two taps never wait side by side.
    func testAnotherVoiceTapWithdrawsThePendingRequest() async throws {
        let (core, _, _) = makeCore()
        let send = Task { await core.clearTap(on: "Send", inApp: "com.apple.MobileSMS", named: "Messages", waiting: 3) }
        let asked = await eventually { core.pendingApproval != nil }
        XCTAssertTrue(asked, "the Send tap asks the owner")
        let pending = try XCTUnwrap(core.pendingApproval)

        let settings = await core.clearTap(on: "Display & Brightness", inApp: "com.apple.Preferences", named: "Settings", waiting: 1)
        XCTAssertEqual(settings, .clear)
        XCTAssertNil(core.pendingApproval, "the Send request is withdrawn")
        core.resolveApproval(id: pending.id, approved: true)  // a press that arrives late does nothing
        let sent = await send.value
        XCTAssertFalse(sent.mayTap, "\(sent)")
    }

    /// A voice tap on an element with no readable text cannot be checked against the rules, so the owner
    /// is asked (a Send button known only by its identifier would otherwise go through).
    func testAVoiceTapWithNoReadableTextAsksTheOwner() async {
        let (core, _, _) = makeCore()
        let asked = Task { await eventually { core.pendingApproval != nil } }
        let tap = await core.clearTap(on: "  ", inApp: "com.apple.MobileSMS", named: "Messages", waiting: 0.3)
        let wasAsked = await asked.value
        XCTAssertFalse(tap.mayTap, "\(tap)")
        XCTAssertTrue(wasAsked, "the owner is asked on the phone")
    }

    /// An element can read "Done" and still be the Send button by its identifier; `do` checks both.
    func testDoAsksForAButtonOnlyItsIdentifierCallsSend() async {
        let wda = FakeWDA()
        let button: JSON = ["type": "XCUIElementTypeButton", "label": "Done", "name": "send-button", "rect": ["x": 16, "y": 100, "width": 358, "height": 44]]
        let root: JSON = ["type": "XCUIElementTypeApplication", "label": "Messages", "rect": ["x": 0, "y": 0, "width": 390, "height": 844], "children": [button]]
        wda.set("GET /source") { _ in (200, ["value": root]) }
        wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "com.apple.MobileSMS", "name": "Messages"]]) }
        let (core, _, _) = makeCore(wda)
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(result.text.contains("approval_required"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
    }

    /// The relay agent's `do` never taps in Poki either.
    func testDoTapsNothingInPoki() async {
        let wda = FakeWDA()
        wda.source([("Button", "Allow"), ("Button", "Deny")], app: "Poki")
        wda.set("GET /wda/activeAppInfo") { _ in (200, ["value": ["bundleId": "nz.zheha.poki", "name": "Poki"]]) }
        let (core, _, _) = makeCore(wda)
        _ = await core.call("look", [:])
        let result = await core.call("do", ["actions": [["tap": 1]]])
        XCTAssertTrue(result.isError, result.text)
        XCTAssertTrue(result.text.contains("only the phone's owner"), result.text)
        XCTAssertTrue(wda.bodies("POST /wda/tap").isEmpty)
    }

    func testPasswordsNeedApproval() async {
        let wda = FakeWDA()
        wda.source([("TextField", "Email"), ("SecureTextField", "Password")])
        let (core, _, _) = makeCore(wda)
        _ = await core.call("look", [:])
        let typed = await core.call("do", ["actions": [["type": "hunter2", "ref": 2]]])
        XCTAssertTrue(typed.text.contains("password field"), typed.text)
        XCTAssertFalse(core.pendingApproval!.summary.contains("hunter2"), "the summary hides the text")
        let email = await core.call("do", ["actions": [["type": "a@b.c", "ref": 1]]])
        XCTAssertFalse(email.isError, email.text)
    }
}

final class MCPTests: XCTestCase {
    func post(_ core: PokiCore, _ body: JSON, session: String? = nil) async -> RelayResponse {
        await core.handle(RelayRequest(id: "r", method: "POST", headers: session.map { ["mcp-session-id": $0] } ?? [:], body: body.serialized()))
    }

    func testInitializeListAndCall() async throws {
        let (core, _, _) = makeCore()
        let initialized = await post(core, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        XCTAssertEqual(initialized.status, 200)
        let session = try XCTUnwrap(initialized.headers["mcp-session-id"])
        XCTAssertEqual(try JSON.parse(initialized.body)["result"]?["protocolVersion"], "2025-06-18")
        let note = await post(core, ["jsonrpc": "2.0", "method": "notifications/initialized"], session: session)
        XCTAssertEqual(note.status, 202)
        let list = try JSON.parse(await post(core, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"], session: session).body)
        XCTAssertEqual(list["result"]?["tools"]?.array?.compactMap { $0["name"]?.string }, ["look", "do", "status"])
        let call = try JSON.parse(await post(core, ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "look", "arguments": .object([:])]], session: session).body)
        XCTAssertEqual(call["result"]?["content"]?[1]?["type"], "image")
        XCTAssertEqual(call["result"]?["isError"], false)
    }

    func testGetIsNotAllowed() async {
        let (core, _, _) = makeCore()
        let r = await core.handle(RelayRequest(id: "r", method: "GET", headers: [:], body: ""))
        XCTAssertEqual(r.status, 405)
    }
}

final class RelayTests: XCTestCase {
    func testHandshakeRequestsAndKeepalive() async throws {
        let (core, _, _) = makeCore()
        let sockets = FakeSockets()
        let events = LockedBox<[CoreEvent]>([])
        Task { for await e in core.events { events.update { $0.append(e) } } }
        core.start(relay: testRelay, socketFactory: sockets)
        core.relay?.pingEvery = 0.1
        do { let ok = await eventually { !sockets.sockets.value.isEmpty }; XCTAssertTrue(ok) }
        let socket = sockets.sockets.value[0]
        let label = base32(FakeKey().publicKey)
        XCTAssertEqual(sockets.urls.value[0].absoluteString, "wss://relay.example.com/v1/\(label)/connect")

        let nonce = Data(repeating: 7, count: 32)
        socket.push((["t": "challenge", "nonce": .string(nonce.base64EncodedString())] as JSON).serialized())
        do { let ok = await eventually { !socket.sent.isEmpty }; XCTAssertTrue(ok) }
        let hello = try JSON.parse(socket.sent[0])
        XCTAssertEqual(hello["t"], "hello")
        XCTAssertEqual(hello["access"], ["abc123"])
        var signed = Data("poki-relay-v1:\(label):".utf8)
        signed.append(nonce)
        XCTAssertEqual(hello["sig"]?.string, try FakeKey().sign(signed).base64EncodedString())

        socket.push((["t": "ready", "max_body": 4_194_304] as JSON).serialized())
        do { let ok = await eventually { events.value.contains(.relay(.ready(url: "wss://relay.example.com/v1/\(label)"))) }; XCTAssertTrue(ok) }
        do { let ok = await eventually { socket.sent.contains("ping") }; XCTAssertTrue(ok) }

        let body = (["jsonrpc": "2.0", "id": 1, "method": "tools/list"] as JSON).serialized()
        socket.push((["t": "req", "id": "q1", "method": "POST", "headers": ["Content-Type": "application/json"], "body": .string(body)] as JSON).serialized())
        do { let ok = await eventually { socket.sent.contains { $0.contains("\"t\":\"res\"") } }; XCTAssertTrue(ok) }
        let res = try JSON.parse(socket.sent.first { $0.contains("\"t\":\"res\"") }!)
        XCTAssertEqual(res["id"], "q1")
        XCTAssertEqual(res["status"], 200)
        XCTAssertNotNil(try JSON.parse(res["body"]!.string!)["result"]?["tools"])
        core.stop()
    }

    func testTheRelayAddressThePersonEntersDecidesWhereThePhoneDials() {
        let entered: [(String, String?, String?)] = [
            ("poki-relay.you.workers.dev", "wss://poki-relay.you.workers.dev/v1", "https://poki-relay.you.workers.dev/v1"),
            (" https://Relay.Example.com/v1/ ", "wss://relay.example.com/v1", "https://relay.example.com/v1"),
            ("http://127.0.0.1:8787", "ws://127.0.0.1:8787/v1", "http://127.0.0.1:8787/v1"),
            ("https://relay.example.com/other", nil, nil),
            ("ftp://relay.example.com", nil, nil),
            ("", nil, nil),
        ]
        for (text, phone, connector) in entered {
            let address = RelayAddress(text)
            XCTAssertEqual(address?.phoneURL.absoluteString, phone, text)
            XCTAssertEqual(address?.connectorBase.absoluteString, connector, text)
        }
    }

    /// A three-action do answered "what was sent is unknown" when the relay reset mid-call: the
    /// call now runs to its end and its answer comes with the next call.
    func testAnAnswerReadyAfterTheConnectionDroppedComesWithTheNextCall() async throws {
        let (core, wda, _) = makeCore()
        wda.delay("GET /source", 0.7)
        let sockets = FakeSockets()
        core.start(relay: testRelay, socketFactory: sockets)
        core.relay?.maxBackoff = 0.05
        func ready(_ socket: FakeSocket) async {
            socket.push((["t": "challenge", "nonce": .string(Data(repeating: 7, count: 32).base64EncodedString())] as JSON).serialized())
            _ = await eventually { !socket.sent.isEmpty }
            socket.push((["t": "ready", "max_body": 4_194_304] as JSON).serialized())
        }
        func call(_ socket: FakeSocket, _ id: String) {
            let body = (["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "look", "arguments": [:]]] as JSON).serialized()
            socket.push((["t": "req", "id": .string(id), "method": "POST", "headers": ["Content-Type": "application/json"], "body": .string(body)] as JSON).serialized())
        }
        do { let ok = await eventually { !sockets.sockets.value.isEmpty }; XCTAssertTrue(ok) }
        let first = sockets.sockets.value[0]
        await ready(first)
        call(first, "q1")
        try await Task.sleep(nanoseconds: 200_000_000)
        first.close(code: 1006, reason: "reset")
        do { let ok = await eventually(5) { sockets.sockets.value.count >= 2 }; XCTAssertTrue(ok) }
        let second = sockets.sockets.value[1]
        await ready(second)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertFalse(first.sent.contains { $0.contains("\"t\":\"res\"") }, "nothing goes to the dropped connection")
        call(second, "q2")
        do { let ok = await eventually(5) { second.sent.contains { $0.contains("\"t\":\"res\"") } }; XCTAssertTrue(ok) }
        let res = try JSON.parse(second.sent.first { $0.contains("\"t\":\"res\"") }!)
        XCTAssertEqual(res["id"], "q2")
        let text = try JSON.parse(res["body"]!.string!)["result"]?["content"]?[0]?["text"]?.string ?? ""
        XCTAssertTrue(text.hasPrefix("earlier, never delivered to you: the look call whose connection dropped (finished at "), text)
        XCTAssertTrue(text.contains("\n\nnow:\napp: Settings"), text)
        core.stop()
    }

    func testTheRelayIsDialedAgainAfterADrop() async {
        let (core, _, _) = makeCore()
        let sockets = FakeSockets()
        core.start(relay: testRelay, socketFactory: sockets)
        core.relay?.maxBackoff = 0.05
        do { let ok = await eventually { !sockets.sockets.value.isEmpty }; XCTAssertTrue(ok) }
        sockets.sockets.value[0].close(code: 1006, reason: "gone")
        do { let ok = await eventually(5) { sockets.sockets.value.count >= 2 }; XCTAssertTrue(ok) }
        core.stop()
    }
}

final class EventTests: XCTestCase {
    func testAFinishedCallCarriesTheAppAndAThumbnail() async {
        let (core, _, _) = makeCore()
        let events = LockedBox<[CoreEvent]>([])
        Task { for await e in core.events { events.update { $0.append(e) } } }
        _ = await core.call("look", [:])
        let finished = await eventually { events.value.contains { if case .toolFinished = $0 { return true }; return false } }
        XCTAssertTrue(finished)
        guard case .toolFinished(_, .done, let facts)? = events.value.last else { return XCTFail("\(events.value)") }
        XCTAssertEqual(facts.app, "Settings")
        XCTAssertNotNil(facts.thumbnail)
    }

    /// The app logs each call's summary. What was typed stays out of the log, after the first step too.
    func testTheSummariesTheAppLogsKeepNoTypedText() async {
        let wda = FakeWDA()
        wda.source([("SearchField", "Search")])
        let (core, _, _) = makeCore(wda)
        let events = LockedBox<[CoreEvent]>([])
        Task { for await e in core.events { events.update { $0.append(e) } } }
        _ = await core.call("do", ["actions": [["type": "door code 4412"]]])
        _ = await core.call("look", [:])
        _ = await core.call("do", ["actions": [["tap": 1], ["type": "meet at 5, door code 4412"]]])
        _ = await core.call("do", ["actions": [["type": "他说“好的”就在4412"]]])
        let summaries = { events.value.compactMap { e -> String? in if case .toolStarted(let a) = e, a.name == "do" { return a.summary }; return nil } }
        let started = await eventually { summaries().count == 3 }
        XCTAssertTrue(started)
        XCTAssertEqual(summaries().map(StepLabels.withoutTypedText), ["Type “…”", "Tap “Search”, then type “…”", "Type “…”"])
    }
}

final class DDITests: XCTestCase {
    final class Mirror: HTTPTransport, @unchecked Sendable {
        var files: [String: Data] = [:]
        func send(method: String, url: URL, body: Data?, timeout: Double) async throws -> (status: Int, body: Data) {
            files[url.lastPathComponent].map { (200, $0) } ?? (404, Data())
        }
    }

    func testDownloadsIntoPlaceAndKeepsAVerifiedCopy() async throws {
        let mirror = Mirror()
        var manifestEntries: [String: Any] = [:]
        for (key, path) in zip(DeveloperDiskImage.payloadKeys, ["Image.dmg", "Image.dmg.trustcache", "Image.dmg.cryptex_info", "Image.dmg.root_hash"]) {
            #if canImport(CryptoKit)
            let digest = Data(SHA384.hash(data: Data(path.utf8)))
            #else
            let digest = Data([1])
            #endif
            manifestEntries[key] = ["Info": ["Path": path], "Digest": digest]
            mirror.files[path] = Data(path.utf8)
        }
        let manifest: [String: Any] = ["ProductBuildVersion": "22A1", "BuildIdentities": [["Manifest": manifestEntries]]]
        mirror.files["BuildManifest.plist"] = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ddi-\(UUID().uuidString)")
        let build = try await DeveloperDiskImage.ensure(in: dir, from: URL(string: "https://mirror.invalid/x")!, transport: mirror)
        XCTAssertEqual(build, "22A1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Image.dmg").path))
        mirror.files = [:]  // a verified copy is not downloaded again
        let again = try await DeveloperDiskImage.ensure(in: dir, from: URL(string: "https://mirror.invalid/x")!, transport: mirror)
        XCTAssertEqual(again, "22A1")
        try? FileManager.default.removeItem(at: dir)
    }
}
