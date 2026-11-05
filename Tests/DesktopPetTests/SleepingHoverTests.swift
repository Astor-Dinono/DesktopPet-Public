import XCTest
@testable import DesktopPet

final class SleepingHoverTests: XCTestCase {
    func testSleepingStrokesPreserveYawnAndBlushFadesNormally() {
        var motion = PetMotion(now: 0)
        motion.dogYawnEnabled = true
        motion.sleep(now: 1)
        for time in [2.0, 2.4, 2.8] { motion.sootheSleeping(now: time) }
        XCTAssertEqual(motion.sleepStarted, 1)
        XCTAssertEqual(motion.lastInteraction, 0)
        XCTAssertEqual(motion.pose(now: 3).yawn?.time, 2)
        XCTAssertEqual(motion.pose(now: 3).squash, 0)
        XCTAssertGreaterThan(motion.pose(now: 5).affection, 0)
        XCTAssertEqual(motion.pose(now: 9).affection, 0)
        XCTAssertEqual(motion.pose(now: 9).sleep, 1)
    }

    func testHoverPreservesAutomaticSleepClassificationAndInputWake() {
        var motion = PetMotion(now: 0, autoNap: .thirtySeconds)
        motion.advance(now: 35)
        motion.sootheSleeping(now: 36)
        XCTAssertEqual(motion.sleepStarted, 30)
        motion.setAutoNap(.off, now: 37)
        XCTAssertNil(motion.sleepStarted)
        motion.sleep(now: 40)
        motion.sootheSleeping(now: 43)
        motion.inputActivity(now: 44)
        XCTAssertNil(motion.sleepStarted)
        motion.sleep(now: 50)
        motion.sootheSleeping(now: 53)
        motion.beginDrag(now: 54)
        XCTAssertNil(motion.sleepStarted)
    }
}
