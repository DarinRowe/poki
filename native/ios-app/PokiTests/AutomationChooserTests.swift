import XCTest
@testable import Poki

/// The method Poki chooses for each situation: native services first, the XCTest session where it
/// is the only one, and a question to the owner before its banner stands in for native services.
final class AutomationChooserTests: XCTestCase {
    private typealias C = AutomationChooser.Conditions

    private func expect(_ c: C, _ method: AutomationChooser.Method, _ ask: AutomationChooser.Ask?, _ name: String, line: UInt = #line) {
        let got = AutomationChooser.choose(c)
        XCTAssertEqual(got.method, method, "\(name): \(got.why)", line: line)
        XCTAssertEqual(got.ask, ask, "\(name): \(got.why)", line: line)
    }

    func testEverySituation() {
        expect(C(iOS: 18, loopbackWorking: true), .xctest, nil, "iOS 18 with loopback")
        expect(C(iOS: 26, current: .xctest), .xctest, nil, "iOS 26 no loopback")
        expect(C(iOS: 27, pinned: .xctest, loopbackWorking: true), .xctest, nil, "pinned xctest")
        expect(C(iOS: 27, pinned: .native, imageMounted: true), .native, nil, "pinned native without loopback")
        expect(C(iOS: 27, loopbackWorking: true), .native, nil, "iOS 27 Wi-Fi")
        expect(C(iOS: 27, cellularOnly: true, imageMounted: true, onWiFi: false), .native, .noWiFi, "cold start on cellular asks")
        expect(C(iOS: 27, cellularOnly: true, imageMounted: true, onWiFi: false, bannerAllowed: true), .xctest, nil, "cellular, owner agreed")
        expect(C(iOS: 27, imageMounted: true, onWiFi: true), .native, .loopbackOff, "Wi-Fi, loopback off: nudge")
        expect(C(iOS: 27, imageMounted: true, onWiFi: true, bannerAllowed: true), .xctest, nil, "Wi-Fi, loopback off, agreed")
        expect(C(iOS: 27, cellularOnly: true, nativeTunnelsOpen: true, imageMounted: true, onWiFi: false), .native, nil, "tunnels opened on Wi-Fi, now cellular")
        expect(C(iOS: 27, current: .xctest, loopbackWorking: true, imageMounted: true, xctestOpen: true, bannerAllowed: true), .native, nil, "Wi-Fi back while on xctest")
        expect(C(iOS: 27, current: .native, imageMounted: false), .native, nil, "nothing possible: no ask")
        expect(C(iOS: 27, imageMounted: true, xctestUnavailable: true), .native, nil, "xctest used up: no ask")
        expect(C(iOS: 27, loopbackWorking: true, imageMounted: true, nativeFailures: 2), .native, .nativeFailing, "native keeps failing asks")
        expect(C(iOS: 27, loopbackWorking: true, imageMounted: true, nativeFailures: 2, bannerAllowed: true), .xctest, nil, "native failing, agreed")
        expect(C(iOS: 27, loopbackWorking: true, cellularOnly: true, imageMounted: true, onWiFi: false), .native, .noWiFi, "proxy answers but only cellular")
        expect(C(iOS: 27, cellularOnly: true, nativeTunnelsOpen: true, imageMounted: true, nativeFailures: 2, onWiFi: false), .native, .noWiFi, "held tunnels died on cellular")
    }
}
