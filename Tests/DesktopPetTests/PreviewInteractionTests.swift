import AppKit
import XCTest
@testable import DesktopPet

final class PreviewInteractionTests: XCTestCase, @unchecked Sendable {
    func testPreviewHoverRequiresVisibleUnobscuredWindowAndNoMouseButtons() async {
        await MainActor.run {
            _ = NSApplication.shared
            for (eligible, hitsWindow, buttons) in [(false, true, 0), (true, false, 0), (true, true, 1), (true, true, 2)] {
                var time = 0.0
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 366, height: 204),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 366, height: 204),
                                              scale: 0.62, name: "测试小狗", clock: { time })
                window.contentView = canvas
                defer { canvas.stop(); window.contentView = nil; window.close() }
                var pets = 0
                canvas.pet.onPet = { _ in pets += 1; return true }
                let a = NSPoint(x: 50, y: 25), b = NSPoint(x: 75, y: 25)
                canvas.updateHover(at: a, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                time = 0.36
                canvas.updateHover(at: a, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                time = 0.4
                canvas.updateHover(at: b, pressedButtons: buttons, windowEligible: eligible, pointerHitsWindow: hitsWindow)
                XCTAssertEqual(pets, 0)
                time = 0.5
                canvas.updateHover(at: a, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                time = 0.7
                canvas.updateHover(at: b, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                XCTAssertEqual(pets, 0, "Becoming visible must start a fresh dwell")
                time = 0.86
                canvas.updateHover(at: a, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                time = 1
                canvas.updateHover(at: b, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                XCTAssertEqual(pets, 1)
                time = 10
                canvas.updateHover(at: b, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
                XCTAssertEqual(pets, 1)
                XCTAssertFalse(canvas.pet.hasPointerCapture)
            }
        }
    }

    func testPreviewRotationCancelsHoverAndRequiresFreshDwellAfterTurning() async {
        await MainActor.run {
            _ = NSApplication.shared
            var time = 0.0
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 366, height: 204),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 366, height: 204),
                                          scale: 0.62, name: "测试小狗", clock: { time })
            window.contentView = canvas
            defer { canvas.stop(); window.contentView = nil; window.close() }
            var pets = 0
            canvas.pet.onPet = { _ in pets += 1; return true }
            canvas.updateHover(at: NSPoint(x: 50, y: 25), pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            time = 0.36
            canvas.updateHover(at: NSPoint(x: 50, y: 25), pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            canvas.rotate()
            time = 0.4
            canvas.updateHover(at: NSPoint(x: 75, y: 25), pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            XCTAssertEqual(pets, 0)
            time = 2
            canvas.advanceAnimation(at: time)
            let transform = DogOrientation.left.transform(size: canvas.canonicalSize)
            let a = NSPoint(x: 50, y: 25).applying(transform), b = NSPoint(x: 75, y: 25).applying(transform)
            canvas.updateHover(at: a, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            time = 2.2
            canvas.updateHover(at: b, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            XCTAssertEqual(pets, 0)
            time = 2.36
            canvas.updateHover(at: a, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            time = 2.5
            canvas.updateHover(at: b, pressedButtons: 0, windowEligible: true, pointerHitsWindow: true)
            XCTAssertEqual(pets, 1)
        }
    }

    func testDragMovesOnlyThePreviewDogSnapsToTheEdgeAndKeepsItsOrientation() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var time = 0.0
            let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 366, height: 204),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 366, height: 204),
                                          scale: 0.62, name: "测试小狗", clock: { time })
            canvas.pet.positionLocked = false
            window.contentView = canvas
            let originalWindow = window.frame
            let originalDog = canvas.pet.frame
            var hearts = 0
            canvas.pet.onPet = { _ in hearts += 1; return true }
            let press = canvas.pet.convert(NSPoint(x: 60, y: 25), to: nil)
            canvas.pet.mouseDown(with: try mouse(.leftMouseDown, at: press, in: window))
            canvas.pet.mouseDragged(with: try mouse(.leftMouseDragged,
                at: NSPoint(x: press.x - 2000, y: press.y + 30), in: window))
            canvas.pet.mouseUp(with: try mouse(.leftMouseUp,
                at: NSPoint(x: press.x - 2000, y: press.y + 30), in: window))
            time = 1
            canvas.advanceAnimation(at: time)
            XCTAssertEqual(window.frame, originalWindow)
            XCTAssertNotEqual(canvas.pet.frame.origin, originalDog.origin)
            XCTAssertEqual(canvas.orientation, .bottom)
            XCTAssertEqual(canvas.pet.frame.minX, 2, accuracy: 0.00001)
            XCTAssertEqual(hearts, 0)
            XCTAssertFalse(canvas.pet.hasPointerCapture)
            XCTAssertFalse(canvas.pet.motion.isDragging)
            XCTAssertNotNil(canvas.pet.motion.landingStarted)
            assertInside(canvas)
            canvas.stop()
        }
    }

    func testReleaseNearAnEdgeSnapsTheDrawnBaselineRatherThanTransparentPadding() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var time = 0.0
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 204),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 180, height: 204),
                                          scale: 0.5, name: "测试小狗", clock: { time })
            canvas.pet.positionLocked = false
            window.contentView = canvas
            let press = canvas.pet.convert(NSPoint(x: 52, y: 20), to: nil)
            canvas.pet.mouseDown(with: try mouse(.leftMouseDown, at: press, in: window))
            let release = NSPoint(x: press.x, y: press.y + 8)
            canvas.pet.mouseDragged(with: try mouse(.leftMouseDragged, at: release, in: window))
            canvas.pet.mouseUp(with: try mouse(.leftMouseUp, at: release, in: window))
            XCTAssertNotNil(canvas.pet.turnPresentation)
            time = 1
            canvas.advanceAnimation(at: time)
            XCTAssertNil(canvas.pet.turnPresentation)
            let baseline = canvas.pet.frame.minY + 1 + DogRenderer.baselineY * 0.5
            XCTAssertEqual(baseline, 2, accuracy: 0.00001)
            XCTAssertEqual(canvas.orientation, .bottom)
            canvas.stop()
        }
    }

    func testROnlyRotatesTheSelectedPreviewAndIgnoresRepeatAndCommandModifiers() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var time = 0.0
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 588, height: 232),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 588, height: 232))
            window.contentView = root
            let first = DogPreviewCanvas(frame: NSRect(x: 8, y: 24, width: 366, height: 204),
                                         scale: 0.62, name: "第一只", clock: { time })
            let second = DogPreviewCanvas(frame: NSRect(x: 400, y: 24, width: 180, height: 204),
                                          scale: 0.5, name: "第二只", clock: { time })
            root.addSubview(first); root.addSubview(second)
            XCTAssertTrue(first.pet.accessibilityPerformPress())
            XCTAssertTrue(window.firstResponder === first)
            first.keyDown(with: try key(in: window, repeating: true))
            first.keyDown(with: try key(in: window, modifiers: .command))
            first.keyDown(with: try key(in: window, modifiers: .control))
            first.keyDown(with: try key(in: window, modifiers: .option))
            XCTAssertEqual(first.orientation, .bottom)
            first.keyDown(with: try key(in: window))
            XCTAssertEqual(first.orientation, .left)
            XCTAssertEqual(second.orientation, .bottom)
            time = 1
            first.advanceAnimation(at: time)
            XCTAssertNil(first.pet.turnPresentation)
            XCTAssertEqual(first.pet.frame.size, NSSize(width: 148 * 0.62, height: 260 * 0.62))
            XCTAssertTrue(second.pet.accessibilityPerformPress())
            XCTAssertTrue(window.firstResponder === second)
            first.keyDown(with: try key(in: window))
            XCTAssertEqual(first.orientation, .left)
            second.keyDown(with: try key(in: window, modifiers: .shift))
            XCTAssertEqual(second.orientation, .left)
            time = 2
            second.advanceAnimation(at: time)
            second.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 580, y: 225), in: window))
            second.keyDown(with: try key(in: window))
            XCTAssertEqual(second.orientation, .left)
            first.stop(); second.stop()
        }
    }

    func testFourTurnsStayInsideEachPreviewAndStopReleasesTheFastAnimationState() async {
        await MainActor.run {
            for (scale, width) in [(0.62, 366.0), (0.5, 180.0)] {
                var time = 0.0
                let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: width, height: 204),
                                              scale: scale, name: "测试小狗", clock: { time })
                for expected in [DogOrientation.left, .top, .right, .bottom] {
                    let start = time
                    canvas.rotate()
                    XCTAssertEqual(canvas.orientation, expected)
                    for frame in 0...60 {
                        time = start + Double(frame) / 60
                        canvas.advanceAnimation(at: time)
                        assertInside(canvas)
                    }
                    XCTAssertNil(canvas.pet.turnPresentation)
                }
                canvas.rotate()
                time += 0.1
                canvas.advanceAnimation(at: time)
                canvas.stop()
                XCTAssertNil(canvas.pet.turnPresentation)
                XCTAssertEqual(canvas.pet.orientation, .left)
                assertInside(canvas)
            }
        }
    }

    func testRapidTurnsContinueFromTheCurrentPoseInsteadOfRestarting() async {
        await MainActor.run {
            var time = 0.0
            let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 366, height: 204),
                                          scale: 0.62, name: "测试小狗", clock: { time })
            for _ in 0..<12 {
                canvas.rotate()
                time += 0.08
                canvas.advanceAnimation(at: time)
                let before = canvas.pose
                canvas.rotate()
                XCTAssertEqual(canvas.pose.angle, before.angle, accuracy: 0.00001)
                XCTAssertEqual(canvas.pose.center, before.center)
                assertInside(canvas)
            }
            time += 2
            canvas.advanceAnimation(at: time)
            XCTAssertNil(canvas.pet.turnPresentation)
            canvas.stop()
        }
    }

    func testRWhileDraggingKeepsCaptureAndTheNewOrientationWhenDroppedAtTheEdge() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var time = 0.0
            let window = NSWindow(contentRect: NSRect(x: 50, y: 60, width: 366, height: 204),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let canvas = DogPreviewCanvas(frame: NSRect(x: 0, y: 0, width: 366, height: 204),
                                          scale: 0.62, name: "测试小狗", clock: { time })
            canvas.pet.positionLocked = false
            window.contentView = canvas
            let originalWindow = window.frame
            let press = canvas.pet.convert(NSPoint(x: 60, y: 25), to: nil)
            canvas.pet.mouseDown(with: try mouse(.leftMouseDown, at: press, in: window))
            canvas.pet.mouseDragged(with: try mouse(.leftMouseDragged,
                at: NSPoint(x: press.x + 20, y: press.y + 40), in: window))
            canvas.keyDown(with: try key(in: window))
            time = 0.2
            canvas.advanceAnimation(at: time)
            XCTAssertTrue(canvas.pet.hasPointerCapture)
            let release = NSPoint(x: press.x - 1000, y: press.y + 1000)
            canvas.pet.mouseDragged(with: try mouse(.leftMouseDragged, at: release, in: window))
            canvas.pet.mouseUp(with: try mouse(.leftMouseUp, at: release, in: window))
            time = 2
            canvas.advanceAnimation(at: time)
            time = 3
            canvas.advanceAnimation(at: time)
            XCTAssertEqual(window.frame, originalWindow)
            XCTAssertEqual(canvas.orientation, .left)
            XCTAssertEqual(canvas.pet.orientation, .left)
            XCTAssertFalse(canvas.pet.hasPointerCapture)
            XCTAssertNil(canvas.pet.turnPresentation)
            assertInside(canvas)
            canvas.stop()
        }
    }
}

@MainActor
private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
}

@MainActor
private func key(in window: NSWindow, repeating: Bool = false,
                 modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "r", charactersIgnoringModifiers: "r",
        isARepeat: repeating, keyCode: 0))
}

@MainActor
private func assertInside(_ canvas: DogPreviewCanvas, file: StaticString = #filePath, line: UInt = #line) {
    let size = canvas.canonicalSize
    let baseline = 1 + 3.8 * size.width / 260
    let transform = canvas.pet.turnPresentation?.transform(in: canvas.pet.bounds)
        ?? canvas.pet.orientation.transform(size: size)
    for point in [NSPoint(x: 0, y: baseline), NSPoint(x: size.width, y: baseline),
                  NSPoint(x: 0, y: size.height), NSPoint(x: size.width, y: size.height)] {
        let actual = canvas.pet.convert(point.applying(transform), to: canvas)
        XCTAssertGreaterThanOrEqual(actual.x, 2 - 0.00001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(actual.y, 2 - 0.00001, file: file, line: line)
        XCTAssertLessThanOrEqual(actual.x, canvas.bounds.maxX - 2 + 0.00001, file: file, line: line)
        XCTAssertLessThanOrEqual(actual.y, canvas.bounds.maxY - 2 + 0.00001, file: file, line: line)
    }
}
