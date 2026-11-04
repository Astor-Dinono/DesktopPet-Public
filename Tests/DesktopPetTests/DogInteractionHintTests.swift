import AppKit
import XCTest
@testable import DesktopPet

final class DogInteractionHintTests: XCTestCase, @unchecked Sendable {
    func testPrefersAboveThenBelowForTopbarAndTopEdge() throws {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        let middle = NSRect(x: 350, y: 250, width: 100, height: 80)
        let above = try XCTUnwrap(DogInteractionHintLayout.frame(anchor: middle, obstacle: nil, screen: screen))
        XCTAssertEqual(above.minY, middle.maxY + DogInteractionHintLayout.gap)
        for anchor in [NSRect(x: 350, y: 540, width: 100, height: 60),
                       NSRect(x: 350, y: 600, width: 100, height: 38)] {
            let below = try XCTUnwrap(DogInteractionHintLayout.frame(anchor: anchor, obstacle: nil, screen: screen))
            XCTAssertEqual(below.maxY, anchor.minY - DogInteractionHintLayout.gap)
            XCTAssertTrue(screen.contains(below))
            XCTAssertFalse(below.intersects(anchor))
        }
    }

    func testFourEdgesStayInsideWorkAreaAndClearTheDog() throws {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 600)
        for anchor in [NSRect(x: 0, y: 250, width: 100, height: 80),
                       NSRect(x: 700, y: 250, width: 100, height: 80),
                       NSRect(x: 350, y: 0, width: 100, height: 80),
                       NSRect(x: 350, y: 520, width: 100, height: 80)] {
            let frame = try XCTUnwrap(DogInteractionHintLayout.frame(anchor: anchor, obstacle: nil, screen: screen))
            XCTAssertEqual(frame.size, DogInteractionHintLayout.size)
            XCTAssertTrue(screen.contains(frame))
            XCTAssertFalse(frame.intersects(anchor))
        }
    }

    func testFallsBackToSideWithoutCompressingText() throws {
        let screen = NSRect(x: 0, y: 0, width: 800, height: 120)
        let dog = NSRect(x: 350, y: 20, width: 100, height: 80)
        let frame = try XCTUnwrap(DogInteractionHintLayout.frame(anchor: dog, obstacle: nil, screen: screen))
        XCTAssertEqual(frame.maxX, dog.minX - DogInteractionHintLayout.gap)
        XCTAssertEqual(frame.size, NSSize(width: 210, height: 104))
        XCTAssertTrue(screen.contains(frame))
    }

    func testNegativeScreenAndVisibleCounterAreBothRespected() throws {
        let screen = NSRect(x: -1440, y: -500, width: 1440, height: 900)
        let dog = NSRect(x: -900, y: -280, width: 120, height: 80)
        let counter = NSRect(x: -870, y: -192, width: 60, height: 18)
        let frame = try XCTUnwrap(DogInteractionHintLayout.frame(anchor: dog, obstacle: counter, screen: screen))
        XCTAssertTrue(screen.contains(frame))
        XCTAssertEqual(frame.minY, counter.maxY + DogInteractionHintLayout.gap)
        XCTAssertFalse(frame.intersects(dog))
        XCTAssertFalse(frame.intersects(counter))
    }

    func testInsufficientOrInvalidSpaceHidesInsteadOfCoveringDog() {
        let dog = NSRect(x: 140, y: 65, width: 40, height: 20)
        for screen in [NSRect(x: 0, y: 0, width: 200, height: 600),
                       NSRect(x: 0, y: 0, width: 800, height: 100),
                       NSRect(x: 0, y: 0, width: 320, height: 150), .zero] {
            XCTAssertNil(DogInteractionHintLayout.frame(anchor: dog, obstacle: nil, screen: screen))
        }
        XCTAssertNil(DogInteractionHintLayout.frame(anchor: NSRect(x: CGFloat.nan, y: 0, width: 20, height: 20),
            obstacle: nil, screen: NSRect(x: 0, y: 0, width: 800, height: 600)))
    }

    func testCloseDismissesOnlyThisLaunchAndManualReopenDoesNotPersist() async throws {
        try await MainActor.run {
            let (name, defaults) = try isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let hint = DogInteractionHint(defaults: defaults)
            XCTAssertFalse(hint.isRequested)
            hint.requestAutomatically()
            XCTAssertTrue(hint.isRequested)
            hint.dismiss(permanently: false)
            XCTAssertFalse(hint.isRequested)
            hint.requestAutomatically()
            XCTAssertFalse(hint.isRequested)
            XCTAssertNil(defaults.object(forKey: DogInteractionHint.disabledKey))
            hint.showManually()
            XCTAssertTrue(hint.isRequested)
            hint.dismiss(permanently: false)
            let nextLaunch = DogInteractionHint(defaults: defaults)
            nextLaunch.requestAutomatically()
            XCTAssertTrue(nextLaunch.isRequested)
        }
    }

    func testNeverShowAgainPersistsButManualReopenKeepsThePreference() async throws {
        try await MainActor.run {
            let (name, defaults) = try isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let hint = DogInteractionHint(defaults: defaults)
            hint.requestAutomatically()
            hint.dismiss(permanently: true)
            XCTAssertFalse(hint.isRequested)
            XCTAssertTrue(defaults.bool(forKey: DogInteractionHint.disabledKey))
            let nextLaunch = DogInteractionHint(defaults: defaults)
            nextLaunch.requestAutomatically()
            XCTAssertFalse(nextLaunch.isRequested)
            nextLaunch.showManually()
            XCTAssertTrue(nextLaunch.isRequested)
            nextLaunch.dismiss(permanently: false)
            XCTAssertTrue(defaults.bool(forKey: DogInteractionHint.disabledKey))
            nextLaunch.requestAutomatically()
            XCTAssertFalse(nextLaunch.isRequested)
        }
    }

    func testTemporaryHidingAndLackOfRoomPreserveRequest() async throws {
        try await MainActor.run {
            let (name, defaults) = try isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: name) }
            let hint = DogInteractionHint(defaults: defaults)
            hint.requestAutomatically()
            hint.hide()
            XCTAssertTrue(hint.isRequested)
            hint.update(anchor: NSRect(x: 30, y: 30, width: 30, height: 30),
                screen: NSRect(x: 0, y: 0, width: 100, height: 100), visible: true, level: .floating)
            XCTAssertTrue(hint.isRequested)
            hint.update(anchor: NSRect(x: 30, y: 30, width: 30, height: 30),
                screen: NSRect(x: 0, y: 0, width: 800, height: 600), visible: false, level: .floating)
            XCTAssertTrue(hint.isRequested)
            XCTAssertNil(defaults.object(forKey: DogInteractionHint.disabledKey))
        }
    }

    func testCopyMatchesLockedAndLegacyUnlockedInteraction() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let view = DogInteractionHintContentView(frame: NSRect(origin: .zero, size: DogInteractionHintLayout.size))
            let label = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextField }.first)
            XCTAssertEqual(label.stringValue, "双击按住拖动我\n按住来回摸摸我")
            view.setPositionLocked(false)
            XCTAssertEqual(label.stringValue, "按住拖动我\n点一下摸摸我")
            XCTAssertEqual(view.closeButton.title, "关闭")
            XCTAssertEqual(view.disableButton.title, "不再提示")
            XCTAssertEqual(view.closeButton.accessibilityRole(), .button)
            XCTAssertEqual(view.disableButton.accessibilityRole(), .button)
        }
    }

    private func isolatedDefaults() throws -> (String, UserDefaults) {
        let name = "DesktopPet.InteractionHintTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        return (name, defaults)
    }
}
