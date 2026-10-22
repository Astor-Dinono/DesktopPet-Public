import AppKit
import XCTest
@testable import DesktopPet

final class TurnMotionTests: XCTestCase, @unchecked Sendable {
    func testNormalEdgeTurnsPlanOneContinuousPathInsideDesktopAndPreviewBounds() {
        for (size, area) in [(CGSize(width: 161.2, height: 91.76), CGRect(x: 2, y: 2, width: 362, height: 200)),
                             (CGSize(width: 130, height: 74), CGRect(x: 2, y: 2, width: 176, height: 200)),
                             (CGSize(width: 195, height: 111), CGRect(x: -500, y: 30, width: 1200, height: 870))] {
            let bounds = DogTurnBounds(canonicalSize: size, area: area, baseline: 1 + 3.8 * size.width / 260)
            for angle in [0.0, 90, 180, 270] {
                for proposed in [area.origin, CGPoint(x: area.maxX, y: area.maxY)] {
                    let from = bounds.center(proposed, angle: angle)
                    let target = bounds.center(from, angle: angle + 90)
                    let turn = DogTurnMotion(now: 0, from: DogTurnPose(angle: angle, center: from, badgeCenter: .zero),
                        targetAngle: angle + 90, center: target, badgeCenter: .zero, bounds: bounds)
                    XCTAssertTrue(turn.followsBoundsContinuously, "size \(size), angle \(angle), point \(proposed)")
                    for frame in 0...240 {
                        let pose = turn.pose(now: turn.duration * Double(frame) / 240)
                        let box = bounds.offsets(angle: pose.angle).offsetBy(dx: pose.center.x, dy: pose.center.y)
                        XCTAssertGreaterThanOrEqual(box.minX, area.minX - 0.00001)
                        XCTAssertGreaterThanOrEqual(box.minY, area.minY - 0.00001)
                        XCTAssertLessThanOrEqual(box.maxX, area.maxX + 0.00001)
                        XCTAssertLessThanOrEqual(box.maxY, area.maxY + 0.00001)
                    }
                    XCTAssertEqual(turn.pose(now: turn.duration).center, target)
                    XCTAssertEqual(turn.velocity(now: turn.duration).center, .zero)
                }
            }
        }
    }

    func testFittedTurnRetargetKeepsItsActualPositionAndVelocity() {
        let bounds = DogTurnBounds(canonicalSize: CGSize(width: 130, height: 74),
            area: CGRect(x: 0, y: 0, width: 366, height: 204), baseline: 2.9)
        let start = bounds.center(CGPoint(x: 183, y: 0), angle: 0)
        let first = DogTurnMotion(now: 0, from: DogTurnPose(angle: 0, center: start, badgeCenter: .zero),
            targetAngle: 90, center: bounds.center(start, angle: 90), badgeCenter: .zero, bounds: bounds)
        let time = 0.2
        let before = first.pose(now: time), velocity = first.velocity(now: time)
        let next = DogTurnMotion(now: time, from: before, targetAngle: 180,
            center: bounds.center(before.center, angle: 180), badgeCenter: .zero, velocity: velocity, bounds: bounds)
        XCTAssertTrue(first.followsBoundsContinuously)
        XCTAssertTrue(next.followsBoundsContinuously)
        XCTAssertEqual(next.pose(now: time).center, before.center)
        XCTAssertEqual(next.velocity(now: time).center, velocity.center)
        let h = 0.000001
        XCTAssertEqual((next.pose(now: time + h).center.y - before.center.y) / h, velocity.center.y, accuracy: 0.01)
    }

    func testDraggingAnActiveTurnTranslatesItWithoutRestartingTheAnimation() {
        let turn = DogTurnMotion(now: 10, from: DogTurnPose(angle: 0, center: CGPoint(x: 200, y: 150), badgeCenter: .zero),
            targetAngle: 90, center: CGPoint(x: 230, y: 180), badgeCenter: CGPoint(x: 10, y: 10))
        let delta = CGPoint(x: 33.5, y: -15.25)
        let moved = turn.translated(by: delta)
        XCTAssertEqual(moved.started, turn.started)
        XCTAssertEqual(moved.duration, turn.duration)
        for time in [10.0, 10.12, 10.3, 11] {
            let a = turn.pose(now: time), b = moved.pose(now: time)
            XCTAssertEqual(a.angle, b.angle)
            XCTAssertEqual(b.center.x, a.center.x + delta.x, accuracy: 0.00001)
            XCTAssertEqual(b.center.y, a.center.y + delta.y, accuracy: 0.00001)
            XCTAssertEqual(moved.velocity(now: time).center, turn.velocity(now: time).center)
        }
    }

    func testDesktopRRequiresExplicitSelectionAndEndsWhenFocusIsLostOrEscapeIsPressed() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 130, height: 74),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let pet = PetView(frame: NSRect(x: 0, y: 0, width: 130, height: 74))
            panel.contentView = pet
            panel.becomesKeyOnlyIfNeeded = true
            var turns = 0
            pet.onRotationRequest = { turns += 1 }
            pet.onCancelSelection = { [weak panel] in panel?.clearRotationSelection() }
            func event(_ text: String = "r", repeating: Bool = false, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
                try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: text,
                    charactersIgnoringModifiers: text, isARepeat: repeating, keyCode: 0))
            }
            XCTAssertFalse(panel.canBecomeKey)
            pet.keyDown(with: try event())
            XCTAssertEqual(turns, 0)
            panel.selectForRotation(pet)
            XCTAssertTrue(panel.canBecomeKey)
            XCTAssertTrue(pet.isRotationSelected)
            pet.keyDown(with: try event())
            pet.keyDown(with: try event(repeating: true))
            pet.keyDown(with: try event(modifiers: .command))
            XCTAssertEqual(turns, 1)
            panel.resignKey()
            pet.keyDown(with: try event())
            XCTAssertFalse(pet.isRotationSelected)
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertEqual(turns, 1)
            panel.selectForRotation(pet)
            pet.keyDown(with: try event("\u{1b}"))
            XCTAssertFalse(pet.isRotationSelected)
            XCTAssertFalse(panel.canBecomeKey)
            pet.onRotationRequest = nil
            pet.onCancelSelection = nil
        }
    }

    func testTurnEasesFromRestAndEndsExactlyAtTheDestination() {
        let from = DogTurnPose(angle: 0, center: CGPoint(x: 20, y: 40), badgeCenter: CGPoint(x: 10, y: 4))
        let turn = DogTurnMotion(now: 2, from: from, targetAngle: 90,
            center: CGPoint(x: 50, y: 60), badgeCenter: CGPoint(x: 30, y: 20))
        XCTAssertEqual(turn.pose(now: 2).angle, 0)
        XCTAssertEqual(turn.velocity(now: 2).angle, 0)
        XCTAssertLessThan(turn.pose(now: 2.05).angle, 5)
        XCTAssertEqual(turn.pose(now: 2 + turn.duration / 2).angle, 45, accuracy: 0.00001)
        let end = turn.pose(now: 2 + turn.duration + 1)
        XCTAssertEqual(end.angle, 90)
        XCTAssertEqual(end.center, CGPoint(x: 50, y: 60))
        XCTAssertEqual(end.badgeCenter, CGPoint(x: 30, y: 20))
        XCTAssertEqual(turn.velocity(now: 2 + turn.duration).angle, 0, accuracy: 0.00001)
        XCTAssertTrue(turn.isFinished(now: 3))
    }

    func testShortestTurnDoesNotSpinAllTheWayAroundAtZeroDegrees() {
        for (angle, target, end) in [(270.0, 0.0, 360.0), (0.0, 270.0, -90.0),
                                    (350.0, 90.0, 450.0), (90.0, 270.0, 270.0)] {
            let turn = DogTurnMotion(now: 0,
                from: DogTurnPose(angle: angle, center: .zero, badgeCenter: .zero),
                targetAngle: target, center: .zero, badgeCenter: .zero)
            XCTAssertEqual(turn.pose(now: 1).angle, end)
            XCTAssertLessThanOrEqual(abs(end - angle), 180)
        }
    }

    func testRetargetPreservesAnglePositionAndVelocity() {
        let first = DogTurnMotion(now: 0,
            from: DogTurnPose(angle: 0, center: .zero, badgeCenter: .zero),
            targetAngle: 90, center: CGPoint(x: 30, y: 20), badgeCenter: CGPoint(x: 40, y: 20))
        for time in [0.08, 0.25, 0.45] {
            let before = first.pose(now: time)
            let velocity = first.velocity(now: time)
            let next = DogTurnMotion(now: time, from: before, targetAngle: 270,
                center: CGPoint(x: -20, y: 10), badgeCenter: CGPoint(x: -10, y: 10), velocity: velocity)
            XCTAssertEqual(next.pose(now: time).angle, before.angle)
            XCTAssertEqual(next.pose(now: time).center, before.center)
            XCTAssertEqual(next.pose(now: time).badgeCenter, before.badgeCenter)
            XCTAssertEqual(next.velocity(now: time).angle, velocity.angle, accuracy: 0.00001)
            XCTAssertEqual(next.velocity(now: time).center, velocity.center)
            let h = 0.000001
            XCTAssertEqual((next.pose(now: time + h).angle - before.angle) / h, velocity.angle, accuracy: 0.01)
        }
    }

    func testIntermediateAnglesKeepHitTestingAlignedWithTheHead() async {
        await MainActor.run {
            let canonical = NSSize(width: 130, height: 74)
            let side = DogTurnPresentation.enclosingSide(for: canonical)
            let pet = PetView(frame: NSRect(x: 0, y: 0, width: side, height: side))
            for angle in [0.0, 30, 45, 90, 135, 180, 225, 270, 315, 360] {
                let presentation = DogTurnPresentation(canonicalSize: canonical, angle: angle)
                pet.setTurnPresentation(presentation)
                let transform = presentation.transform(in: pet.bounds)
                XCTAssertTrue(pet.containsInteraction(NSPoint(x: 52, y: 20).applying(transform)))
                XCTAssertFalse(pet.containsInteraction(NSPoint(x: 4, y: 68).applying(transform)))
                for corner in [NSPoint.zero, NSPoint(x: 130, y: 0),
                               NSPoint(x: 0, y: 74), NSPoint(x: 130, y: 74)] {
                    XCTAssertTrue(pet.bounds.contains(corner.applying(transform)))
                }
            }
            pet.setTurnPresentation(nil)
            XCTAssertNil(pet.turnPresentation)
        }
    }

    func testVisibleHeadPivotStaysFixedThroughoutTheRotation() {
        let canonical = NSSize(width: 130, height: 74)
        let pivot = DogTurnPresentation.pivot(in: canonical)
        XCTAssertEqual(pivot, NSPoint(x: 54, y: 21))
        let fixed = NSPoint(x: 500, y: 400)
        let motion = DogTurnMotion(now: 0, from: DogTurnPose(angle: 0, center: fixed, badgeCenter: .zero),
            targetAngle: 180, center: fixed, badgeCenter: NSPoint(x: 550, y: 450))
        let side = DogTurnPresentation.enclosingSide(for: canonical)
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        for index in 0...60 {
            let pose = motion.pose(now: motion.duration * Double(index) / 60)
            let transform = DogTurnPresentation(canonicalSize: canonical, angle: pose.angle).transform(in: bounds)
            let visualPivot = pivot.applying(transform)
            XCTAssertEqual(visualPivot.x + pose.center.x - bounds.midX, fixed.x, accuracy: 0.00001)
            XCTAssertEqual(visualPivot.y + pose.center.y - bounds.midY, fixed.y, accuracy: 0.00001)
        }
    }

    func testTurnEndpointMatchesStaticDrawingWhenAnchoredByTheHeadPivot() {
        let canonical = NSSize(width: 130, height: 74)
        let pivot = DogTurnPresentation.pivot(in: canonical)
        let side = DogTurnPresentation.enclosingSide(for: canonical)
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        for orientation in DogOrientation.allCases {
            let staticTransform = orientation.transform(size: canonical)
            let staticPivot = pivot.applying(staticTransform)
            let animated = DogTurnPresentation(canonicalSize: canonical, angle: Double(orientation.rawValue)).transform(in: bounds)
            for point in [NSPoint.zero, pivot, NSPoint(x: 90, y: 60), NSPoint(x: 130, y: 74)] {
                let a = point.applying(animated)
                let b = point.applying(staticTransform)
                XCTAssertEqual(a.x - bounds.midX, b.x - staticPivot.x, accuracy: 0.00001)
                XCTAssertEqual(a.y - bounds.midY, b.y - staticPivot.y, accuracy: 0.00001)
            }
        }
    }

    func testNativeTopPlacementKeepsInkAlignedInsteadOfConstrainingTransparentPadding() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let screen = try XCTUnwrap(NSScreen.main)
            let panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            for scale in [0.5, 0.62, 0.75] {
                let placement = DogWindowPlacement(anchor: NSPoint(x: screen.visibleFrame.midX,
                    y: screen.visibleFrame.maxY), scale: scale, orientation: .top, visibleFrame: screen.visibleFrame)
                XCTAssertEqual(panel.constrainFrameRect(placement.frame, to: screen), placement.frame)
                let view = DogCompanionView(pet: PetView(frame: .zero), scale: scale)
                view.orientation = .top
                view.counterAboveDog = placement.counterAboveDog
                panel.contentView = view
                panel.setPetFrame(placement.frame)
                view.layoutSubtreeIfNeeded()
                let local = NSPoint(x: 130 * scale, y: 1 + DogRenderer.baselineY * scale)
                    .applying(DogOrientation.top.transform(size: NSSize(width: 260 * scale, height: 148 * scale)))
                let baseline = panel.convertPoint(toScreen: view.pet.convert(local, to: nil)).y
                XCTAssertEqual(baseline, screen.visibleFrame.maxY, accuracy: 0.00001)
                XCTAssertTrue(placement.counterAboveDog)
            }
        }
    }

    func testPressAndReleaseHooksBracketCaptureForInterruptingTurns() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 130, height: 74),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let pet = PetView(frame: NSRect(x: 0, y: 0, width: 130, height: 74))
            panel.contentView = pet
            var hooks: [String] = []
            pet.onPointerPress = { XCTAssertFalse(pet.hasPointerCapture); hooks.append("press") }
            pet.onPointerRelease = { XCTAssertFalse(pet.hasPointerCapture); hooks.append("release") }
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 52, y: 20),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            pet.mouseDown(with: down)
            XCTAssertTrue(pet.hasPointerCapture)
            pet.mouseUp(with: down)
            XCTAssertEqual(hooks, ["press", "release"])
            XCTAssertFalse(pet.hasPointerCapture)
            pet.onPointerPress = nil
            pet.onPointerRelease = nil
        }
    }
}
