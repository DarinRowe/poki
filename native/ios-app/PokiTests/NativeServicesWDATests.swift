import PokiCore
import XCTest
@testable import Poki

final class NativeServicesWDATests: XCTestCase {
    func testHumanizedPointerActionsKeepEveryPointAndRelativeTime() throws {
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

        let points = try NativeServicesWDA.finger(source)

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0]["x"] as? Int, 100)
        XCTAssertEqual(points[0]["y"] as? Int, 200)
        XCTAssertEqual(points[0]["time_ms"] as? Double, 0)
        XCTAssertEqual(points[1]["x"] as? Int, 100)
        XCTAssertEqual(points[1]["time_ms"] as? Double, 30)
        XCTAssertEqual(points[2]["x"] as? Int, 102)
        XCTAssertEqual(points[2]["y"] as? Int, 202)
        XCTAssertEqual(points[2]["time_ms"] as? Double, 75)
    }
}
