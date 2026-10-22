import XCTest
@testable import DesktopPet

final class MotionTests: XCTestCase {
    func testSleepIsBasedOnInteractionNotFrameCount() {
        var motion = PetMotion(now: 100, autoNap: .thirtySeconds)
        motion.advance(now: 129.9)
        XCTAssertNil(motion.sleepStarted)
        motion.advance(now: 135)
        XCTAssertEqual(motion.sleepStarted, 130)
        XCTAssertEqual(motion.pose(now: 135).sleep, 1)
        motion.click(now: 136)
        XCTAssertNil(motion.sleepStarted)
        motion.advance(now: 165)
        XCTAssertNil(motion.sleepStarted)
    }

    func testDragWakesAndLandingCanBeInterrupted() {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 1)
        motion.click(now: 2)
        motion.beginDrag(now: 2.1)
        XCTAssertNil(motion.sleepStarted)
        XCTAssertNil(motion.reactionStarted)
        motion.advance(now: 100)
        XCTAssertNil(motion.sleepStarted)
        motion.endDrag(now: 101)
        XCTAssertNotEqual(motion.pose(now: 101.065).squash, 0)
        motion.beginDrag(now: 101.1)
        XCTAssertEqual(motion.pose(now: 101.1).squash, 0)
    }

    func testSpringStartsAndEndsAtRestAndDecays() {
        XCTAssertEqual(PetMotion.landing(at: 0), 0)
        XCTAssertEqual(PetMotion.landing(at: 1.25), 0)
        XCTAssertEqual(PetMotion.landing(at: 3), 0)
        XCTAssertLessThan(abs(PetMotion.landing(at: 0.7)), abs(PetMotion.landing(at: 0.07)))
        for step in 0...125 {
            XCTAssertLessThanOrEqual(abs(PetMotion.landing(at: Double(step) / 100)), 0.17)
        }
    }

    func testRepeatedClicksAreBoundedAndAffectionExpires() {
        var motion = PetMotion(now: 0)
        for step in 0...100 { motion.click(now: Double(step) / 100) }
        XCTAssertEqual(motion.reactionStarted, 1)
        XCTAssertGreaterThan(motion.pose(now: 4).affection, 0)
        XCTAssertEqual(motion.pose(now: 8).affection, 0)
    }

    func testReducedMotionDisablesBreathingAndSpring() {
        var motion = PetMotion(now: 0)
        motion.beginDrag(now: 1)
        motion.endDrag(now: 2)
        motion.click(now: 2.02)
        let pose = motion.pose(now: 2.1, reducedMotion: true)
        XCTAssertEqual(pose.breath, 0)
        XCTAssertEqual(pose.squash, 0)
        XCTAssertGreaterThan(pose.affection, 0)
    }

    func testWakeFadesSleepRatherThanJumping() {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 1)
        let asleep = motion.pose(now: 3).sleep
        motion.click(now: 3)
        XCTAssertEqual(motion.pose(now: 3).sleep, asleep)
        XCTAssertGreaterThan(motion.pose(now: 3.2).sleep, 0)
        XCTAssertLessThan(motion.pose(now: 3.2).sleep, asleep)
        XCTAssertEqual(motion.pose(now: 3.9).sleep, 0)
    }




    func testBlushContinuesFromCurrentLevelOnClickAndBuildsUp() {
        var motion = PetMotion(now: 0)
        motion.click(now: 0)
        let before = motion.pose(now: 0.7).affection
        motion.click(now: 0.7)
        XCTAssertEqual(motion.pose(now: 0.7).affection, before, accuracy: 0.000001)
        let warmer = motion.pose(now: 1.2).affection
        XCTAssertGreaterThan(warmer, before)
        motion.click(now: 1.2)
        XCTAssertEqual(motion.pose(now: 1.2).affection, warmer, accuracy: 0.000001)
        XCTAssertGreaterThan(motion.pose(now: 1.8).affection, warmer)
        XCTAssertEqual(motion.pose(now: 10).affection, 0)
    }

    func testClickDuringFadeAndDragDoNotFlashBlushOff() {
        var motion = PetMotion(now: 0)
        motion.click(now: 0)
        let fading = motion.pose(now: 3).affection
        XCTAssertGreaterThan(fading, 0)
        motion.click(now: 3)
        XCTAssertEqual(motion.pose(now: 3).affection, fading, accuracy: 0.000001)
        XCTAssertGreaterThan(motion.pose(now: 3.5).affection, fading)
        let beforeDrag = motion.pose(now: 3.6).affection
        motion.beginDrag(now: 3.6)
        XCTAssertEqual(motion.pose(now: 3.6).affection, beforeDrag, accuracy: 0.000001)
    }

    func testSleepClosesEyesBeforeBubbleAndLetters() {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 0)
        let drowsy = motion.pose(now: 0.65)
        XCTAssertGreaterThan(drowsy.sleep, 0)
        XCTAssertLessThan(drowsy.sleep, 1)
        XCTAssertEqual(drowsy.sleepBubble, 0)
        XCTAssertEqual(drowsy.sleepLetters, 0)
        let settling = motion.pose(now: 1.3)
        XCTAssertGreaterThan(settling.sleepBubble, 0)
        XCTAssertEqual(settling.sleepLetters, 0)
        let asleep = motion.pose(now: 3)
        XCTAssertEqual(asleep.sleep, 1)
        XCTAssertEqual(asleep.sleepBubble, 1)
        XCTAssertEqual(asleep.sleepLetters, 1)
    }

    func testWakeShrinksBubbleBeforeFullyOpeningEyesAndIsNotRestarted() {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 0)
        motion.wake(now: 3)
        let waking = motion.pose(now: 3.45)
        XCTAssertEqual(waking.sleepBubble, 0, accuracy: 0.000001)
        XCTAssertGreaterThan(waking.sleep, 0)
        motion.click(now: 3.45)
        motion.click(now: 3.6)
        let awake = motion.pose(now: 4.2)
        XCTAssertEqual(awake.sleep, 0)
        XCTAssertEqual(awake.sleepBubble, 0)
        XCTAssertEqual(awake.sleepLetters, 0)
        XCTAssertEqual(awake.sleepSettle, 0)
        XCTAssertEqual(awake.wakeStretch, 0, accuracy: 0.000001)
    }

    func testRestTransitionsCanBeInterruptedWithoutJumping() {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 0)
        let beforeWake = motion.pose(now: 1.2)
        motion.wake(now: 1.2)
        assertRestEqual(beforeWake, motion.pose(now: 1.2))
        let beforeSleep = motion.pose(now: 1.5)
        motion.sleep(now: 1.5)
        assertRestEqual(beforeSleep, motion.pose(now: 1.5))
        let beforeDrag = motion.pose(now: 1.7)
        motion.beginDrag(now: 1.7)
        assertRestEqual(beforeDrag, motion.pose(now: 1.7))
        let reduced = motion.pose(now: 1.8, reducedMotion: true)
        XCTAssertEqual(reduced.sleepSettle, 0)
        XCTAssertEqual(reduced.wakeStretch, 0)
        XCTAssertEqual(reduced.breath, 0)
    }

    private func assertRestEqual(_ first: PetPose, _ second: PetPose, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(first.sleep, second.sleep, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(first.sleepBubble, second.sleepBubble, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(first.sleepLetters, second.sleepLetters, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(first.sleepSettle, second.sleepSettle, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(first.wakeStretch, second.wakeStretch, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(first.sleepAge, second.sleepAge, accuracy: 0.000001, file: file, line: line)
    }
}
