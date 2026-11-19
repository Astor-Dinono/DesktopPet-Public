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

    func testReturningToSleepDuringWakePreservesTheDisplayedYawnAndDecorations() {
        for wakeTime in [0.08, 0.5, 1.2, 3.4, 4.15, 5.0] {
            for delay in [0.02, 0.1, 0.23, 0.3, 0.95] {
                var motion = dog()
                motion.sleep(now: 0)
                motion.wake(now: wakeTime)
                let time = wakeTime + delay
                let before = motion.pose(now: time)
                motion.sleep(now: time)
                let after = motion.pose(now: time)
                assertContinuous(before, after)
                XCTAssertEqual(before.yawn?.time, after.yawn?.time)
                let finished = motion.pose(now: time + 3)
                XCTAssertNil(finished.yawn, "A quick return to sleep must not replay the clip")
                XCTAssertEqual(finished.sleep, 1)
                XCTAssertEqual(finished.sleepBubble, 1)
                XCTAssertEqual(finished.sleepLetters, 1)
            }
        }
    }

    func testRepeatedSleepWakeInterruptionsRemainContinuousAndCanPlayAgainAfterWaking() {
        var motion = dog()
        motion.sleep(now: 0)
        for time in [1.2, 1.27, 1.33, 1.5, 1.65, 1.8] {
            let before = motion.pose(now: time)
            if motion.sleepStarted == nil { motion.sleep(now: time) }
            else { motion.wake(now: time) }
            assertContinuous(before, motion.pose(now: time))
        }
        motion.wake(now: 3)
        motion.sleep(now: 5)
        XCTAssertEqual(motion.pose(now: 6).yawn?.time, 1)
        XCTAssertEqual(motion.pose(now: 6).yawn?.weight, 1)
        XCTAssertNil(motion.pose(now: 5 + DogYawnMotion.duration + DogYawnMotion.handoff + 0.000001).yawn)
    }

    func testYawnInterruptionsAndSleepingHoverHaveNoPositionJump() {
        for time in [0.03, 0.08, 0.16, 0.5, 1.2, 2.4, 3.4, 4.1, 4.25] {
            for action in 0...3 {
                var motion = dog()
                motion.sleep(now: 0)
                let before = motion.pose(now: time)
                switch action {
                case 0: motion.click(now: time)
                case 1: motion.stroke(now: time, bounces: true)
                case 2: motion.beginDrag(now: time)
                default: motion.sootheSleeping(now: time)
                }
                assertContinuous(before, motion.pose(now: time))
            }
        }
    }

    private func assertContinuous(_ before: PetPose, _ after: PetPose,
                                  file: StaticString = #filePath, line: UInt = #line) {
        for channel in [\PetPose.breath, \.sleep, \.sleepBubble, \.sleepLetters,
                        \.sleepSettle, \.wakeStretch, \.affection, \.squash] {
            XCTAssertEqual(before[keyPath: channel], after[keyPath: channel], accuracy: 1e-12,
                           file: file, line: line)
        }
        XCTAssertEqual(before.yawn?.weight ?? 0, after.yawn?.weight ?? 0, accuracy: 1e-12,
                       file: file, line: line)
    }
}
