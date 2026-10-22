import AppKit
import XCTest
@testable import DesktopPet

final class CounterViewTests: XCTestCase, @unchecked Sendable {
    func testPinnedBaselineAndCounterStayVisibleAtEverySizeAndScreenOrigin() async throws {
        try await MainActor.run {
            for area in [NSRect(x: 0, y: 62, width: 1440, height: 816),
                         NSRect(x: -1920, y: -800, width: 1920, height: 1080)] {
                for scale in [0.50, 0.62, 0.75] {
                    let placement = DogWindowPlacement(x: area.maxX - 200, baseline: area.minY,
                                                       scale: scale, visibleFrame: area)
                    XCTAssertTrue(placement.counterAboveDog)
                    let view = DogCompanionView(pet: PetView(frame: .zero), scale: scale)
                    view.counterAboveDog = placement.counterAboveDog
                    view.frame = NSRect(origin: .zero, size: placement.frame.size)
                    view.layoutSubtreeIfNeeded()
                    let badge = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
                    let edge = placement.frame.minY + view.pet.frame.minY + 1 + DogRenderer.baselineY * scale
                    XCTAssertEqual(edge, area.minY, accuracy: 0.001)
                    XCTAssertEqual(view.pet.frame.height, DogRenderer.canvas.height * scale, accuracy: 0.001)
                    XCTAssertGreaterThan(badge.frame.minY, 1 + 80 * scale) // clear of the head
                    XCTAssertTrue(area.contains(badge.frame.offsetBy(dx: placement.frame.minX, dy: placement.frame.minY)))
                }
            }
        }
    }

    func testChangingCounterSidePreservesTheRequestedBaselineAndStaysOnScreen() async {
        await MainActor.run {
            let area = NSRect(x: 0, y: 60, width: 1200, height: 800)
            for baseline: CGFloat in [60, 70, 86, 88, 100, 500] {
                let placement = DogWindowPlacement(x: 2000, baseline: baseline, scale: 0.62, visibleFrame: area)
                let offset = placement.counterAboveDog ? 0 : DogCompanionView.footerHeight
                XCTAssertEqual(placement.frame.minY + offset + 1 + DogRenderer.baselineY * 0.62,
                               baseline, accuracy: 0.001)
                XCTAssertLessThanOrEqual(placement.frame.maxX, area.maxX)
                XCTAssertLessThanOrEqual(placement.frame.maxY, area.maxY)
                if !placement.counterAboveDog { XCTAssertGreaterThanOrEqual(placement.frame.minY, area.minY) }
            }
        }
    }

    func testHoverAndPinnedModesKeepTheDogSizeAndCounterBelowIt() async throws {
        try await MainActor.run {
            let dog = PetView(frame: .zero)
            let view = DogCompanionView(pet: dog, scale: 0.62)
            view.layoutSubtreeIfNeeded()
            let badge = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
            let original = dog.frame
            XCTAssertEqual(original.width, 161.2, accuracy: 0.001)
            XCTAssertEqual(original.height, 91.76, accuracy: 0.001)
            XCTAssertLessThanOrEqual(badge.frame.maxY, original.minY)
            XCTAssertTrue(badge.isAccessibilityHidden())
            let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            let exited = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, trackingNumber: 0, userData: nil))
            view.mouseEntered(with: entered)
            XCTAssertFalse(badge.isAccessibilityHidden())
            view.mouseExited(with: exited)
            XCTAssertTrue(badge.isAccessibilityHidden())
            view.alwaysShowCount = true
            view.mouseExited(with: exited)
            XCTAssertFalse(badge.isAccessibilityHidden())
            view.updateCount(Int.max)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(badge.stringValue, String(Int.max))
            XCTAssertTrue(view.bounds.contains(badge.frame))
            XCTAssertEqual(dog.frame, original)
            view.alwaysShowCount = false
            XCTAssertTrue(badge.isAccessibilityHidden())
        }
    }
}
