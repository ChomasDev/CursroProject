import XCTest
@testable import AiAndo

final class MouseFrenzyTrackerTests: XCTestCase {
    func testStillPointerIsCalm() {
        var tracker = MouseFrenzyTracker()
        tracker.add(x: 100, y: 100, time: 0)
        tracker.add(x: 100.5, y: 100.4, time: 0.2)
        tracker.add(x: 101, y: 100, time: 0.6)
        XCTAssertFalse(tracker.isFrantic)
        XCTAssertLessThan(tracker.distance, 10)
    }

    func testNormalMoveDoesNotTrigger() {
        var tracker = MouseFrenzyTracker()
        tracker.add(x: 0, y: 0, time: 0)
        tracker.add(x: 400, y: 80, time: 0.4)
        XCTAssertFalse(tracker.isFrantic)
    }

    func testThrashTriggers() {
        var tracker = MouseFrenzyTracker()
        var x = 0.0
        var direction = 1.0
        for step in 0..<12 {
            tracker.add(x: x, y: 200, time: Double(step) * 0.05)
            x += direction * 280
            direction *= -1
        }
        XCTAssertTrue(tracker.isFrantic)
        XCTAssertGreaterThanOrEqual(tracker.distance, 2400)
    }

    func testOldTravelFallsOutOfWindow() {
        var tracker = MouseFrenzyTracker()
        tracker.add(x: 0, y: 0, time: 0)
        tracker.add(x: 3000, y: 0, time: 0.2)
        XCTAssertTrue(tracker.isFrantic)
        tracker.add(x: 3000, y: 0, time: 1.2)
        tracker.add(x: 3020, y: 0, time: 1.3)
        XCTAssertFalse(tracker.isFrantic)
    }

    func testCopyStaysTheGenZLine() {
        XCTAssertEqual(
            MouseDizzyCopy.line,
            "Woooo cavallo calma che mi stai facendo venire mal di pancia"
        )
    }
}
