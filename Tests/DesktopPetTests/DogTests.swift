import AppKit
import XCTest
@testable import DesktopPet

final class DogTests: XCTestCase {
    func testShortBaselineLeavesOldEndsTransparentInEveryOrientationAndTopbar() async {
        await MainActor.run {
            for scale in [DogSize.tiny.scale, 0.5, 0.62, 0.75] {
                let size = NSSize(width: 260 * scale, height: 148 * scale)
                XCTAssertEqual(DogSize.tiny.scale, 0.3678859203570799, accuracy: 1e-12)
                let edge = 1 + DogRenderer.baselineY * scale
                for orientation in DogOrientation.allCases {
                    let view = PetView(frame: NSRect(origin: .zero, size: orientation.rotatedSize(size)))
                    view.orientation = orientation
                    let turn = orientation.transform(size: size)
                    for x in [0.0, 8.0, 250.0, 260.0] {
                        XCTAssertFalse(view.containsInteraction(NSPoint(x: x * scale, y: edge).applying(turn)))
                    }
                    for x in [DogRenderer.baselineRange.lowerBound, DogRenderer.baselineRange.upperBound] {
                        let point = NSPoint(x: x * scale, y: edge).applying(turn)
                        XCTAssertTrue(view.containsInteraction(point))
                        XCTAssertFalse(view.containsInteraction(point, includesBaseline: false))
                    }
                    let layout = DogLayout(scale: scale, orientation: orientation, counterInside: true)
                    let center = NSPoint(x: 130 * scale, y: edge).applying(turn)
                    XCTAssertEqual(layout.baselineAnchor.x - layout.petFrame.minX, center.x, accuracy: 1e-8)
                    XCTAssertEqual(layout.baselineAnchor.y - layout.petFrame.minY, center.y, accuracy: 1e-8)
                }
                let topSize = DogTopbarRenderer.drawingSize(scale: scale, bandHeight: 38)
                let top = DogTopbarRenderer.layout(size: topSize, scale: scale)
                for (x, hit) in [(0.0, false), (260.0, false),
                                  (DogRenderer.baselineRange.lowerBound, true), (DogRenderer.baselineRange.upperBound, true)] {
                    let point = NSPoint(x: top.offset.x + x * scale,
                        y: top.offset.y + (1 + DogRenderer.baselineY) * scale)
                    XCTAssertEqual(DogTopbarRenderer.contains(point, size: topSize, pose: PetPose(),
                        tail: TailPose(angle: 0, bend: 0), tailSize: .small, scale: scale), hit)
                }
            }
        }
    }

    func testBaselineRoundCapsAreHitButTrimmedMarginsAreNot() async {
        await MainActor.run {
            let left = DogRenderer.baselineRange.lowerBound
            let right = DogRenderer.baselineRange.upperBound
            for (x, y, hit) in [(left - 1.2, 0.0, true), (right + 1.2, 0.0, true),
                                (left - 1.3, 0.0, false), (right + 1.3, 0.0, false),
                                (left - 1.1, -1.1, false)] {
                XCTAssertEqual(DogRenderer.contains(NSPoint(x: x, y: 1 + DogRenderer.baselineY + y),
                    size: DogRenderer.canvas), hit)
            }
        }
    }

    func testApprovedEarRibbonIsCachedAndJoinsAtFullOuterInkWidth() async {
        await MainActor.run {
            let ears = DogRenderer.earLines
            XCTAssertTrue(ears === DogRenderer.earLines)
            XCTAssertEqual((0..<ears.elementCount).filter { ears.element(at: $0) == .closePath }.count, 2)
            func point(_ index: Int) -> NSPoint {
                var points = [NSPoint](repeating: .zero, count: 3)
                _ = ears.element(at: index, associatedPoints: &points)
                return points[0]
            }
            for offset in [0, 275] {
                let rimLeft = point(offset + 128), rimRight = point(offset + 129)
                XCTAssertEqual(hypot(rimLeft.x - rimRight.x, rimLeft.y - rimRight.y), 3.6, accuracy: 1e-8)
                let startLeft = point(offset), startRight = point(offset + 257)
                XCTAssertEqual(hypot(startLeft.x - startRight.x, startLeft.y - startRight.y), 2.85, accuracy: 1e-8)
                XCTAssertEqual(ears.element(at: offset + 274), .closePath)
            }
        }
    }

    func testRefinedTailRetainsBothSizesAndFixedRootWithoutChangingDeformation() async {
        await MainActor.run {
            let scale = 260.0 / 749
            let root = NSPoint(x: 574 * scale, y: (268 - 280) * scale + DogRenderer.baselineY)
            for bend in [-0.36, 0, 0.36] {
                let large = DogRenderer.tailPath(bend: bend, tailSize: .original)
                let small = DogRenderer.tailPath(bend: bend, tailSize: .small)
                for index in 0..<large.elementCount {
                    var a = [NSPoint](repeating: .zero, count: 3)
                    var b = a
                    let kind = large.element(at: index, associatedPoints: &a)
                    XCTAssertEqual(small.element(at: index, associatedPoints: &b), kind)
                    for j in 0..<(kind == .curveTo ? 3 : kind == .closePath ? 0 : 1) {
                        XCTAssertEqual(b[j].x, root.x + (a[j].x - root.x) * 0.8, accuracy: 1e-8)
                        XCTAssertEqual(b[j].y, root.y + (a[j].y - root.y) * 0.8, accuracy: 1e-8)
                    }
                }
            }
            var points = [NSPoint](repeating: .zero, count: 3)
            _ = DogRenderer.tailPath(tailSize: .original).element(at: 2, associatedPoints: &points)
            XCTAssertEqual(points[1].y, points[2].y, accuracy: 1e-8, "The upper tip has a horizontal tangent")
            XCTAssertEqual(points[2].x, 650 * scale, accuracy: 1e-8)
        }
    }

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
