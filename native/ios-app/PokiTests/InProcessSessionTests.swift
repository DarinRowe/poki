import Foundation
import PokiCore
import XCTest
@testable import Poki

/// Poki opens its own automation session before an agent needs it (ESP-152). When that fails (the
/// owner cancelled the passcode, testmanagerd did not answer within 3 s), an agent's call hears why at
/// once and asks for another try, instead of every call waiting out "opening the session".
final class InProcessSessionTests: XCTestCase {
    func testAFailedOpenIsAnsweredWithItsReasonAndTheCallTriesAgain() {
        let host = AppCoreHost()
        let tries = Tries()
        host.onRetry { tries.add() }
        host.update(runner: InProcessSession.failed(code: "session_timeout", detail: "").agentState)

        let state = host.runnerState()

        guard case .failed(let detail, let fix) = state else { return XCTFail("the agent reads \(state.describe)") }
        XCTAssertTrue(detail.contains("session_timeout"), detail)
        XCTAssertNotNil(fix)
        XCTAssertEqual(tries.count, 1, "the call asks Poki to open the session again")
    }
}

private final class Tries: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func add() { lock.withLock { value += 1 } }
}
