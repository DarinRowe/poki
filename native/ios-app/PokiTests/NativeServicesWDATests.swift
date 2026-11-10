import PokiCore
import UIKit
import XCTest
@testable import Poki

final class NativeServicesWDATests: XCTestCase {
    func testCompactStatusAndGlyphShareEventColor() {
        var state = PokiState(phase: .idle, headline: "Ready", thumbnailVersion: 0)
        state.event = .init(kind: .started, text: "Started")
        let face = state.face
        guard case .text(_, let tone) = face.compact else { return XCTFail("Expected compact status") }
        XCTAssertEqual(tone, face.tone)
    }

    func testDragVelocityUsesScreenPointsNotHIDCoordinates() {
        let body: JSON = ["fromX": 201, "fromY": 300, "toX": 201, "toY": 480, "velocity": 800]
        XCTAssertEqual(NativeServicesWDA.dragMilliseconds(body), 225)
        let diagonal: JSON = ["fromX": 0, "fromY": 0, "toX": 300, "toY": 400, "velocity": 1000]
        XCTAssertEqual(NativeServicesWDA.dragMilliseconds(diagonal), 500)
        XCTAssertEqual(NativeServicesWDA.dragMilliseconds(nil), 80)
    }

    func testHumanizedPointerActionsKeepEveryPointAndRelativeTime() throws {
        let wda = NativeServicesWDA(screen: CGSize(width: 401, height: 801))
        let source: JSON = [
            "type": "pointer",
            "parameters": ["pointerType": "touch"],
            "actions": [
                ["type": "pointerMove", "duration": 0, "x": 100.25, "y": 200.25],
                ["type": "pointerDown", "button": 0],
                ["type": "pause", "duration": 30],
                ["type": "pointerMove", "duration": 45, "x": 101.75, "y": 201.75],
                ["type": "pointerUp", "button": 0],
            ],
        ]

        let points = try wda.finger(source)

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0]["x"] as? Int, 16_424)
        XCTAssertEqual(points[0]["y"] as? Int, 16_404)
        XCTAssertEqual(points[0]["time_ms"] as? Double, 0)
        XCTAssertEqual(points[1]["x"] as? Int, 16_424)
        XCTAssertEqual(points[1]["time_ms"] as? Double, 30)
        XCTAssertEqual(points[2]["x"] as? Int, 16_671)
        XCTAssertEqual(points[2]["y"] as? Int, 16_527)
        XCTAssertEqual(points[2]["time_ms"] as? Double, 75)
    }
}
