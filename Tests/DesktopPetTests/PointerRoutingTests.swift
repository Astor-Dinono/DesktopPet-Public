import AppKit
import XCTest
@testable import DesktopPet

final class PointerRoutingTests: XCTestCase, @unchecked Sendable {
    func testDesktopDogReenteringMenuBandRestoresItsInteractiveLevel() async {
        await MainActor.run {
            _ = NSApplication.shared
            let band = NSRect(x: -1440, y: 662, width: 1440, height: 38)
            let panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            let view = DogCompanionView(pet: PetView(frame: .zero), scale: 0.5)
            panel.contentView = view
            // Repeat actual desktop placement / top-area placement, including
            // the window being made click-through during a mode transition.
            for _ in 0..<3 {
                panel.setPetFrame(NSRect(x: -800, y: 400, width: 130, height: 98))
                XCTAssertFalse(panel.updateDesktopLevel(menuBands: [band]))
                XCTAssertEqual(panel.level, .floating)
                panel.stopPointerRouting()
                panel.setPetFrame(NSRect(x: -800, y: 640.25, width: 130, height: 98))
                view.layoutSubtreeIfNeeded()
                XCTAssertTrue(panel.updateDesktopLevel(menuBands: [band]))
                XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.statusBar.rawValue)
                let head = view.pet.convert(NSPoint(x: 52, y: 20), to: view)
                panel.updatePointerRouting(at: head, pressedButtons: 0)
                XCTAssertFalse(panel.ignoresMouseEvents)
                panel.updatePointerRouting(at: head, pressedButtons: 1)
                XCTAssertTrue(panel.ignoresMouseEvents, "Foreign drags must still pass through")
                panel.updatePointerRouting(at: NSPoint(x: 3, y: view.bounds.maxY - 3), pressedButtons: 0)
                XCTAssertTrue(panel.ignoresMouseEvents)
                XCTAssertFalse(panel.canBecomeKey)
            }
        }
    }

    func testHitRegionMatchesRenderedSilhouetteWhileBouncingAndWagging() async throws {
        try await MainActor.run {
            for (scale, tailSize) in [0.5, 0.75].flatMap({ scale in DogTailSize.allCases.map { (scale, $0) } }) {
                let size = NSSize(width: 260 * scale, height: 148 * scale)
                let width = Int(size.width * 2), height = Int(size.height * 2)
                for (squash, angle, bend, breath) in [(0.0, 0.0, 0.0, 0.0),
                    (0.15, 0.21, 0.36, 0.0), (-0.12, -0.21, -0.36, 0.0),
                    (0.0, 0.0, 0.0, 1.35), (0.0, 0.0, 0.0, -1.35)] {
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                        pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = graphics
                    graphics.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
                    graphics.cgContext.scaleBy(x: 2, y: 2)
                    let pose = PetPose(breath: breath, squash: squash)
                    DogRenderer.draw(in: graphics.cgContext, size: size, pose: pose, angle: angle, bend: bend, tailSize: tailSize)
                    NSGraphicsContext.restoreGraphicsState()
                    var mismatches = 0
                    for y in stride(from: 2, to: height, by: 4) {
                        for x in stride(from: 2, to: width, by: 4) {
                            let alpha = try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
                            // Skip antialiased boundary pixels; compare solid ink/fill and clear space.
                            guard alpha < 0.01 || alpha > 0.99 else { continue }
                            let point = NSPoint(x: (Double(x) + 0.5) / 2,
                                                y: (Double(height - y) - 0.5) / 2)
                            let hit = DogRenderer.contains(point, size: size, pose: pose, angle: angle, bend: bend, tailSize: tailSize)
                            if hit != (alpha > 0.99) { mismatches += 1 }
                        }
                    }
                    XCTAssertLessThanOrEqual(mismatches, 2, "scale \(scale), squash \(squash), angle \(angle)")
                }
            }
        }
    }

    func testTransparentPaddingPassesThroughAndDogReceivesClicksWithoutTakingFocus() async {
        await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            let view = DogCompanionView(pet: PetView(frame: .zero), scale: 0.5)
            panel.setContentSize(view.frame.size)
            panel.contentView = view
            view.layoutSubtreeIfNeeded()
            panel.updatePointerRouting(at: NSPoint(x: 4, y: view.bounds.maxY - 4), pressedButtons: 0)
            XCTAssertTrue(panel.ignoresMouseEvents)
            panel.updatePointerRouting(at: NSPoint(x: 52, y: view.dogOffsetY + 20), pressedButtons: 0)
            XCTAssertFalse(panel.ignoresMouseEvents)
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertFalse(panel.canBecomeMain)
            panel.stopPointerRouting()
            XCTAssertTrue(panel.ignoresMouseEvents)
        }
    }

    func testVisibleBadgeReceivesClicksAndHiddenBadgeDoesNot() async throws {
        try await MainActor.run {
            for above in [false, true] {
                let view = DogCompanionView(pet: PetView(frame: .zero), scale: 0.5)
                view.counterAboveDog = above
                view.frame.size = DogCompanionView.size(scale: 0.5, counterAboveDog: above)
                view.layoutSubtreeIfNeeded()
                let badge = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
                let point = NSPoint(x: badge.frame.midX, y: badge.frame.midY)
                XCTAssertFalse(view.containsInteraction(point))
                view.alwaysShowCount = true
                XCTAssertTrue(view.containsInteraction(point))
                XCTAssertFalse(view.containsInteraction(NSPoint(x: badge.frame.minX + 0.1,
                                                                 y: badge.frame.minY + 0.1)))
            }
        }
    }

    func testOwnDragKeepsCaptureButDraggingFromAnotherWindowCannotGrabDog() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            let view = DogCompanionView(pet: PetView(frame: .zero), scale: 0.5)
            panel.setContentSize(view.frame.size)
            panel.contentView = view
            view.layoutSubtreeIfNeeded()
            let dogPoint = NSPoint(x: 52, y: view.dogOffsetY + 20)
            panel.updatePointerRouting(at: dogPoint, pressedButtons: 1)
            XCTAssertTrue(panel.ignoresMouseEvents)
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: dogPoint,
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            view.pet.mouseDown(with: down)
            panel.updatePointerRouting(at: NSPoint(x: -500, y: -500), pressedButtons: 1)
            XCTAssertFalse(panel.ignoresMouseEvents)
            view.pet.mouseUp(with: down)
            panel.updatePointerRouting(at: NSPoint(x: -500, y: -500), pressedButtons: 0)
            XCTAssertTrue(panel.ignoresMouseEvents)
            XCTAssertFalse(view.pet.hasPointerCapture)
        }
    }
}
