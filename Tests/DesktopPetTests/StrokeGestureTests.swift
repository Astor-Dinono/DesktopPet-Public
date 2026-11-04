import Foundation
import CoreGraphics
import XCTest
@testable import DesktopPet

final class StrokeGestureTests: XCTestCase {
    func testHoverDwellAllowsGentleMovementButDiscardsEarlyTravel() {
        var hover = DogHoverGesture()
        XCTAssertFalse(hover.update(.zero, now: 0, inside: true, allowed: true))
        XCTAssertFalse(hover.update(CGPoint(x: 30, y: 0), now: 0.2, inside: true, allowed: true))
        XCTAssertFalse(hover.isArmed)
        XCTAssertFalse(hover.update(.zero, now: 0.35, inside: true, allowed: true))
        XCTAssertTrue(hover.isArmed)
        XCTAssertFalse(hover.update(CGPoint(x: 6, y: 0), now: 0.36, inside: true, allowed: true))
        XCTAssertTrue(hover.update(.zero, now: 0.37, inside: true, allowed: true))
        XCTAssertFalse(hover.update(.zero, now: 10, inside: true, allowed: true))
    }

    func testHoverPassingLeavingOrBlockedButtonsResetIntent() {
        for blockByLeaving in [false, true] {
            var hover = DogHoverGesture()
            XCTAssertFalse(hover.update(.zero, now: 0, inside: true, allowed: true))
            XCTAssertFalse(hover.update(CGPoint(x: 50, y: 0), now: 0.2, inside: true, allowed: true))
            XCTAssertFalse(hover.update(.zero, now: 0.3, inside: !blockByLeaving, allowed: blockByLeaving))
            XCTAssertFalse(hover.isArmed)
            XCTAssertFalse(hover.update(CGPoint(x: 20, y: 0), now: 1, inside: true, allowed: true))
            XCTAssertFalse(hover.update(.zero, now: 1.2, inside: true, allowed: true))
            XCTAssertFalse(hover.update(.zero, now: 1.36, inside: true, allowed: true))
            XCTAssertTrue(hover.update(CGPoint(x: 10, y: 0), now: 1.4, inside: true, allowed: true))
        }
    }

    func testStationaryHoverAndTinyJitterNeverPet() {
        var hover = DogHoverGesture()
        for index in 0...10_000 {
            XCTAssertFalse(hover.update(CGPoint(x: index % 2 == 0 ? -1 : 1, y: 0),
                now: Double(index) * 0.01, inside: true, allowed: true))
        }
        XCTAssertTrue(hover.isArmed)
        hover.cancel()
        XCTAssertFalse(hover.isArmed)
    }

    func testInvalidHoverClockAndPointDiscardArmedIntent() {
        for invalidPoint in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)] {
            var hover = DogHoverGesture()
            _ = hover.update(.zero, now: 0, inside: true, allowed: true)
            _ = hover.update(.zero, now: 0.4, inside: true, allowed: true)
            XCTAssertTrue(hover.isArmed)
            XCTAssertFalse(hover.update(invalidPoint, now: 0.5, inside: true, allowed: true))
            XCTAssertFalse(hover.isArmed)
        }
        for time in [-1.0, Double.nan, Double.infinity] {
            var hover = DogHoverGesture()
            _ = hover.update(.zero, now: 0, inside: true, allowed: true)
            _ = hover.update(.zero, now: 0.4, inside: true, allowed: true)
            XCTAssertFalse(hover.update(.zero, now: time, inside: true, allowed: true))
            XCTAssertFalse(hover.isArmed)
        }
    }

    func testClickAndStationaryHoldRespondOnlyOnceOnRelease() {
        var gesture = DogStrokeGesture()
        XCTAssertFalse(gesture.active)
        XCTAssertFalse(gesture.move(CGPoint(x: 20, y: 0), now: 1, inside: true))
        XCTAssertFalse(gesture.finish(.zero, inside: true))
        let point = CGPoint(x: 20, y: 30)
        gesture.begin(point, now: 0, inside: true)
        XCTAssertTrue(gesture.active)
        for i in 1...10_000 {
            XCTAssertFalse(gesture.move(point, now: Double(i) * 0.01, inside: true))
        }
        XCTAssertTrue(gesture.finish(point, inside: true))
        XCTAssertFalse(gesture.active)
        XCTAssertFalse(gesture.didStroke)
        XCTAssertFalse(gesture.finish(point, inside: true))
    }

    func testJitterDoesNotAccumulateIntoAStroke() {
        var gesture = DogStrokeGesture()
        gesture.begin(.zero, now: 0, inside: true)
        for i in 1...10_000 {
            XCTAssertFalse(gesture.move(CGPoint(x: i % 2 == 0 ? -1 : 1, y: 0),
                                        now: Double(i) * 0.01, inside: true))
        }
        XCTAssertFalse(gesture.didStroke)
        XCTAssertTrue(gesture.finish(.zero, inside: true))
    }

    func testShortStrokeNeverAddsAReleaseClickEvenWithoutPulse() {
        var gesture = DogStrokeGesture()
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertFalse(gesture.move(CGPoint(x: 4, y: 0), now: 0.1, inside: true))
        XCTAssertFalse(gesture.didStroke)
        XCTAssertFalse(gesture.move(CGPoint(x: 5, y: 0), now: 0.2, inside: true))
        XCTAssertTrue(gesture.didStroke)
        XCTAssertFalse(gesture.finish(.zero, inside: true))
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertFalse(gesture.finish(CGPoint(x: 5, y: 0), inside: true))
    }

    func testBackAndForthTravelWorksAndStationaryDebtCannotFire() {
        var gesture = DogStrokeGesture()
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertFalse(gesture.move(CGPoint(x: 6, y: 0), now: 0.01, inside: true))
        XCTAssertTrue(gesture.move(CGPoint(x: 1, y: 0), now: 0.02, inside: true))
        XCTAssertFalse(gesture.move(CGPoint(x: 7, y: 0), now: 0.05, inside: true))
        XCTAssertFalse(gesture.move(CGPoint(x: 1, y: 0), now: 0.06, inside: true))
        XCTAssertFalse(gesture.move(CGPoint(x: 1, y: 0), now: 10, inside: true))
        XCTAssertTrue(gesture.move(CGPoint(x: 2, y: 0), now: 10.01, inside: true))
        XCTAssertFalse(gesture.finish(CGPoint(x: 2, y: 0), inside: true))
    }

    func testFastInputIsBoundedWithoutQueuingExtraResponses() {
        var gesture = DogStrokeGesture()
        gesture.begin(.zero, now: 0, inside: true)
        var pulses = 0
        var lastPulse = -100.0
        for i in 1...10_000 {
            let time = Double(i) * 0.001
            let point = CGPoint(x: i % 2 == 0 ? -100_000 : 100_000, y: 0)
            if gesture.move(point, now: time, inside: true) {
                XCTAssertGreaterThanOrEqual(time - lastPulse, DogStrokeGesture.pulseInterval)
                lastPulse = time
                pulses += 1
            }
        }
        XCTAssertGreaterThan(pulses, 70)
        XCTAssertLessThanOrEqual(pulses, 84)
        XCTAssertFalse(gesture.move(CGPoint(x: -100_000, y: 0), now: 20, inside: true))
        XCTAssertFalse(gesture.finish(CGPoint(x: -100_000, y: 0), inside: true))
    }

    func testOutsideTravelAndReturnSegmentNeverPetTheDog() {
        var gesture = DogStrokeGesture()
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertFalse(gesture.move(CGPoint(x: 6, y: 0), now: 0.1, inside: true))
        XCTAssertFalse(gesture.move(CGPoint(x: 1_000, y: 0), now: 0.2, inside: false))
        XCTAssertFalse(gesture.move(CGPoint(x: 2_000, y: 0), now: 0.3, inside: false))
        XCTAssertFalse(gesture.move(.zero, now: 0.4, inside: true))
        XCTAssertFalse(gesture.move(CGPoint(x: 9, y: 0), now: 0.5, inside: true))
        XCTAssertTrue(gesture.move(CGPoint(x: 10, y: 0), now: 0.6, inside: true))
        XCTAssertFalse(gesture.finish(CGPoint(x: 10, y: 0), inside: true))
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertFalse(gesture.move(CGPoint(x: 1, y: 0), now: 0.1, inside: false))
        XCTAssertFalse(gesture.move(.zero, now: 0.2, inside: true))
        XCTAssertFalse(gesture.finish(.zero, inside: true))
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertFalse(gesture.finish(.zero, inside: false))
    }

    func testStartingOutsideAndCancellationDoNotLeaveState() {
        var gesture = DogStrokeGesture()
        gesture.begin(.zero, now: 0, inside: false)
        XCTAssertFalse(gesture.active)
        XCTAssertFalse(gesture.move(CGPoint(x: 20, y: 0), now: 1, inside: true))
        XCTAssertFalse(gesture.finish(CGPoint(x: 20, y: 0), inside: true))
        gesture.begin(.zero, now: 0, inside: true)
        XCTAssertTrue(gesture.move(CGPoint(x: 10, y: 0), now: 0.01, inside: true))
        gesture.cancel()
        XCTAssertFalse(gesture.active)
        XCTAssertFalse(gesture.didStroke)
        XCTAssertFalse(gesture.move(CGPoint(x: 20, y: 0), now: 1, inside: true))
        XCTAssertFalse(gesture.finish(CGPoint(x: 20, y: 0), inside: true))
        gesture.begin(.zero, now: 2, inside: true)
        XCTAssertTrue(gesture.move(CGPoint(x: 10, y: 0), now: 2.01, inside: true))
        gesture.begin(.zero, now: 2.02, inside: true)
        XCTAssertTrue(gesture.finish(.zero, inside: true))
    }

    func testLogicalCoordinatesAreIndependentOfScreenOriginAndRetinaScale() {
        for origin in [CGPoint.zero, CGPoint(x: -1_440, y: 900), CGPoint(x: 6_000, y: -1_000)] {
            for scale in [1.0, 1.25, 1.5, 2.0, 3.0] {
                func point(_ x: Double) -> CGPoint {
                    CGPoint(x: origin.x + x * scale / scale, y: origin.y + 20 * scale / scale)
                }
                var gesture = DogStrokeGesture()
                gesture.begin(point(100), now: 0, inside: true)
                XCTAssertFalse(gesture.move(point(106), now: 0.1, inside: true))
                XCTAssertTrue(gesture.move(point(101), now: 0.2, inside: true))
                XCTAssertFalse(gesture.finish(point(101), inside: true))
            }
        }
    }

    func testInvalidCoordinatesTimesAndReversedClockCancelSafely() {
        var gesture = DogStrokeGesture()
        for point in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)] {
            gesture.begin(point, now: 0, inside: true)
            XCTAssertFalse(gesture.active)
            gesture.begin(.zero, now: 0, inside: true)
            XCTAssertFalse(gesture.move(point, now: 1, inside: true))
            XCTAssertFalse(gesture.active)
            gesture.begin(.zero, now: 0, inside: true)
            XCTAssertFalse(gesture.finish(point, inside: true))
            XCTAssertFalse(gesture.active)
        }
        for time in [Double.nan, Double.infinity] {
            gesture.begin(.zero, now: time, inside: true)
            XCTAssertFalse(gesture.active)
            gesture.begin(.zero, now: 0, inside: true)
            XCTAssertFalse(gesture.move(CGPoint(x: 10, y: 0), now: time, inside: true))
            XCTAssertFalse(gesture.active)
        }
        gesture.begin(.zero, now: 10, inside: true)
        XCTAssertFalse(gesture.move(CGPoint(x: 10, y: 0), now: 9, inside: true))
        XCTAssertFalse(gesture.active)
        let huge = CGFloat.greatestFiniteMagnitude
        gesture.begin(CGPoint(x: huge, y: 0), now: 0, inside: true)
        XCTAssertFalse(gesture.move(CGPoint(x: -huge, y: 0), now: 1, inside: true))
        XCTAssertFalse(gesture.active)
    }
}
