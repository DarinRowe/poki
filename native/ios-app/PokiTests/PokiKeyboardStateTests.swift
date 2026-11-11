import SwiftUI
import XCTest
@testable import Poki

/// The word Setup shows for the Poki keyboard (#162). Poki cannot read Full Access itself: it learns
/// it only when the keyboard has come up once and written its status.
final class PokiKeyboardStateTests: XCTestCase {
    func testWordForEachState() {
        XCTAssertEqual(PokiKeyboardState(added: false, answered: false).word, "Not Added")
        // Added with Full Access on, but the panel has not come up yet: one step is left, not a permission.
        XCTAssertEqual(PokiKeyboardState(added: true, answered: false).word, "One More Step")
        XCTAssertEqual(PokiKeyboardState(added: true, answered: true).word, "Ready")
        // Removed in Settings after it had answered: iOS's list no longer has it.
        XCTAssertEqual(PokiKeyboardState(added: false, answered: true, listed: true).word, "Not Added")
    }
}
