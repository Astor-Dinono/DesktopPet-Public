import XCTest
@testable import DesktopPet

final class DogTests: XCTestCase {
    func testTailSizeDefaultsSafelyAndPreservesOriginalChoice() {
        for value in [nil, 0, -1, 99, 101] as [Int?] {
            XCTAssertEqual(DogTailSize(storedValue: value), .small)
        }
        XCTAssertEqual(DogTailSize(storedValue: 80), .small)
        XCTAssertEqual(DogTailSize(storedValue: 100), .original)
    }

    func testTailStartsAndEndsAtRestAndStaysBounded() {
        var motion = DogMotion()
        motion.wag(now: 0)
        XCTAssertEqual(motion.angle(now: 0), 0)
        XCTAssertNotEqual(motion.angle(now: 0.3), 0)
        for tick in 0...140 {
            XCTAssertLessThanOrEqual(abs(motion.angle(now: Double(tick) / 100)), 0.26)
        }
        XCTAssertFalse(motion.isMoving(now: 2))
        XCTAssertEqual(motion.angle(now: 2), 0)
        XCTAssertEqual(motion.angle(now: 0.3, reducedMotion: true), 0)
    }

    func testRetriggerPreservesCurrentTailPosition() {
        var motion = DogMotion()
        motion.wag(now: 0)
        let before = motion.angle(now: 0.85)
        motion.wag(now: 0.85)
        XCTAssertEqual(motion.angle(now: 0.85), before, accuracy: 0.000001)
        XCTAssertTrue(motion.isMoving(now: 1.5))
        XCTAssertEqual(motion.angle(now: 3), 0)
    }

    func testRestingTailDecaysWithoutJumpAndCanBeRetriggered() {
        var motion = DogMotion()
        motion.wag(now: 0)
        let beforeRest = motion.angle(now: 0.3)
        motion.settle(now: 0.3)
        XCTAssertEqual(motion.angle(now: 0.3), beforeRest, accuracy: 0.000001)
        XCTAssertEqual(motion.angle(now: 0.76), 0)
        XCTAssertFalse(motion.isMoving(now: 0.76))

        var interrupted = DogMotion()
        interrupted.wag(now: 0)
        interrupted.settle(now: 0.3)
        let beforeWag = interrupted.angle(now: 0.45)
        interrupted.wag(now: 0.45)
        XCTAssertEqual(interrupted.angle(now: 0.45), beforeWag, accuracy: 0.000001)
        XCTAssertTrue(interrupted.isMoving(now: 0.8))
        XCTAssertEqual(interrupted.angle(now: 3), 0)
    }

    func testBlinkIsBriefBoundedAndRespectsReducedMotion() {
        XCTAssertEqual(DogMotion.blink(now: 5.19), 0)
        XCTAssertEqual(DogMotion.blink(now: 5.30), 1, accuracy: 0.000001)
        XCTAssertEqual(DogMotion.blink(now: 5.49), 0)
        XCTAssertEqual(DogMotion.blink(now: 5.30, reducedMotion: true), 0)
        for tick in 0...1460 {
            let blink = DogMotion.blink(now: Double(tick) / 100)
            XCTAssertTrue((0...1).contains(blink))
        }
    }

    func testTailTipFlexesIndependentlyAndReducedMotionStopsBothChannels() {
        var motion = DogMotion()
        motion.wag(now: 0)
        let lively = motion.pose(now: 0.10)
        XCTAssertNotEqual(lively.angle, 0)
        XCTAssertNotEqual(lively.bend, 0)
        for tick in 0...140 {
            let pose = motion.pose(now: Double(tick) / 100)
            XCTAssertLessThanOrEqual(abs(pose.angle), 0.21)
            XCTAssertLessThanOrEqual(abs(pose.bend), 0.36)
        }
        let still = motion.pose(now: 0.10, reducedMotion: true)
        XCTAssertEqual(still.angle, 0)
        XCTAssertEqual(still.bend, 0)
        XCTAssertEqual(motion.pose(now: 1.5).bend, 0)
    }

    func testRetriggerAndSettlePreservePositionAndVelocityOfRootAndTip() {
        for time in [0.06, 0.3, 0.7, 1.17] {
            for settle in [false, true] {
                var motion = DogMotion()
                motion.wag(now: 0)
                let h = 0.000001
                let previous = motion.pose(now: time - h)
                let before = motion.pose(now: time)
                if settle { motion.settle(now: time) } else { motion.wag(now: time) }
                let after = motion.pose(now: time)
                let next = motion.pose(now: time + h)
                XCTAssertEqual(before.angle, after.angle, accuracy: 0.000001)
                XCTAssertEqual(before.bend, after.bend, accuracy: 0.000001)
                XCTAssertEqual((before.angle - previous.angle) / h, (next.angle - after.angle) / h, accuracy: 0.001)
                XCTAssertEqual((before.bend - previous.bend) / h, (next.bend - after.bend) / h, accuracy: 0.001)
            }
        }
    }
}
