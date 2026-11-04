import AppKit
import XCTest
@testable import DesktopPet

final class ClickHeartTests: XCTestCase, @unchecked Sendable {
    func testEffectsStayAboveTheDogAfterSelectionRaisingAndMovement() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let name = "DesktopPet.EffectStackTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(1, forKey: InteractionEffectSelection.preferenceKey)
            let existing = Set(NSApp.windows.map(\.windowNumber))
            let overlay = ClickHeartOverlay(defaults: defaults)
            let effectWindow = try XCTUnwrap(NSApp.windows.first {
                $0.title == "互动特效" && !existing.contains($0.windowNumber)
            })
            let dog = PetPanel(contentRect: NSRect(x: 100, y: 100, width: 130, height: 74),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            dog.level = .floating
            dog.animationBehavior = .none
            let pet = PetView(frame: NSRect(x: 0, y: 0, width: 130, height: 74))
            pet.onRotationRequest = {}
            dog.contentView = pet
            defer { overlay.clear(); dog.orderOut(nil) }
            dog.orderFrontRegardless()
            for orientation in DogOrientation.allCases {
                pet.orientation = orientation
                XCTAssertTrue(overlay.emit(at: NSPoint(x: 150, y: 140)))
                // Selecting, clicking again or dragging can raise the dog after emission.
                dog.selectForRotation(pet)
                dog.orderFrontRegardless()
                dog.setFrameOrigin(NSPoint(x: 101, y: 101))
                overlay.advance()
                let order = try XCTUnwrap(NSWindow.windowNumbers(options: []))
                let front = try XCTUnwrap(order.firstIndex(of: NSNumber(value: effectWindow.windowNumber)))
                let back = try XCTUnwrap(order.firstIndex(of: NSNumber(value: dog.windowNumber)))
                XCTAssertLessThan(front, back, "The dog must never cover a live interaction effect")
                XCTAssertTrue(effectWindow.ignoresMouseEvents)
                XCTAssertFalse(effectWindow.canBecomeKey)
                XCTAssertFalse(effectWindow.isKeyWindow)
                XCTAssertLessThan(effectWindow.level.rawValue, NSWindow.Level.modalPanel.rawValue)
            }
            overlay.clear()
            XCTAssertFalse(effectWindow.isVisible)
        }
    }

    func testHeartStartsAtTheInteractionPointRisesAndFadesAway() throws {
        let origin = NSPoint(x: -400, y: 500)
        let heart = ClickHeart(origin: origin, started: 10, variant: 0)
        let birth = try XCTUnwrap(heart.pose(now: 10))
        XCTAssertEqual(birth.x, origin.x)
        XCTAssertEqual(birth.y, origin.y)
        XCTAssertEqual(birth.alpha, 0)
        let first = try XCTUnwrap(heart.pose(now: 10.2))
        let later = try XCTUnwrap(heart.pose(now: 11.6))
        XCTAssertGreaterThan(later.y, first.y)
        XCTAssertLessThan(later.alpha, first.alpha)
        XCTAssertNil(heart.pose(now: 12))
    }

    func testEveryClickGetsOneFreshHeartWhileRapidClicksStayBounded() {
        var motion = ClickHeartMotion()
        motion.emit(at: NSPoint(x: 20, y: 30), now: 0)
        XCTAssertEqual(motion.hearts.count, 1)
        for index in 1...1000 {
            let point = NSPoint(x: index, y: -index)
            motion.emit(at: point, now: Double(index) / 1000)
            XCTAssertLessThanOrEqual(motion.hearts.count, 6)
            XCTAssertEqual(motion.hearts.last?.origin, point)
        }
        motion.advance(now: 4)
        XCTAssertTrue(motion.hearts.isEmpty)
        XCTAssertTrue(motion.frame.isNull)
    }

    func testNewInteractionDoesNotMoveOrRestartAnExistingHeart() throws {
        var motion = ClickHeartMotion()
        motion.emit(at: NSPoint(x: 20, y: 30), now: 0)
        let before = try XCTUnwrap(motion.poses(now: 0.6).first)
        motion.emit(at: NSPoint(x: 80, y: 10), now: 0.6)
        let after = try XCTUnwrap(motion.poses(now: 0.6).first)
        XCTAssertEqual(before.x, after.x)
        XCTAssertEqual(before.y, after.y)
        XCTAssertEqual(before.alpha, after.alpha)
        XCTAssertEqual(motion.hearts.count, 2)
        XCTAssertEqual(motion.hearts.first?.started, 0)
    }

    func testReducedMotionKeepsHeartAtTheClickAndOnlyFades() throws {
        let heart = ClickHeart(origin: NSPoint(x: 10, y: 20), started: 0, variant: 1)
        let first = try XCTUnwrap(heart.pose(now: 0.2, reducedMotion: true))
        let last = try XCTUnwrap(heart.pose(now: 1.8, reducedMotion: true))
        XCTAssertEqual(first.x, last.x)
        XCTAssertEqual(first.y, last.y)
        XCTAssertEqual(first.scale, last.scale)
        XCTAssertEqual(last.rotation, 0)
        XCTAssertLessThan(last.alpha, first.alpha)
    }

    func testActualLocalClickUsesScreenLocationAtEveryOrientation() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            for orientation in DogOrientation.allCases {
                let view = DogCompanionView(pet: PetView(frame: .zero), scale: 0.5)
                view.orientation = orientation
                panel.contentView = view
                panel.setPetFrame(NSRect(origin: NSPoint(x: -100.3, y: 250.6), size: view.layoutGeometry.size))
                view.layoutSubtreeIfNeeded()
                for canonicalPoint in [NSPoint(x: 32, y: 18), NSPoint(x: 88, y: 22)] {
                    var points: [NSPoint] = []
                    view.pet.onPet = { points.append($0); return true }
                    let point = canonicalPoint.applying(orientation.transform(size: NSSize(width: 130, height: 74)))
                    let inWindow = view.pet.convert(point, to: nil)
                    let expected = panel.convertPoint(toScreen: inWindow)
                    let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: inWindow,
                        modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1))
                    view.pet.mouseDown(with: down)
                    view.pet.mouseUp(with: down)
                    XCTAssertEqual(points, [expected])
                    view.pet.onPet = nil
                }
            }
        }
    }

    func testDragPreservesExistingScreenSpaceHeartsWithoutEmittingAnother() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 130, height: 74),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let pet = PetView(frame: NSRect(x: 0, y: 0, width: 130, height: 74))
            pet.positionLocked = false
            panel.contentView = pet
            var effects = ClickHeartMotion()
            var emissions = 0, clears = 0
            pet.onPet = { point in
                effects.emit(at: point, now: 10)
                emissions += 1
                return true
            }
            pet.onEffectsCleared = { effects.clear(); clears += 1 }
            let windowNumber = panel.windowNumber
            func event(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            }
            for orientation in DogOrientation.allCases {
                pet.orientation = orientation
                pet.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 52, y: 20)))
                pet.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 52, y: 20)))
                let original = try XCTUnwrap(effects.hearts.last)
                let before = try XCTUnwrap(original.pose(now: 10.6))
                let windowOrigin = panel.frame.origin
                pet.mouseDown(with: try event(.leftMouseDown, at: NSPoint(x: 52, y: 20)))
                // Small hand tremor is still a click until the drag threshold is crossed.
                pet.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 54, y: 21)))
                XCTAssertEqual(panel.frame.origin, windowOrigin)
                pet.mouseDragged(with: try event(.leftMouseDragged, at: NSPoint(x: 82, y: 50)))
                XCTAssertTrue(pet.motion.isDragging)
                XCTAssertNotEqual(panel.frame.origin, windowOrigin)
                pet.mouseUp(with: try event(.leftMouseUp, at: NSPoint(x: 52, y: 20)))
                XCTAssertFalse(pet.motion.isDragging)
                XCTAssertEqual(effects.hearts.count, 1)
                XCTAssertEqual(effects.hearts.first?.origin, original.origin)
                XCTAssertEqual(effects.hearts.first?.started, original.started)
                let after = try XCTUnwrap(effects.poses(now: 10.6).first)
                XCTAssertEqual(after.x, before.x)
                XCTAssertEqual(after.y, before.y)
                XCTAssertEqual(after.alpha, before.alpha)
                let fading = try XCTUnwrap(effects.poses(now: 11.8).first)
                XCTAssertGreaterThan(fading.y, after.y)
                XCTAssertLessThan(fading.alpha, after.alpha)
                effects.advance(now: 12)
                XCTAssertTrue(effects.hearts.isEmpty)
            }
            XCTAssertEqual(emissions, DogOrientation.allCases.count)
            XCTAssertEqual(clears, 0)
        }
    }
}
