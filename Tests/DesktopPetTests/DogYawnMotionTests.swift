import XCTest
@testable import DesktopPet

final class DogYawnMotionTests: XCTestCase {
    private func dog() -> PetMotion {
        var result = PetMotion(now: 0, autoNap: .thirtySeconds)
        result.dogYawnEnabled = true
        return result
    }

    func testManualNapPlaysOnceThenHandsOffToSleep() {
        var motion = dog()
        motion.sleep(now: 1)
        motion.sleep(now: 2)
        XCTAssertEqual(motion.pose(now: 2).yawn?.time, 1)
        XCTAssertEqual(motion.pose(now: 4.4).sleepBubble, 0)
        XCTAssertEqual(motion.pose(now: 4.4).sleepLetters, 0)
        XCTAssertTrue(motion.isAnimatingQuickly(now: 4.8))
        let finished = 1 + DogYawnMotion.duration + 0.8
        XCTAssertNil(motion.pose(now: finished).yawn)
        XCTAssertEqual(motion.pose(now: finished).sleep, 1)
        XCTAssertEqual(motion.pose(now: finished).sleepBubble, 1)
        XCTAssertFalse(motion.isAnimatingQuickly(now: finished))
        motion.advance(now: finished + 100)
        XCTAssertNil(motion.pose(now: finished + 100).yawn)
    }

    func testAutomaticNapUsesSameTimelineAndDoesNotReplayAfterLongAbsence() {
        var motion = dog()
        motion.advance(now: 31)
        XCTAssertEqual(motion.pose(now: 31).yawn?.time, 1)
        motion.advance(now: 100)
        XCTAssertNil(motion.pose(now: 100).yawn)
    }

    func testInputCancelsFromCurrentFrameWithoutRestartingFadeOrFlashingBubble() {
        var motion = dog()
        motion.sleep(now: 1)
        let before = motion.pose(now: 2.2).yawn!
        motion.inputActivity(now: 2.2)
        XCTAssertNil(motion.sleepStarted)
        XCTAssertEqual(motion.pose(now: 2.2).yawn?.time, before.time)
        XCTAssertEqual(motion.pose(now: 2.2).yawn?.weight, before.weight)
        XCTAssertEqual(motion.pose(now: 2.2).sleepBubble, 0)
        let faded = motion.pose(now: 2.3).yawn!
        motion.inputActivity(now: 2.3)
        XCTAssertEqual(motion.pose(now: 2.3).yawn?.weight, faded.weight)
        XCTAssertEqual(faded.time, before.time)
        XCTAssertLessThan(faded.weight, before.weight)
        XCTAssertNil(motion.pose(now: 2.5).yawn)
    }

    func testClickAndDragInterruptAndNextSleepCanPlayAgain() {
        var motion = dog()
        motion.sleep(now: 0)
        motion.click(now: 1)
        XCTAssertNil(motion.pose(now: 1.3).yawn)
        motion.sleep(now: 3)
        XCTAssertEqual(motion.pose(now: 4).yawn?.time, 1)
        motion.beginDrag(now: 4)
        motion.advance(now: 100)
        XCTAssertNil(motion.sleepStarted)
        XCTAssertNil(motion.pose(now: 100).yawn)
    }

    func testReducedMotionAndUnavailableArtworkKeepExistingSleep() {
        var motion = dog()
        motion.sleep(now: 0)
        XCTAssertNil(motion.pose(now: 2, reducedMotion: true).yawn)
        XCTAssertEqual(motion.pose(now: 2, reducedMotion: true).sleepBubble, 1)
        var fallback = PetMotion(now: 0)
        fallback.sleep(now: 0)
        XCTAssertNil(fallback.pose(now: 1).yawn)
        XCTAssertGreaterThan(fallback.pose(now: 1).sleepBubble, 0)
    }
}
