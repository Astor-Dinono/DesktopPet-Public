import AppKit
import XCTest
@testable import DesktopPet

/// Exercises local AppKit event routing only. The panels are never shown and
/// PetView.start() is deliberately not called: no global input or clock runs.
final class PettingInteractionTests: XCTestCase, @unchecked Sendable {
    func testSleepingHoverBlushesWithoutWakingOrEmittingEffectsAndClickStillWakes() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            let now = ProcessInfo.processInfo.systemUptime
            f.pet.motion.sleep(now: now - 10)
            let began = f.pet.motion.sleepStarted
            f.routeHover(at: f.headA, time: 0)
            f.routeHover(at: f.headA, time: 0.36)
            f.routeHover(at: f.headB, time: 0.5)
            XCTAssertEqual(f.pet.motion.sleepStarted, began)
            let pose = f.pet.motion.pose(now: ProcessInfo.processInfo.systemUptime + 0.6)
            XCTAssertEqual(pose.sleep, 1)
            XCTAssertEqual(pose.sleepBubble, 1)
            XCTAssertGreaterThan(pose.affection, 0)
            XCTAssertEqual(pose.squash, 0)
            XCTAssertTrue(f.pets.isEmpty)
            XCTAssertFalse(f.pet.hasPointerCapture)
            try f.send(.leftMouseDown, at: f.headA)
            try f.send(.leftMouseUp, at: f.headA)
            XCTAssertNil(f.pet.motion.sleepStarted)
            XCTAssertEqual(f.pets.count, 1)
        }
    }

    func testPositionIsUnlockedForSinglePressDraggingByDefault() async {
        await MainActor.run {
            XCTAssertFalse(PetView(frame: .zero).positionLocked)
        }
    }

    func testHoverPassesThroughWithoutFeedbackAndOutsideAreasResetDwell() async throws {
        try await MainActor.run {
            for target in OutsideTarget.allCases {
                let f = Fixture()
                defer { f.close() }
                f.routeHover(at: f.headA, time: 0)
                f.routeHover(at: f.headB, time: 0.2)
                f.routeHover(at: f.outsidePoint(target), time: 0.3)
                XCTAssertTrue(f.pets.isEmpty)
                f.routeHover(at: f.headA, time: 0.4)
                f.routeHover(at: f.headB, time: 0.7)
                XCTAssertTrue(f.pets.isEmpty, "Transparent padding, line and counter restart dwell")
                f.routeHover(at: f.headA, time: 0.8)
                XCTAssertTrue(f.pets.isEmpty)
                f.routeHover(at: f.headB, time: 0.9)
                XCTAssertEqual(f.pets.count, 1)
                for time in [1.0, 2, 5, 10] { f.routeHover(at: f.headB, time: time) }
                XCTAssertEqual(f.pets.count, 1, "A stationary physical pointer never repeats feedback")
                XCTAssertFalse(f.pet.hasPointerCapture)
                XCTAssertTrue(f.dragOffsets.isEmpty)
                XCTAssertEqual(f.presses, 0)
                XCTAssertEqual(f.releases, 0)
            }
        }
    }

    func testForeignButtonsAndMenusCancelHoverInsteadOfQueuingFeedback() async throws {
        try await MainActor.run {
            for buttons in [1, 2, 4, 0] {
                let f = Fixture()
                defer { f.close() }
                f.routeHover(at: f.headA, time: 0)
                f.routeHover(at: f.headA, time: 0.36)
                if buttons == 0 { f.pet.allowsHoverInteraction = false }
                f.routeHover(at: f.headB, buttons: buttons, time: 0.4)
                XCTAssertTrue(f.pets.isEmpty)
                if buttons != 0 { XCTAssertTrue(f.panel.ignoresMouseEvents) }
                f.pet.allowsHoverInteraction = true
                f.routeHover(at: f.headA, time: 0.5)
                f.routeHover(at: f.headB, time: 0.7)
                XCTAssertTrue(f.pets.isEmpty)
                f.routeHover(at: f.headA, time: 0.86)
                f.routeHover(at: f.headB, time: 1)
                XCTAssertEqual(f.pets.count, 1)
                XCTAssertFalse(f.pet.hasPointerCapture)
            }
        }
    }

    func testMouseDownCancelsArmedHoverAndStillPerformsAnOrdinaryClick() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            f.routeHover(at: f.headA, time: 0)
            f.routeHover(at: f.headA, time: 0.36)
            try f.send(.leftMouseDown, at: f.headA)
            f.routeHover(at: f.headB, buttons: 1, time: 0.5)
            XCTAssertTrue(f.pets.isEmpty)
            try f.send(.leftMouseUp, at: f.headA)
            XCTAssertEqual(f.pets.count, 1)
            f.routeHover(at: f.headB, time: 1)
            f.routeHover(at: f.headA, time: 1.2)
            XCTAssertEqual(f.pets.count, 1, "Release cannot reuse pre-press dwell")
            XCTAssertFalse(f.pet.hasPointerCapture)
            XCTAssertTrue(f.dragOffsets.isEmpty)
        }
    }

    func testStopRestFocusLossAndRotationDiscardHoverIntent() async throws {
        try await MainActor.run {
            for reason in [Cancellation.explicit, .stop, .rest, .resignKey] {
                let f = Fixture()
                defer { f.close() }
                f.routeHover(at: f.headA, time: 0)
                f.routeHover(at: f.headA, time: 0.36)
                f.cancel(reason)
                f.routeHover(at: f.headB, time: 0.4)
                f.routeHover(at: f.headA, time: 0.6)
                XCTAssertTrue(f.pets.isEmpty, "\(reason)")
                f.pet.cancelStroke() // The R path also clears hover without cancelling an unlocked drag.
                f.routeHover(at: f.headB, time: 0.8)
                f.routeHover(at: f.headA, time: 1)
                XCTAssertTrue(f.pets.isEmpty)
            }
        }
    }

    func testSinglePressDragsAtEveryOrientationAndHoverWorksAfterRelease() async throws {
        try await MainActor.run {
            let placements: [(DogOrientation, CGFloat?)] = DogOrientation.allCases.map { ($0, nil) } + [(.bottom, 38)]
            for (orientation, topbarHeight) in placements {
                for clickCount in [1, 2] {
                    let f = Fixture(orientation: orientation, topbarHeight: topbarHeight)
                    defer { f.close() }
                    f.pet.positionLocked = false
                    let start: NSPoint, end: NSPoint
                    if topbarHeight != nil {
                        let layout = DogTopbarRenderer.layout(size: f.pet.bounds.size, scale: f.scale)
                        start = NSPoint(x: layout.offset.x + 90 * layout.scale, y: layout.offset.y + 35 * layout.scale)
                        end = NSPoint(x: layout.offset.x + 125 * layout.scale, y: start.y)
                    } else {
                        let transform = orientation.transform(size: NSSize(width: 260 * f.scale, height: 148 * f.scale))
                        start = f.headA.applying(transform)
                        end = f.headB.applying(transform)
                    }
                    XCTAssertTrue(f.pet.containsInteraction(start, includesBaseline: false))
                    XCTAssertTrue(f.pet.containsInteraction(end, includesBaseline: false))
                    // The preceding ordinary click is still a click, not a mode switch.
                    try f.send(.leftMouseDown, at: start)
                    try f.send(.leftMouseUp, at: start)
                    XCTAssertEqual(f.pets.count, 1)
                    try f.send(.leftMouseDown, at: start, clickCount: clickCount)
                    let distance = hypot(end.x - start.x, end.y - start.y)
                    let tremor = NSPoint(x: start.x + (end.x - start.x) * 3 / distance,
                                         y: start.y + (end.y - start.y) * 3 / distance)
                    try f.send(.leftMouseDragged, at: tremor, clickCount: clickCount)
                    XCTAssertTrue(f.dragOffsets.isEmpty, "A press still honors the drag threshold")
                    XCTAssertFalse(f.pet.motion.isDragging)
                    try f.send(.leftMouseDragged, at: end, clickCount: clickCount)
                    XCTAssertTrue(f.pet.hasPointerCapture)
                    XCTAssertTrue(f.pet.motion.isDragging)
                    XCTAssertFalse(f.pet.positionLocked)
                    XCTAssertEqual(f.dragOffsets.count, 1)
                    XCTAssertEqual(f.pets.count, 1, "Dragging must not emit a hover stroke")
                    try f.send(.leftMouseUp, at: end, clickCount: clickCount)
                    XCTAssertEqual(f.dragEnds.count, 1)
                    XCTAssertEqual(f.positionChanges, 1)
                    XCTAssertEqual(f.releases, 2)
                    XCTAssertFalse(f.pet.hasPointerCapture)
                    XCTAssertFalse(f.pet.motion.isDragging)
                    XCTAssertFalse(f.pet.positionLocked)
                    XCTAssertEqual(f.pets.count, 1)
                    let originalFrame = f.panel.frame
                    f.pet.updateHover(at: start, pressedButtons: 0, hoverTime: 0)
                    f.pet.updateHover(at: end, pressedButtons: 0, hoverTime: 0.36)
                    XCTAssertEqual(f.pets.count, 1, "Travel before the dwell is discarded")
                    f.pet.updateHover(at: start, pressedButtons: 0, hoverTime: 0.5)
                    XCTAssertEqual(f.pets.count, 2)
                    XCTAssertFalse(f.pet.hasPointerCapture)
                    XCTAssertFalse(f.pet.motion.isDragging)
                    XCTAssertEqual(f.panel.frame, originalFrame)
                    XCTAssertEqual(f.dragOffsets.count, 1)
                    f.pet.updateHover(at: start, pressedButtons: 0, hoverTime: 10)
                    XCTAssertEqual(f.pets.count, 2, "Stationary hover cannot repeat feedback")
                    XCTAssertEqual(f.dragEnds.count, 1)
                    XCTAssertEqual(f.releases, 2)
                }
            }
        }
    }

    func testStationaryDoubleClickProducesTwoClicksWithoutTogglingLock() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            f.pet.positionLocked = true
            for clickCount in [1, 2] {
                try f.send(.leftMouseDown, at: f.headA, clickCount: clickCount)
                try f.send(.leftMouseDragged, at: f.headA, clickCount: clickCount)
                XCTAssertEqual(f.pets.count, clickCount - 1)
                try f.send(.leftMouseUp, at: f.headA, clickCount: clickCount)
                XCTAssertEqual(f.pets.count, clickCount)
                XCTAssertTrue(f.pet.positionLocked)
                XCTAssertFalse(f.pet.hasPointerCapture)
            }
            XCTAssertEqual(f.releases, 2)
            XCTAssertTrue(f.dragOffsets.isEmpty)
            XCTAssertTrue(f.dragEnds.isEmpty)
        }
    }

    func testCancellingNormalDragRequiresFreshHoverIntent() async throws {
        try await MainActor.run {
            for reason in [Cancellation.explicit, .stop, .rest, .resignKey] {
                let f = Fixture()
                defer { f.close() }
                f.pet.positionLocked = false
                try f.send(.leftMouseDown, at: f.headA)
                try f.send(.leftMouseDragged, at: f.headB)
                XCTAssertTrue(f.pet.motion.isDragging)
                f.cancel(reason)
                XCTAssertFalse(f.pet.hasPointerCapture)
                XCTAssertFalse(f.pet.motion.isDragging)
                XCTAssertFalse(f.pet.positionLocked)
                XCTAssertEqual(f.releases, 1)
                try f.send(.leftMouseUp, at: f.headB)
                XCTAssertEqual(f.releases, 1)
                XCTAssertTrue(f.pets.isEmpty)
                XCTAssertTrue(f.dragEnds.isEmpty)
                f.pet.updateHover(at: f.headA, pressedButtons: 0, hoverTime: 0)
                f.pet.updateHover(at: f.headB, pressedButtons: 0, hoverTime: 0.2)
                XCTAssertTrue(f.pets.isEmpty)
                f.pet.updateHover(at: f.headA, pressedButtons: 0, hoverTime: 0.36)
                f.pet.updateHover(at: f.headB, pressedButtons: 0, hoverTime: 0.5)
                XCTAssertEqual(f.pets.count, reason == .rest ? 0 : 1, "\(reason)")
                if reason == .rest {
                    XCTAssertNotNil(f.pet.motion.sleepStarted)
                    XCTAssertGreaterThan(f.pet.motion.pose(now: ProcessInfo.processInfo.systemUptime + 0.6).affection, 0)
                }
                XCTAssertFalse(f.pet.motion.isDragging)
                XCTAssertEqual(f.releases, 1)
                XCTAssertEqual(f.dragOffsets.count, 1)
                XCTAssertTrue(f.dragEnds.isEmpty)
            }
        }
    }

    func testLockedStrokeRespondsWithoutMovingAndReleaseDoesNotPetAgain() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            f.pet.positionLocked = true
            let initialFrame = f.panel.frame
            XCTAssertTrue(f.pet.containsInteraction(f.headA, includesBaseline: false))
            XCTAssertTrue(f.pet.containsInteraction(f.headB, includesBaseline: false))
            try f.send(.leftMouseDown, at: f.headA)
            XCTAssertEqual(f.presses, 1)
            XCTAssertTrue(f.pet.hasPointerCapture)
            try f.send(.leftMouseDragged, at: f.headB)
            XCTAssertEqual(f.pets.count, 1, "The first genuine stroke gives immediate feedback")
            XCTAssertEqual(f.pets.first, f.screenPoint(f.headB))
            XCTAssertEqual(f.panel.frame, initialFrame)
            XCTAssertTrue(f.dragOffsets.isEmpty)
            XCTAssertTrue(f.dragEnds.isEmpty)
            XCTAssertEqual(f.positionChanges, 0)
            f.panel.updatePointerRouting(at: NSPoint(x: -200, y: -200), pressedButtons: 1)
            XCTAssertFalse(f.panel.ignoresMouseEvents, "An owned stroke keeps capture outside its silhouette")
            XCTAssertTrue(f.pet.hasPointerCapture)
            try f.send(.leftMouseUp, at: f.headB)
            XCTAssertEqual(f.pets.count, 1)
            XCTAssertEqual(f.releases, 1)
            XCTAssertFalse(f.pet.hasPointerCapture)
            XCTAssertEqual(f.panel.frame, initialFrame)
            XCTAssertTrue(f.dragEnds.isEmpty)
        }
    }

    func testStationaryHoldHasNoPulseAndStillEndsAsOneClick() async throws {
        try await MainActor.run {
            for locked in [false, true] {
                let f = Fixture()
                defer { f.close() }
                f.pet.positionLocked = locked
                try f.send(.leftMouseDown, at: f.headA)
                for _ in 0..<12 { try f.send(.leftMouseDragged, at: f.headA) }
                XCTAssertTrue(f.pets.isEmpty)
                XCTAssertTrue(f.dragOffsets.isEmpty)
                try f.send(.leftMouseUp, at: f.headA)
                try f.send(.leftMouseUp, at: f.headA)
                XCTAssertEqual(f.pets.count, 1)
                XCTAssertEqual(f.presses, 1)
                XCTAssertEqual(f.releases, 1)
            }
        }
    }

    func testMovementPastClickToleranceButBelowPulseDoesNotBecomeClick() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            f.pet.positionLocked = true
            let smallMove = NSPoint(x: f.headA.x + 6, y: f.headA.y)
            try f.send(.leftMouseDown, at: f.headA)
            try f.send(.leftMouseDragged, at: smallMove)
            try f.send(.leftMouseUp, at: smallMove)
            XCTAssertTrue(f.pets.isEmpty)
            XCTAssertEqual(f.releases, 1)
        }
    }

    func testLeavingSilhouetteDiscardsTheReturnSegment() async throws {
        try await MainActor.run {
            for target in OutsideTarget.allCases {
                let f = Fixture()
                defer { f.close() }
                f.pet.positionLocked = true
                let outside = f.outsidePoint(target)
                XCTAssertFalse(f.pet.containsInteraction(outside, includesBaseline: false), "\(target)")
                if target == .baseline {
                    XCTAssertTrue(f.pet.containsInteraction(outside), "The baseline remains draggable, but cannot be petted")
                }
                try f.send(.leftMouseDown, at: f.headA)
                try f.send(.leftMouseDragged, at: outside)
                XCTAssertTrue(f.pets.isEmpty)
                try f.send(.leftMouseDragged, at: f.headB)
                XCTAssertTrue(f.pets.isEmpty, "Re-entry must not include the trip outside: \(target)")
                try f.send(.leftMouseDragged, at: f.headA)
                XCTAssertEqual(f.pets.count, 1, "A new inside segment may resume petting: \(target)")
                try f.send(.leftMouseUp, at: f.headA)
                XCTAssertEqual(f.pets.count, 1)
                XCTAssertEqual(f.releases, 1)
            }
        }
    }

    func testOutsidePressDoesNotPetOnReleaseOrReturnForEitherClickCount() async throws {
        try await MainActor.run {
            for target in OutsideTarget.allCases {
                for clickCount in [1, 2] {
                    let f = Fixture()
                    defer { f.close() }
                    f.pet.positionLocked = true
                    let outside = f.outsidePoint(target)
                    try f.send(.leftMouseDown, at: outside, clickCount: clickCount)
                    try f.send(.leftMouseUp, at: outside, clickCount: clickCount)
                    XCTAssertTrue(f.pets.isEmpty, "A stationary outside press is not a pet: \(target), \(clickCount)")
                    XCTAssertEqual(f.releases, 1)
                    try f.send(.leftMouseDown, at: outside, clickCount: clickCount)
                    try f.send(.leftMouseDragged, at: f.headA, clickCount: clickCount)
                    try f.send(.leftMouseUp, at: f.headA, clickCount: clickCount)
                    XCTAssertTrue(f.pets.isEmpty, "An outside press/re-entry is not a pet: \(target), \(clickCount)")
                    XCTAssertEqual(f.releases, 2)
                    try f.send(.leftMouseDown, at: f.headA, clickCount: clickCount)
                    try f.send(.leftMouseUp, at: outside, clickCount: clickCount)
                    XCTAssertTrue(f.pets.isEmpty, "An outside release is not a pet: \(target), \(clickCount)")
                    XCTAssertEqual(f.releases, 3)
                }
            }
        }
    }

    func testCancellationPathsReleaseCaptureExactlyOnce() async throws {
        try await MainActor.run {
            for reason in Cancellation.allCases {
                let f = Fixture()
                defer { f.close() }
                f.pet.positionLocked = true
                try f.send(.leftMouseDown, at: f.headA)
                XCTAssertTrue(f.pet.hasPointerCapture)
                f.cancel(reason)
                XCTAssertFalse(f.pet.hasPointerCapture, "\(reason)")
                XCTAssertEqual(f.releases, 1, "\(reason)")
                f.cancel(reason)
                f.pet.cancelPointerInteraction()
                try f.send(.leftMouseUp, at: f.headA)
                XCTAssertEqual(f.releases, 1, "Cancellation is idempotent: \(reason)")
                XCTAssertEqual(f.presses, 1)
                XCTAssertTrue(f.pets.isEmpty)
                XCTAssertTrue(f.dragEnds.isEmpty)
            }
        }
    }

    func testUnlockedDragKeepsOriginalOffsetsAndDropCallbacks() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            let initialFrame = f.panel.frame
            try f.send(.leftMouseDown, at: f.headA)
            try f.send(.leftMouseDragged, at: f.headB)
            XCTAssertEqual(f.dragOffsets, [NSPoint(x: f.headB.x - f.headA.x, y: 0)])
            XCTAssertTrue(f.pet.hasPointerCapture)
            XCTAssertTrue(f.pets.isEmpty)
            try f.send(.leftMouseUp, at: f.headB)
            XCTAssertEqual(f.dragEnds, [f.screenPoint(f.headB)])
            XCTAssertEqual(f.positionChanges, 1)
            XCTAssertEqual(f.releases, 1)
            XCTAssertFalse(f.pet.hasPointerCapture)
            XCTAssertEqual(f.panel.frame, initialFrame, "The configured drag callback owns placement")
        }
    }

    func testUnlockedDragWithoutCallbackMovesTheWindow() async throws {
        try await MainActor.run {
            let f = Fixture()
            defer { f.close() }
            f.pet.onDragOffset = nil
            let initialOrigin = f.panel.frame.origin
            let dropScreenPoint = f.screenPoint(f.headB)
            try f.send(.leftMouseDown, at: f.headA)
            try f.send(.leftMouseDragged, at: f.headB)
            XCTAssertEqual(f.panel.frame.origin.x, initialOrigin.x + f.headB.x - f.headA.x, accuracy: 0.001)
            XCTAssertEqual(f.panel.frame.origin.y, initialOrigin.y, accuracy: 0.001)
            // Window movement changes local coordinates; retain the actual drop screen point.
            let localDrop = f.pet.convert(f.panel.convertPoint(fromScreen: dropScreenPoint), from: nil)
            try f.send(.leftMouseUp, at: localDrop)
            XCTAssertEqual(f.dragEnds, [dropScreenPoint])
            XCTAssertTrue(f.pets.isEmpty)
            XCTAssertEqual(f.releases, 1)
        }
    }

    func testFourOrientationsAndTopbarUseTheDisplayedHeadForStroking() async throws {
        try await MainActor.run {
            for orientation in DogOrientation.allCases {
                let f = Fixture(orientation: orientation)
                defer { f.close() }
                f.pet.positionLocked = true
                let transform = orientation.transform(size: NSSize(width: 260 * f.scale, height: 148 * f.scale))
                let start = f.headA.applying(transform)
                let end = f.headB.applying(transform)
                XCTAssertTrue(f.pet.containsInteraction(start, includesBaseline: false), "\(orientation)")
                XCTAssertTrue(f.pet.containsInteraction(end, includesBaseline: false), "\(orientation)")
                try f.send(.leftMouseDown, at: start)
                try f.send(.leftMouseDragged, at: end)
                try f.send(.leftMouseUp, at: end)
                XCTAssertEqual(f.pets.count, 1, "\(orientation)")
                XCTAssertTrue(f.dragEnds.isEmpty)
            }
            let f = Fixture(scale: 0.5, topbarHeight: 38)
            defer { f.close() }
            f.pet.positionLocked = true
            let layout = DogTopbarRenderer.layout(size: f.pet.bounds.size, scale: f.scale)
            func point(_ x: CGFloat) -> NSPoint {
                NSPoint(x: layout.offset.x + x * layout.scale, y: layout.offset.y + 35 * layout.scale)
            }
            let start = point(90), end = point(125)
            XCTAssertTrue(f.pet.containsInteraction(start, includesBaseline: false))
            XCTAssertTrue(f.pet.containsInteraction(end, includesBaseline: false))
            try f.send(.leftMouseDown, at: start)
            try f.send(.leftMouseDragged, at: end)
            try f.send(.leftMouseUp, at: end)
            XCTAssertEqual(f.pets.count, 1)
            XCTAssertTrue(f.dragEnds.isEmpty)
        }
    }

    func testClearingTopbarSelectionPreservesOwnedDragAcrossDesktopTransition() async throws {
        try await MainActor.run {
            let f = Fixture(scale: 0.5, topbarHeight: 38)
            defer { f.close() }
            f.pet.positionLocked = false
            let layout = DogTopbarRenderer.layout(size: f.pet.bounds.size, scale: f.scale)
            let head = NSPoint(x: layout.offset.x + 100 * layout.scale,
                               y: layout.offset.y + 35 * layout.scale)
            XCTAssertTrue(f.pet.containsInteraction(head, includesBaseline: false))
            XCTAssertFalse(f.panel.isKeyWindow)
            try f.send(.leftMouseDown, at: head)
            let firstDrag = NSPoint(x: head.x, y: head.y - 45)
            let firstScreen = f.screenPoint(firstDrag)
            try f.send(.leftMouseDragged, at: firstDrag)
            XCTAssertEqual(f.dragOffsets.count, 1)
            // App.setTopbarEnabled(false) clears selection while the same owned
            // drag is moving out of the menu band. It must not release capture.
            f.panel.clearRotationSelection()
            f.companion.topbarHeight = nil
            f.panel.setContentSize(f.companion.layoutGeometry.size)
            f.companion.layoutSubtreeIfNeeded()
            XCTAssertTrue(f.pet.hasPointerCapture)
            XCTAssertEqual(f.releases, 0)
            let lastScreen = NSPoint(x: firstScreen.x + 15, y: firstScreen.y - 20)
            let lastLocal = f.pet.convert(f.panel.convertPoint(fromScreen: lastScreen), from: nil)
            try f.send(.leftMouseDragged, at: lastLocal)
            XCTAssertEqual(f.dragOffsets.count, 2, "The detached dog must continue following this drag")
            XCTAssertTrue(f.pet.hasPointerCapture)
            try f.send(.leftMouseUp, at: lastLocal)
            XCTAssertEqual(f.dragEnds.count, 1)
            let actualDrop = try XCTUnwrap(f.dragEnds.first)
            XCTAssertEqual(actualDrop.x, lastScreen.x, accuracy: 0.00001)
            XCTAssertEqual(actualDrop.y, lastScreen.y, accuracy: 0.00001)
            XCTAssertEqual(f.positionChanges, 1)
            XCTAssertEqual(f.releases, 1)
            XCTAssertFalse(f.pet.hasPointerCapture)
            XCTAssertFalse(f.pet.positionLocked)
            XCTAssertTrue(f.pets.isEmpty)
        }
    }

    func testRReleasesLockedStrokeButPreservesOriginalUnlockedDrag() async throws {
        try await MainActor.run {
            for (locked, clickCount) in [(false, 1), (true, 1), (true, 2)] {
                let f = Fixture()
                defer { f.close() }
                var capturesAtRotation: [Bool] = []
                f.pet.onRotationRequest = { capturesAtRotation.append(f.pet.hasPointerCapture) }
                f.pet.positionLocked = locked
                f.pet.isRotationSelected = true
                XCTAssertTrue(f.panel.makeFirstResponder(f.pet))
                try f.send(.leftMouseDown, at: f.headA, clickCount: clickCount)
                try f.send(.leftMouseDragged, at: f.headB, clickCount: clickCount)
                XCTAssertTrue(f.pet.hasPointerCapture)
                let petsBeforeRotation = f.pets.count
                f.pet.keyDown(with: try rotationKey(in: f.panel))
                let stroke = locked
                XCTAssertEqual(capturesAtRotation, [!stroke])
                XCTAssertEqual(f.pet.hasPointerCapture, !stroke)
                XCTAssertEqual(f.releases, stroke ? 1 : 0)
                try f.send(.leftMouseUp, at: f.headB, clickCount: clickCount)
                XCTAssertEqual(f.releases, 1)
                XCTAssertEqual(f.pets.count, petsBeforeRotation)
                XCTAssertEqual(f.dragEnds.count, stroke ? 0 : 1)
                f.pet.onRotationRequest = nil
            }
        }
    }

    func testPreviewRAlsoReleasesLockedStrokeBeforeTurning() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 366, height: 204),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 366, height: 204),
                                          scale: 0.62, name: "测试小狗", clock: { 0 })
            window.contentView = canvas
            defer { canvas.stop(); window.contentView = nil; window.close() }
            canvas.pet.positionLocked = true
            var releases = 0
            var pets = 0
            let originalRelease = canvas.pet.onPointerRelease
            canvas.pet.onPointerRelease = { originalRelease?(); releases += 1 }
            canvas.pet.onPet = { _ in pets += 1; return true }
            @MainActor func mouse(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
                let event = NSEvent.mouseEvent(with: type,
                    location: canvas.pet.convert(NSPoint(x: x, y: 25), to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                return try XCTUnwrap(event)
            }
            canvas.pet.mouseDown(with: try mouse(.leftMouseDown, x: 50))
            canvas.pet.mouseDragged(with: try mouse(.leftMouseDragged, x: 75))
            XCTAssertTrue(window.firstResponder === canvas)
            XCTAssertTrue(canvas.pet.hasPointerCapture)
            XCTAssertEqual(pets, 1)
            canvas.keyDown(with: try rotationKey(in: window))
            XCTAssertEqual(canvas.orientation, .left)
            XCTAssertFalse(canvas.pet.hasPointerCapture)
            XCTAssertEqual(releases, 1)
            canvas.pet.mouseUp(with: try mouse(.leftMouseUp, x: 75))
            XCTAssertEqual(releases, 1)
            XCTAssertEqual(pets, 1)
        }
    }

    @MainActor
    private func rotationKey(in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
    }

    private enum OutsideTarget: CaseIterable { case transparent, baseline, counter }
    private enum Cancellation: CaseIterable { case explicit, unlock, stop, rest, resignKey, close, miniaturize }

    @MainActor
    private final class Fixture {
        let panel: PetPanel
        let pet: PetView
        let companion: DogCompanionView
        let scale: Double
        let headA = NSPoint(x: 50, y: 25)
        let headB = NSPoint(x: 75, y: 25)
        var presses = 0
        var releases = 0
        var pets: [NSPoint] = []
        var dragOffsets: [NSPoint] = []
        var dragEnds: [NSPoint] = []
        var positionChanges = 0

        init(scale: Double = 0.62, orientation: DogOrientation = .bottom, topbarHeight: CGFloat? = nil) {
            _ = NSApplication.shared
            self.scale = scale
            panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            pet = PetView(frame: .zero)
            pet.positionLocked = false // Legacy drag tests opt in explicitly.
            companion = DogCompanionView(pet: pet, scale: scale)
            companion.orientation = orientation
            companion.topbarHeight = topbarHeight
            panel.contentView = companion
            panel.setContentSize(companion.layoutGeometry.size)
            companion.layoutSubtreeIfNeeded()
            pet.onPointerPress = { [weak self] in self?.presses += 1 }
            pet.onPointerRelease = { [weak self] in self?.releases += 1 }
            pet.onPet = { [weak self] point in self?.pets.append(point); return true }
            pet.onDragOffset = { [weak self] offset, _ in self?.dragOffsets.append(offset) }
            pet.onDragEnded = { [weak self] point in self?.dragEnds.append(point) }
            pet.onPositionChanged = { [weak self] in self?.positionChanges += 1 }
        }

        func send(_ type: NSEvent.EventType, at point: NSPoint, clickCount: Int = 1) throws {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: pet.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1))
            switch type {
            case .leftMouseDown: pet.mouseDown(with: event)
            case .leftMouseDragged: pet.mouseDragged(with: event)
            case .leftMouseUp: pet.mouseUp(with: event)
            default: XCTFail("Unsupported synthetic mouse event")
            }
        }

        func screenPoint(_ point: NSPoint) -> NSPoint {
            panel.convertPoint(toScreen: pet.convert(point, to: nil))
        }

        func routeHover(at point: NSPoint, buttons: Int = 0, time: TimeInterval) {
            panel.updatePointerRouting(at: pet.convert(point, to: companion), pressedButtons: buttons, hoverTime: time)
        }

        func outsidePoint(_ target: OutsideTarget) -> NSPoint {
            switch target {
            case .transparent: NSPoint(x: 3, y: pet.bounds.maxY - 3)
            case .baseline: NSPoint(x: DogRenderer.baselineRange.lowerBound * scale + 1, y: 1 + DogRenderer.baselineY * scale)
            case .counter: pet.convert(NSPoint(x: companion.badgeFrame.midX, y: companion.badgeFrame.midY), from: companion)
            }
        }

        func cancel(_ reason: Cancellation) {
            switch reason {
            case .explicit: pet.cancelPointerInteraction()
            case .unlock: pet.positionLocked = false
            case .stop: pet.stop()
            case .rest: pet.rest()
            case .resignKey: NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: panel)
            case .close: NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: panel)
            case .miniaturize: NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: panel)
            }
        }

        func close() {
            pet.stop()
            panel.contentView = nil
            panel.close()
        }
    }
}
