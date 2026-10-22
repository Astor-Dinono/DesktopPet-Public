import AppKit
import XCTest
@testable import DesktopPet

final class TopbarTests: XCTestCase, @unchecked Sendable {
    func testActualWorkAreaLineWinsOverMenuAndNotchHeightEstimates() async throws {
        try await MainActor.run {
            for option in DogSize.allCases { for difference in [1.0, 3.0] {
                let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
                let workArea = CGRect(x: -1440, y: -152, width: 1440, height: 828 - difference)
                let baseline = workArea.maxY
                let drawingSize = DogTopbarRenderer.drawingSize(scale: option.scale, bandHeight: 24 + difference)
                let normal = try XCTUnwrap(DogTopbarPlacement.freeFrame(centerX: -700, screen: screen,
                    topInset: 0, menuHeight: 24, left: nil, right: nil, drawingSize: drawingSize, attachmentY: baseline))
                let reserved = try XCTUnwrap(DogTopbarPlacement.frame(
                    slot: CGRect(x: normal.minX, y: 676, width: normal.width, height: 24), screen: screen,
                    topInset: 0, menuHeight: 24, left: nil, right: nil, drawingSize: drawingSize, attachmentY: baseline))
                let drop = try XCTUnwrap(DogTopbarPlacement.dropFrame(pointer: CGPoint(x: -700, y: 699),
                    startedInTopbar: false, screen: screen, topInset: 0, menuHeight: 24,
                    left: nil, right: nil, drawingSize: drawingSize, attachmentY: baseline))
                let layout = DogTopbarRenderer.layout(size: drawingSize, scale: option.scale)
                let line = normal.minY + layout.offset.y + (1 + DogRenderer.baselineY) * layout.scale
                let inverted = DogWindowPlacement(anchor: CGPoint(x: -700, y: baseline), scale: option.scale,
                    orientation: .top, visibleFrame: workArea, allowsPartialVisibility: true)
                let invertedLayout = DogLayout(scale: option.scale, orientation: .top,
                    counterInside: inverted.counterAboveDog)
                XCTAssertEqual(line, inverted.frame.minY + invertedLayout.baselineAnchor.y, accuracy: 0.000001)
                XCTAssertEqual(normal, reserved)
                XCTAssertEqual(normal, drop)
                let view = DogCompanionView(pet: PetView(frame: .zero), scale: option.scale)
                view.topbarHeight = screen.maxY - baseline
                let panel = PetPanel(contentRect: normal, styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
                panel.contentView = view
                panel.setPetFrame(normal)
                view.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(view.pet.accessibilityFrame().maxY, screen.maxY + 0.00001)
            }}
        }
    }

    func testDragStartedInTopbarCanReturnToTheVeryTopWithinTheSameGesture() throws {
        for screen in [CGRect(x: 0, y: 0, width: 1710, height: 1112),
                       CGRect(x: -1440, y: -200, width: 1440, height: 900)] {
            let bottom = screen.maxY - 38
            let head = CGRect(x: screen.midX - 45, y: bottom - 10, width: 90, height: 48)
            for y in [bottom, screen.maxY - 1, screen.maxY] {
                let frame = try XCTUnwrap(DogTopbarPlacement.dropFrame(
                    pointer: CGPoint(x: screen.midX, y: y), startedInTopbar: true,
                    screen: screen, topInset: 38, menuHeight: 22, left: nil, right: nil,
                    dogFrame: head, centerX: screen.midX))
                XCTAssertEqual(frame.minY + DogTopbarPlacement.baselineInset, bottom, accuracy: 0.00001)
            }
            for y in [bottom - 1, bottom - 15, bottom - 40] {
                XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: CGPoint(x: screen.midX, y: y),
                    startedInTopbar: true, screen: screen, topInset: 38, menuHeight: 22,
                    left: nil, right: nil, dogFrame: head, centerX: screen.midX))
            }
        }
    }

    func testHeadInsideTopBandDocksEvenWithALowGrabPointAndPreservesDogCenter() throws {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let pointer = CGPoint(x: -730, y: 640) // Below the old pointer-only trigger.
        let head = CGRect(x: -770, y: 665, width: 90, height: 38)
        let frame = try XCTUnwrap(DogTopbarPlacement.dropFrame(pointer: pointer, startedInTopbar: false,
            screen: screen, topInset: 0, menuHeight: 24, left: nil, right: nil,
            dogFrame: head, centerX: -710))
        XCTAssertEqual(frame.midX, -710)
        XCTAssertEqual(frame.minY + DogTopbarPlacement.baselineInset, 676, accuracy: 0.00001)
        XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: pointer, startedInTopbar: true,
            screen: screen, topInset: 0, menuHeight: 24, left: nil, right: nil,
            dogFrame: head, centerX: -710))
        XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: pointer, startedInTopbar: false,
            screen: screen, topInset: 0, menuHeight: 24, left: nil, right: nil,
            dogFrame: head.offsetBy(dx: 0, dy: -60), centerX: -710))
    }

    func testDockingGeometryExcludesTheTransparentHeadroomAtEverySizeAndDirection() async {
        await MainActor.run {
            _ = NSApplication.shared
            for option in DogSize.allCases { for orientation in DogOrientation.allCases {
                let pet = PetView(frame: .zero)
                let view = DogCompanionView(pet: pet, scale: option.scale)
                view.orientation = orientation
                let panel = PetPanel(contentRect: NSRect(origin: NSPoint(x: 100, y: 300),
                    size: view.layoutGeometry.size), styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
                panel.contentView = view
                view.layoutSubtreeIfNeeded()
                let head = pet.desktopDockingFrame!
                let canvas = panel.convertToScreen(pet.convert(pet.bounds, to: nil))
                XCTAssertTrue(canvas.insetBy(dx: -1, dy: -1).contains(head))
                XCTAssertLessThan(head.width * head.height, canvas.width * canvas.height * 0.7)
                view.topbarHeight = 38
                XCTAssertNil(pet.desktopDockingFrame)
            }}
        }
    }

    private func withinHorizontalArea(_ frame: CGRect, _ area: CGRect) -> Bool {
        frame.minX >= area.minX && frame.maxX <= area.maxX
    }

    func testTopbarBaselineMatchesUpsideDownDesktopAttachmentLineAtEverySize() async throws {
        try await MainActor.run {
            for option in DogSize.allCases { for band in [24.0, 38, 44] {
                let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
                let size = DogTopbarRenderer.drawingSize(scale: option.scale, bandHeight: band)
                let frame = try XCTUnwrap(DogTopbarPlacement.freeFrame(centerX: -700,
                    screen: screen, topInset: band, menuHeight: 22, left: nil, right: nil,
                    drawingSize: size))
                let layout = DogTopbarRenderer.layout(size: size, scale: option.scale)
                let visibleBaseline = frame.minY + layout.offset.y + (1 + DogRenderer.baselineY) * layout.scale
                XCTAssertEqual(visibleBaseline, screen.maxY - band, accuracy: 0.000001)
                // Actual 180° attachment: resetPosition uses visibleFrame.maxY.
                let workArea = CGRect(x: screen.minX, y: screen.minY + 48,
                    width: screen.width, height: screen.height - band - 48)
                let desktop = DogWindowPlacement(anchor: CGPoint(x: -700, y: workArea.maxY),
                    scale: option.scale, orientation: .top, visibleFrame: workArea,
                    allowsPartialVisibility: true)
                let desktopLayout = DogLayout(scale: option.scale, orientation: .top,
                    counterInside: desktop.counterAboveDog)
                let canonical = DogRenderer.canvas.applying(CGAffineTransform(scaleX: option.scale, y: option.scale))
                let ink = CGPoint(x: canonical.width / 2, y: 1 + DogRenderer.baselineY * option.scale)
                    .applying(DogOrientation.top.transform(size: canonical))
                let flippedBaseline = desktop.frame.minY + desktopLayout.petFrame.minY + ink.y
                XCTAssertEqual(visibleBaseline, flippedBaseline, accuracy: 0.000001)
                XCTAssertEqual(layout.scale, option.scale)
                let reserved = try XCTUnwrap(DogTopbarPlacement.frame(
                    slot: CGRect(x: frame.minX, y: screen.maxY - band, width: size.width, height: band),
                    screen: screen, topInset: band, menuHeight: 22, left: nil, right: nil,
                    drawingSize: size))
                XCTAssertEqual(reserved, frame)
            }}
            let size = DogTopbarRenderer.drawingSize(scale: 0.75, bandHeight: 38)
            let companion = DogCompanionView(pet: PetView(frame: .zero), scale: 0.75)
            companion.topbarHeight = 38
            companion.frame.size = size
            companion.layoutSubtreeIfNeeded()
            let offDisplayPoint = CGPoint(x: size.width / 2, y: 45)
            XCTAssertTrue(DogTopbarRenderer.contains(offDisplayPoint, size: size, pose: PetPose(),
                tail: TailPose(), tailSize: .small, scale: 0.75))
            XCTAssertFalse(companion.pet.containsInteraction(offDisplayPoint))
        }
    }

    func testSharedAttachmentLineDoesNotDrawOrHitAboveTheDisplay() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
            var rejectedOffscreenInk = 0
            for option in DogSize.allCases { for band in [24.0, 38, 44] {
                let size = DogTopbarRenderer.drawingSize(scale: option.scale, bandHeight: band)
                let frame = try XCTUnwrap(DogTopbarPlacement.freeFrame(centerX: -700,
                    screen: screen, topInset: band, menuHeight: 22, left: nil, right: nil,
                    drawingSize: size))
                let panel = PetPanel(contentRect: frame,
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                let companion = DogCompanionView(pet: PetView(frame: .zero), scale: option.scale)
                companion.topbarHeight = band
                panel.contentView = companion
                panel.setPetFrame(frame)
                companion.layoutSubtreeIfNeeded()

                let visibleHeight = min(size.height, band + DogTopbarPlacement.baselineInset)
                let axFrame = companion.pet.accessibilityFrame()
                XCTAssertEqual(axFrame.height, visibleHeight, accuracy: 0.000001)
                XCTAssertEqual(axFrame.maxY, min(frame.maxY, screen.maxY), accuracy: 0.000001)
                XCTAssertLessThanOrEqual(axFrame.maxY, screen.maxY + 0.000001)

                // Test ink above the physical edge, rather than only transparent
                // points that would already miss the original dog's paths.
                for y in stride(from: visibleHeight + 0.5, to: size.height, by: 2) {
                    for x in stride(from: 2.0, to: size.width - 2, by: 4) {
                        let point = CGPoint(x: x, y: y)
                        if DogTopbarRenderer.contains(point, size: size, pose: PetPose(),
                            tail: TailPose(), tailSize: .small, scale: option.scale) {
                            rejectedOffscreenInk += 1
                            XCTAssertFalse(companion.pet.containsInteraction(point))
                        }
                    }
                }

                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(ceil(size.width * 2)), pixelsHigh: Int(ceil(size.height * 2)),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let bytes = try XCTUnwrap(bitmap.bitmapData)
                bytes.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphics
                graphics.cgContext.scaleBy(x: 2, y: 2)
                companion.pet.draw(companion.pet.bounds)
                NSGraphicsContext.restoreGraphicsState()
                for y in 0..<bitmap.pixelsHigh {
                    let logicalY = (CGFloat(bitmap.pixelsHigh - y) - 0.5) / 2
                    for x in 0..<bitmap.pixelsWide {
                        let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                        if logicalY > visibleHeight + 0.5 {
                            XCTAssertLessThan(alpha, 0.02, "offscreen ink: \(option), menu \(band)")
                        }
                    }
                }
            }}
            XCTAssertGreaterThan(rejectedOffscreenInk, 0)
        }
    }

    func testSharedAttachmentLineKeepsAutomaticDockAndDetachAtTheRealMenuBand() async throws {
        try await MainActor.run {
            let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
            for option in DogSize.allCases { for height in [24.0, 38, 44] {
                let size = DogTopbarRenderer.drawingSize(scale: option.scale, bandHeight: height)
                let menuBottom = screen.maxY - height
                let frame = try XCTUnwrap(DogTopbarPlacement.dropFrame(
                    pointer: CGPoint(x: -700, y: menuBottom - 12), startedInTopbar: false,
                    screen: screen, topInset: height, menuHeight: 22, left: nil, right: nil,
                    drawingSize: size))
                XCTAssertNil(DogTopbarPlacement.dropFrame(
                    pointer: CGPoint(x: -700, y: menuBottom - 12.25), startedInTopbar: false,
                    screen: screen, topInset: height, menuHeight: 22, left: nil, right: nil,
                    drawingSize: size))
                let band = CGRect(x: frame.minX,
                    y: frame.minY + DogTopbarPlacement.baselineInset,
                    width: frame.width, height: height)
                XCTAssertEqual(band.minY, menuBottom, accuracy: 0.000001)
                XCTAssertEqual(band.maxY, screen.maxY, accuracy: 0.000001)
                XCTAssertFalse(DogTopbarPlacement.shouldDetach(pointerY: menuBottom - 14,
                    frame: band, pressedY: band.midY))
                XCTAssertTrue(DogTopbarPlacement.shouldDetach(pointerY: menuBottom - 14.25,
                    frame: band, pressedY: band.midY))
            }}
        }
    }

    func testSelectedSizeIsNeverReducedAndTinyKeepsThePreviousTopbarSize() async {
        await MainActor.run {
            XCTAssertEqual(DogSize.tiny.scale, DogTopbarRenderer.tinyScale)
            XCTAssertLessThan(DogSize.tiny.scale, 0.5)
            for option in DogSize.allCases {
                XCTAssertEqual(DogSize.matching(option.scale), option)
                for band in [24.0, 38, 44] {
                    let size = DogTopbarRenderer.drawingSize(scale: option.scale, bandHeight: band)
                    XCTAssertGreaterThanOrEqual(size.height, band)
                    XCTAssertEqual(DogTopbarRenderer.layout(size: size, scale: option.scale).scale, option.scale)
                    let desktop = DogCompanionView.size(scale: option.scale)
                    XCTAssertEqual(desktop.width, DogRenderer.canvas.width * option.scale)
                }
            }
            XCTAssertEqual(DogSize.matching(0.5), .small)
            XCTAssertEqual(DogSize.matching(0.62), .medium)
            XCTAssertEqual(DogSize.matching(0.75), .large)
            XCTAssertNil(DogSize.matching(.nan))
            XCTAssertNil(DogSize.matching(8))
        }
    }

    func testLargeTopbarWindowKeepsItsBaselineBelowTheMenuEdgeWithoutCrossingTheNotch() throws {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let left = CGRect(x: 0, y: 1074, width: 751, height: 38)
        let right = CGRect(x: 960, y: 1074, width: 750, height: 38)
        let size = CGSize(width: 200, height: 80)
        let frame = try XCTUnwrap(DogTopbarPlacement.freeFrame(centerX: 700, screen: screen,
            topInset: 38, menuHeight: 22, left: left, right: right, drawingSize: size))
        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.minY + DogTopbarPlacement.baselineInset, left.minY, accuracy: 0.000001)
        XCTAssertLessThan(frame.minY, left.minY)
        XCTAssertLessThanOrEqual(frame.maxX, left.maxX)
        let reserved = DogTopbarPlacement.frame(slot: CGRect(x: 1020, y: 1070, width: 200, height: 29),
            screen: screen, topInset: 38, menuHeight: 22, left: left, right: right, drawingSize: size)
        XCTAssertEqual(reserved?.height, 80)
        XCTAssertEqual(try XCTUnwrap(reserved).minY + DogTopbarPlacement.baselineInset, left.minY, accuracy: 0.000001)
    }

    func testHorizontalDragOnAHeadBelowTheMenuBandDoesNotDetach() {
        let band = CGRect(x: 0, y: 1074, width: 148, height: 38)
        XCTAssertFalse(DogTopbarPlacement.shouldDetach(pointerY: 1044, frame: band, pressedY: 1044))
        XCTAssertFalse(DogTopbarPlacement.shouldDetach(pointerY: 1035, frame: band, pressedY: 1044))
        XCTAssertTrue(DogTopbarPlacement.shouldDetach(pointerY: 1029, frame: band, pressedY: 1044))
    }

    func testAutomaticDockUsesTheReleasePointAndAvoidsTheNotch() throws {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let left = CGRect(x: 0, y: 1074, width: 751, height: 38)
        let right = CGRect(x: 960, y: 1074, width: 750, height: 38)
        for x in [0.0, 600, 850, 1100, 1710] {
            for y in [1062.0, 1074, 1112] {
                let frame = try XCTUnwrap(DogTopbarPlacement.dropFrame(pointer: CGPoint(x: x, y: y),
                    startedInTopbar: false, screen: screen, topInset: 38, menuHeight: 22,
                    left: left, right: right))
                XCTAssertTrue(withinHorizontalArea(frame, left) || withinHorizontalArea(frame, right))
                if x == 600 { XCTAssertEqual(frame.midX, x) }
            }
        }
        for point in [CGPoint(x: 600, y: 1061), CGPoint(x: -1, y: 1110),
                      CGPoint(x: 1711, y: 1110), CGPoint(x: 600, y: 1113)] {
            XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: point, startedInTopbar: false,
                screen: screen, topInset: 38, menuHeight: 22, left: left, right: right))
        }
    }

    func testAutomaticDockDoesNotPullTheSameDragBackAfterLeavingTopbar() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let point = CGPoint(x: 600, y: 1070)
        XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: point, startedInTopbar: true,
            screen: screen, topInset: 38, menuHeight: 22, left: nil, right: nil))
        XCTAssertNotNil(DogTopbarPlacement.dropFrame(pointer: point, startedInTopbar: false,
            screen: screen, topInset: 38, menuHeight: 22, left: nil, right: nil))
    }

    func testAutomaticDockUsesEachDisplaysOwnTopAndRejectsDisplayGaps() {
        let external = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        XCTAssertEqual(DogTopbarPlacement.dropFrame(pointer: CGPoint(x: -700, y: 700),
            startedInTopbar: false, screen: external, topInset: 0, menuHeight: 24,
            left: nil, right: nil)?.minY, 676 - DogTopbarPlacement.baselineInset)
        XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: CGPoint(x: 40, y: 700),
            startedInTopbar: false, screen: external, topInset: 0, menuHeight: 24,
            left: nil, right: nil))
        XCTAssertNil(DogTopbarPlacement.dropFrame(pointer: CGPoint(x: 50, y: 900),
            startedInTopbar: false, screen: CGRect(x: 0, y: 0, width: 100, height: 900),
            topInset: 0, menuHeight: 24, left: nil, right: nil))
    }

    func testDropCallbackRunsOnlyAfterRealDragAndCaptureEndsUsingOriginalReleasePoint() async throws {
        try await MainActor.run {
            let panel = PetPanel(contentRect: CGRect(x: 500, y: 500, width: 148, height: 100),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let pet = PetView(frame: CGRect(x: 0, y: 0, width: 148, height: 100))
            panel.contentView = pet
            var drops: [NSPoint] = []
            var phases: [String] = []
            pet.onDragEnded = { point in
                XCTAssertFalse(pet.hasPointerCapture)
                drops.append(point)
                phases.append("drop")
            }
            pet.onPointerRelease = { phases.append("release") }
            @MainActor func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            }
            let start = NSPoint(x: 74, y: 20)
            pet.mouseDown(with: try event(.leftMouseDown, start))
            pet.mouseUp(with: try event(.leftMouseUp, start))
            XCTAssertTrue(drops.isEmpty)
            pet.mouseDown(with: try event(.leftMouseDown, start))
            pet.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: 76, y: 21)))
            pet.mouseUp(with: try event(.leftMouseUp, CGPoint(x: 76, y: 21)))
            XCTAssertTrue(drops.isEmpty)

            let destination = NSPoint(x: 85, y: 60)
            pet.mouseDown(with: try event(.leftMouseDown, start))
            pet.mouseDragged(with: try event(.leftMouseDragged, destination))
            let expected = panel.convertPoint(toScreen: destination)
            // Legacy preview placement may move a window during its callback.
            pet.onPositionChanged = { panel.setFrameOrigin(CGPoint(x: 800, y: 800)) }
            pet.mouseUp(with: try event(.leftMouseUp, destination))
            XCTAssertEqual(drops, [expected])
            XCTAssertEqual(Array(phases.suffix(2)), ["drop", "release"])
        }
    }

    func testDraggingReportsTheEventsScreenPointRatherThanSamplingTheGlobalCursor() async throws {
        try await MainActor.run {
            let panel = PetPanel(contentRect: CGRect(x: 500, y: 500, width: 148, height: 38),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            let pet = PetView(frame: CGRect(x: 0, y: 0, width: 148, height: 38))
            pet.topbarHeight = 38
            panel.contentView = pet
            var reportedPoint: NSPoint?, reportedOffset: NSPoint?
            pet.onDragOffset = { reportedOffset = $0; reportedPoint = $1 }
            @MainActor func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            }
            let start = NSPoint(x: 74, y: 20), destination = NSPoint(x: -400, y: 20)
            pet.mouseDown(with: try event(.leftMouseDown, start))
            pet.mouseDragged(with: try event(.leftMouseDragged, destination))
            XCTAssertEqual(reportedOffset, NSPoint(x: -474, y: 0))
            XCTAssertEqual(reportedPoint, panel.convertPoint(toScreen: destination))
            XCTAssertFalse(DogTopbarPlacement.shouldDetach(pointerY: try XCTUnwrap(reportedPoint).y,
                frame: panel.petFrame))
            pet.mouseUp(with: try event(.leftMouseUp, destination))
        }
    }

    func testFreeDragCanReachBothSidesAndNeverLeavesTheDisplayOrCrossesTheNotch() throws {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let left = CGRect(x: 0, y: 1074, width: 751, height: 38)
        let right = CGRect(x: 960, y: 1074, width: 750, height: 38)
        var visitedLeft = false, visitedRight = false
        for center in stride(from: -500.0, through: 2200, by: 13) {
            let frame = try XCTUnwrap(DogTopbarPlacement.freeFrame(centerX: center, screen: screen,
                topInset: 38, menuHeight: 22, left: left, right: right))
            XCTAssertTrue(withinHorizontalArea(frame, left) || withinHorizontalArea(frame, right))
            XCTAssertEqual(frame.height, 38)
            visitedLeft = visitedLeft || withinHorizontalArea(frame, left)
            visitedRight = visitedRight || withinHorizontalArea(frame, right)
            let band = CGRect(x: frame.minX, y: left.minY, width: frame.width, height: left.height)
            XCTAssertFalse(DogTopbarPlacement.shouldDetach(pointerY: band.midY, frame: band))
            XCTAssertFalse(DogTopbarPlacement.shouldDetach(pointerY: band.minY - 8, frame: band))
            XCTAssertTrue(DogTopbarPlacement.shouldDetach(pointerY: band.minY - 20, frame: band))
        }
        XCTAssertTrue(visitedLeft && visitedRight)
        XCTAssertEqual(DogTopbarPlacement.freeFrame(centerX: 600, screen: screen, topInset: 38,
            menuHeight: 22, left: left, right: right)?.midX, 600)
        XCTAssertNil(DogTopbarPlacement.freeFrame(centerX: .nan, screen: screen, topInset: 38,
            menuHeight: 22, left: left, right: right))
    }

    func testFreeDragClampsNegativeCoordinateExternalScreensAndNarrowScreens() {
        let external = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let frame = DogTopbarPlacement.freeFrame(centerX: -1500, screen: external,
            topInset: 0, menuHeight: 24, left: nil, right: nil)
        XCTAssertEqual(frame?.minX, -1440)
        XCTAssertEqual(frame?.minY, 676 - DogTopbarPlacement.baselineInset)
        XCTAssertEqual(frame?.height, 24)
        XCTAssertNil(DogTopbarPlacement.freeFrame(centerX: 30,
            screen: CGRect(x: 0, y: 0, width: 100, height: 900),
            topInset: 0, menuHeight: 24, left: nil, right: nil))
    }

    func testFreePositionPersistsOnlyTheChosenPositionAndResetKeepsDesktopPreferences() throws {
        let name = "local.desktop-pet.topbar-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0.62, forKey: "dog.scale")
        defaults.set(210, forKey: "dog.anchorX")
        XCTAssertNil(DogTopbarPosition.load(from: defaults))
        let chosen = DogTopbarPosition(fraction: 0.37, displayID: 42)
        chosen.save(to: defaults)
        XCTAssertEqual(DogTopbarPosition.load(from: defaults), chosen)
        XCTAssertEqual(Set(defaults.persistentDomain(forName: name)!.keys),
            ["dog.scale", "dog.anchorX", DogTopbarPosition.fractionKey, DogTopbarPosition.displayKey])
        DogTopbarPosition.clear(from: defaults)
        XCTAssertNil(DogTopbarPosition.load(from: defaults))
        XCTAssertEqual(defaults.double(forKey: "dog.scale"), 0.62)
        XCTAssertEqual(defaults.double(forKey: "dog.anchorX"), 210)
        defaults.set(-0.2, forKey: DogTopbarPosition.fractionKey)
        defaults.set(42, forKey: DogTopbarPosition.displayKey)
        XCTAssertNil(DogTopbarPosition.load(from: defaults))
    }

    func testTopbarIsPixelIdenticalToUniformlyPlacedOriginalDog() async throws {
        try await MainActor.run {
            let size = CGSize(width: 148, height: 38)
            let poses = [PetPose(), PetPose(breath: 1.35), PetPose(squash: -0.20),
                         PetPose(sleep: 1, sleepBubble: 1, sleepLetters: 1, sleepSettle: 1)]
            for pose in poses { for tailSize in DogTailSize.allCases {
                @MainActor func render(original: Bool) throws -> Data {
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                        pixelsWide: 296, pixelsHigh: 76, bitsPerSample: 8, samplesPerPixel: 4,
                        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                        bytesPerRow: 296 * 4, bitsPerPixel: 32))
                    let bytes = try XCTUnwrap(bitmap.bitmapData)
                    bytes.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                    let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                    NSGraphicsContext.saveGraphicsState()
                    defer { NSGraphicsContext.restoreGraphicsState() }
                    NSGraphicsContext.current = graphics
                    graphics.cgContext.scaleBy(x: 2, y: 2)
                    let tail = TailPose(angle: -0.21, bend: 0.36)
                    if original {
                        let placement = DogTopbarRenderer.layout(size: size)
                        graphics.cgContext.translateBy(x: placement.offset.x, y: placement.offset.y)
                        graphics.cgContext.scaleBy(x: placement.scale, y: placement.scale)
                        var originalPose = pose
                        originalPose.sleepLetters = 0
                        DogRenderer.draw(in: graphics.cgContext, size: DogRenderer.canvas,
                            pose: originalPose, angle: tail.angle, bend: tail.bend, tailSize: tailSize)
                    } else {
                        DogTopbarRenderer.draw(in: graphics.cgContext, size: size, pose: pose,
                            tail: tail, blink: 0, tailSize: tailSize)
                    }
                    return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                }
                XCTAssertEqual(try render(original: false), try render(original: true))
            }}
        }
    }

    func testPlacementUsesOnlyItsReservedSlotAndRejectsNotchAndHiddenMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let left = CGRect(x: 0, y: 1074, width: 751, height: 38)
        let right = CGRect(x: 960, y: 1074, width: 750, height: 38)
        let good = DogTopbarPlacement.frame(slot: CGRect(x: 1015, y: 1069.5, width: 148.5, height: 29),
            screen: screen, topInset: 38, menuHeight: 22, left: left, right: right)
        XCTAssertEqual(good?.minY, 1074 - DogTopbarPlacement.baselineInset)
        XCTAssertEqual(good?.height, 38)
        XCTAssertTrue(withinHorizontalArea(good!, right))
        for bad in [CGRect(x: 820, y: 1070, width: 148, height: 29),
                    CGRect(x: 1015, y: 1120, width: 148, height: 29),
                    CGRect(x: 1015, y: 1070, width: 50, height: 29)] {
            XCTAssertNil(DogTopbarPlacement.frame(slot: bad, screen: screen, topInset: 38,
                menuHeight: 22, left: left, right: right))
        }
        let external = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let frame = DogTopbarPlacement.frame(slot: CGRect(x: -240, y: 677, width: 148, height: 22),
            screen: external, topInset: 0, menuHeight: 24, left: nil, right: nil)
        XCTAssertEqual(frame?.minY, 676 - DogTopbarPlacement.baselineInset)
        XCTAssertEqual(frame?.height, 24)
    }

    func testTopbarCounterIsHiddenAndDoesNotAddFooterOrAffectRestoredLayout() async {
        await MainActor.run {
            let companion = DogCompanionView(pet: PetView(frame: .zero), scale: 0.62)
            companion.alwaysShowCount = true
            let old = companion.layoutGeometry
            companion.topbarHeight = 38
            companion.frame.size = companion.layoutGeometry.size
            companion.layoutSubtreeIfNeeded()
            XCTAssertEqual(companion.bounds.height, DogTopbarRenderer.drawingSize(scale: 0.62, bandHeight: 38).height)
            XCTAssertEqual(companion.badgeFrame, .zero)
            XCTAssertEqual(companion.subviews.compactMap { $0 as? NSTextField }.first?.alphaValue, 0)
            companion.topbarHeight = nil
            XCTAssertEqual(companion.layoutGeometry.size, old.size)
            XCTAssertEqual(companion.layoutGeometry.baselineAnchor, old.baselineAnchor)
            XCTAssertEqual(companion.scale, 0.62)
        }
    }

    func testTopbarKeepsInkInsideTheStripThroughBreathingBounceSleepAndBothTails() async throws {
        try await MainActor.run {
            let poses = [PetPose(), PetPose(breath: 1.35), PetPose(breath: -1.35),
                PetPose(squash: 0.15), PetPose(squash: -0.12),
                PetPose(sleep: 1, sleepBubble: 1, sleepSettle: 1), PetPose(affection: 1)]
            for option in DogSize.allCases { for band in [24.0, 38, 44] { for tailSize in DogTailSize.allCases { for pose in poses {
                let size = DogTopbarRenderer.drawingSize(scale: option.scale, bandHeight: band)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: Int(ceil(size.width * 2)), pixelsHigh: Int(ceil(size.height * 2)), bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0))
                let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                graphics.cgContext.scaleBy(x: 2, y: 2)
                DogTopbarRenderer.draw(in: graphics.cgContext, size: size, pose: pose,
                    tail: TailPose(angle: 0.21, bend: 0.36), blink: 0, tailSize: tailSize, scale: option.scale)
                NSGraphicsContext.restoreGraphicsState()
                for x in 0..<bitmap.pixelsWide {
                    XCTAssertLessThan(bitmap.colorAt(x: x, y: 0)!.alphaComponent, 0.02, "top, size \(option), band \(band)")
                }
                for y in 0..<bitmap.pixelsHigh {
                    XCTAssertLessThan(bitmap.colorAt(x: 0, y: y)!.alphaComponent, 0.02)
                    XCTAssertLessThan(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: y)!.alphaComponent, 0.02)
                }
            }}}}
        }
    }

    func testTopbarHitTestingMatchesVisibleInkInsteadOfTheReservedRectangle() async throws {
        try await MainActor.run {
            for pose in [PetPose(), PetPose(squash: 0.15), PetPose(squash: -0.12)] {
                let size = CGSize(width: 148, height: 38), tail = TailPose(angle: -0.21, bend: -0.36)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 296,
                    pixelsHigh: 76, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                graphics.cgContext.scaleBy(x: 2, y: 2)
                DogTopbarRenderer.draw(in: graphics.cgContext, size: size, pose: pose,
                    tail: tail, blink: 0, tailSize: .small)
                NSGraphicsContext.restoreGraphicsState()
                var mismatches = 0
                for y in stride(from: 2, to: 74, by: 4) { for x in stride(from: 2, to: 294, by: 4) {
                    let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                    guard alpha < 0.01 || alpha > 0.99 else { continue }
                    let hit = DogTopbarRenderer.contains(CGPoint(x: (Double(x) + 0.5) / 2,
                        y: (76 - Double(y) - 0.5) / 2), size: size, pose: pose, tail: tail, tailSize: .small)
                    if hit != (alpha > 0.99) { mismatches += 1 }
                }}
                XCTAssertLessThanOrEqual(mismatches, 2)
            }
        }
    }
}
