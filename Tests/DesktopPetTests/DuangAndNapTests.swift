import XCTest
@testable import DesktopPet

final class DuangAndNapTests: XCTestCase {
    func testClickAndLandingShareTheSameElasticRhythmWithASofterClick() {
        var click = PetMotion(now: 0)
        click.click(now: 0)
        var landing = PetMotion(now: 0)
        landing.beginDrag(now: 0)
        landing.endDrag(now: 0)
        for time in [0.065, 0.23, 0.39, 0.55] {
            let touched = click.pose(now: time).squash
            let dropped = landing.pose(now: time).squash
            XCTAssertGreaterThan(touched * dropped, 0)
            XCTAssertLessThan(abs(touched), abs(dropped))
        }
        XCTAssertEqual(click.pose(now: 1.25).squash, 0)
        XCTAssertEqual(landing.pose(now: 1.25).squash, 0)
    }

    func testClickDuringBouncePreservesPositionAndVelocity() {
        for time in [0.03, 0.065, 0.16, 0.4, 0.95] {
            var motion = PetMotion(now: 0)
            motion.click(now: 0)
            let epsilon = 0.000001
            let before = motion.pose(now: time).squash
            let velocity = (motion.pose(now: time + epsilon).squash - motion.pose(now: time - epsilon).squash) / (2 * epsilon)
            motion.click(now: time)
            XCTAssertEqual(motion.pose(now: time).squash, before, accuracy: 0.0000001)
            let afterVelocity = (motion.pose(now: time + epsilon).squash - before) / epsilon
            XCTAssertEqual(afterVelocity, velocity, accuracy: 0.001)
        }
    }

    func testRapidClicksStayBoundedAndReducedMotionRemainsStill() {
        var motion = PetMotion(now: 0)
        for step in 0..<1000 {
            let time = Double(step) / 200
            motion.click(now: time)
            XCTAssertLessThanOrEqual(abs(motion.pose(now: time + 0.002).squash), 0.20)
            XCTAssertEqual(motion.pose(now: time + 0.002, reducedMotion: true).squash, 0)
        }
        XCTAssertEqual(motion.pose(now: 7).squash, 0)
    }

    func testEveryNapDurationUsesLastActivityAndOffNeverAutoSleeps() {
        for option in AutoNap.allCases {
            var motion = PetMotion(now: 0, autoNap: option)
            motion.inputActivity(now: 20)
            if let delay = option.delay {
                motion.advance(now: 20 + delay - 0.01)
                XCTAssertNil(motion.sleepStarted)
                motion.advance(now: 20 + delay)
                XCTAssertEqual(motion.sleepStarted, 20 + delay)
            } else {
                motion.advance(now: 100_000)
                XCTAssertNil(motion.sleepStarted)
            }
        }
    }

    func testChangingNapTimeStartsAFreshCountdown() {
        var motion = PetMotion(now: 0, autoNap: .fiveMinutes)
        motion.setAutoNap(.thirtySeconds, now: 200)
        motion.advance(now: 229.99)
        XCTAssertNil(motion.sleepStarted)
        motion.advance(now: 230)
        XCTAssertEqual(motion.sleepStarted, 230)
    }

    func testDisablingNapWakesAutomaticSleepButKeepsManualSleepAvailable() {
        var motion = PetMotion(now: 0, autoNap: .thirtySeconds)
        motion.advance(now: 35)
        XCTAssertNotNil(motion.sleepStarted)
        motion.setAutoNap(.off, now: 36)
        XCTAssertNil(motion.sleepStarted)
        motion.advance(now: 1000)
        XCTAssertNil(motion.sleepStarted)
        motion.sleep(now: 1001)
        motion.setAutoNap(.off, now: 1002)
        XCTAssertEqual(motion.sleepStarted, 1001)
        motion.inputActivity(now: 1003)
        XCTAssertNil(motion.sleepStarted)
    }

    func testSavedNapValuesRestoreAndInvalidValuesUseThreeMinutes() {
        XCTAssertEqual(AutoNap(storedValue: nil), .threeMinutes)
        XCTAssertEqual(AutoNap(storedValue: -1), .threeMinutes)
        XCTAssertEqual(AutoNap(storedValue: 35), .threeMinutes)
        for option in AutoNap.allCases {
            XCTAssertEqual(AutoNap(storedValue: option.rawValue), option)
        }
    }
}
