import XCTest
@testable import Poki

/// `poki://voice` links can come from any web page or app, so they open the Voice tab and nothing more.
@MainActor
final class VoiceLinkTests: XCTestCase {
    private let mine = "http://192.168.1.10:47830/voice/0123456789abcdefghijklmn"
    private var before: VoiceBridge?

    override func setUp() async throws {
        before = VoiceBridge.saved
        VoiceBridge.saved = VoiceBridge(mine)
    }

    override func tearDown() async throws {
        VoiceBridge.saved = before
    }

    private func opened(_ link: String) async -> VoiceModel {
        let voice = VoiceModel { _, _, _ in .clear }
        voice.open(URL(string: link)!)
        // Whatever the link started would be under way by now.
        for _ in 0..<10 { await Task.yield() }
        return voice
    }

    func testALinkCannotSwitchTheBridgeOrTurnOnTheMicrophone() async {
        let voice = await opened("poki://voice?bridge=https://someone-else.example/voice/abcdefghijklmnopqrstuvwx&start=1")
        XCTAssertEqual(voice.bridge?.base.absoluteString, mine)
        XCTAssertEqual(VoiceBridge.saved?.base.absoluteString, mine)
        XCTAssertFalse(voice.isOn)
        XCTAssertEqual(voice.phase, .off)
    }

    func testALinkCannotStartASilentTestRun() async {
        let voice = await opened("poki://voice?test=1-99&muted=1")
        XCTAssertFalse(voice.muted)
        XCTAssertFalse(voice.isOn)
        XCTAssertEqual(voice.phase, .off)
    }
}
