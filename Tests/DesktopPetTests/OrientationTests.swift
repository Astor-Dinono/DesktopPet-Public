import AppKit
import XCTest
@testable import DesktopPet

final class OrientationTests: XCTestCase, @unchecked Sendable {
    func testQuarterTurnsPutBaselineOnTheRequestedSideAndRoundTripPoints() {
        let size = NSSize(width: 260, height: 148)
        let expected: [DogOrientation: NSPoint] = [
            .bottom: NSPoint(x: 130, y: 0), .left: NSPoint(x: 0, y: 130),
            .top: NSPoint(x: 130, y: 148), .right: NSPoint(x: 148, y: 130)
        ]
        for orientation in DogOrientation.allCases {
            let transform = orientation.transform(size: size)
            XCTAssertEqual(NSPoint(x: 130, y: 0).applying(transform), expected[orientation])
            for point in [NSPoint.zero, NSPoint(x: 77, y: 54), NSPoint(x: 260, y: 148)] {
                XCTAssertEqual(point.applying(transform).applying(transform.inverted()), point)
            }
        }
    }

    func testEveryEdgeKeepsBaselinePinnedAndCounterUprightOnDifferentScreensAndSizes() async {
        await MainActor.run {
            for area in [NSRect(x: 0, y: 60, width: 1440, height: 800),
                         NSRect(x: -1920, y: -800, width: 1920, height: 1080)] {
                for scale in [0.50, 0.62, 0.75] {
                    for orientation in DogOrientation.allCases {
                        let anchor: NSPoint
                        switch orientation {
                        case .bottom: anchor = NSPoint(x: area.midX, y: area.minY)
                        case .left: anchor = NSPoint(x: area.minX, y: area.midY)
                        case .top: anchor = NSPoint(x: area.midX, y: area.maxY)
                        case .right: anchor = NSPoint(x: area.maxX, y: area.midY)
                        }
                        // Wide enough for the largest saved aggregate; never rotate the number.
                        let placement = DogWindowPlacement(anchor: anchor, scale: scale,
                            orientation: orientation, badgeWidth: 140, visibleFrame: area)
                        let layout = DogLayout(scale: scale, orientation: orientation,
                            counterInside: placement.counterAboveDog, badgeWidth: 140)
                        let actual = NSPoint(x: placement.frame.minX + layout.baselineAnchor.x,
                                             y: placement.frame.minY + layout.baselineAnchor.y)
                        XCTAssertEqual(actual.x, anchor.x, accuracy: 0.00001)
                        XCTAssertEqual(actual.y, anchor.y, accuracy: 0.00001)
                        XCTAssertTrue(area.contains(layout.badgeFrame.offsetBy(dx: placement.frame.minX,
                                                                              dy: placement.frame.minY)))
                        XCTAssertEqual(layout.badgeFrame.height, 18)
                        XCTAssertEqual(orientation.rotatedSize(layout.petFrame.size),
                                       NSSize(width: 260 * scale, height: 148 * scale))
                    }
                }
            }
        }
    }

    func testTopCounterChangesSideWithoutMovingBaselineAndOutOfBoundsPositionsClamp() async {
        await MainActor.run {
            let area = NSRect(x: -1000, y: -500, width: 1000, height: 800)
            for orientation in DogOrientation.allCases {
                for anchor in [NSPoint(x: -9999, y: -9999), NSPoint(x: 9999, y: 9999),
                               NSPoint(x: -500, y: 280), NSPoint(x: -500, y: 230)] {
                    let placement = DogWindowPlacement(anchor: anchor, scale: 0.62,
                        orientation: orientation, visibleFrame: area)
                    let layout = DogLayout(scale: 0.62, orientation: orientation,
                                           counterInside: placement.counterAboveDog)
                    let edge = NSPoint(x: placement.frame.minX + layout.baselineAnchor.x,
                                       y: placement.frame.minY + layout.baselineAnchor.y)
                    XCTAssertTrue((area.minX...area.maxX).contains(edge.x))
                    XCTAssertTrue((area.minY...area.maxY).contains(edge.y))
                    XCTAssertTrue(area.contains(layout.badgeFrame.offsetBy(dx: placement.frame.minX,
                                                                          dy: placement.frame.minY)))
                    if orientation == .top, anchor.x == -500 {
                        XCTAssertEqual(edge.y, anchor.y, accuracy: 0.00001)
                        XCTAssertEqual(placement.counterAboveDog, anchor.y == 280)
                    }
                }
            }
        }
    }

    func testFreePlacementPreservesChosenAnchorAcrossDirectionsSizesAndScreens() async {
        await MainActor.run {
            for area in [NSRect(x: 0, y: 0, width: 1710, height: 1112),
                         NSRect(x: -1440, y: -200, width: 1440, height: 900)] {
                let anchors = [NSPoint(x: area.minX, y: area.minY),
                               NSPoint(x: area.maxX, y: area.minY),
                               NSPoint(x: area.minX, y: area.maxY),
                               NSPoint(x: area.maxX, y: area.maxY),
                               NSPoint(x: area.midX, y: area.midY),
                               NSPoint(x: area.minX + 1, y: area.maxY - 1)]
                for size in DogSize.allCases { for orientation in DogOrientation.allCases {
                    for anchor in anchors {
                        let placement = DogWindowPlacement(anchor: anchor, scale: size.scale,
                            orientation: orientation, badgeWidth: 140, visibleFrame: area,
                            allowsPartialVisibility: true)
                        let layout = DogLayout(scale: size.scale, orientation: orientation,
                            counterInside: placement.counterAboveDog, badgeWidth: 140)
                        XCTAssertEqual(placement.frame.minX + layout.baselineAnchor.x,
                                       anchor.x, accuracy: 0.00001)
                        XCTAssertEqual(placement.frame.minY + layout.baselineAnchor.y,
                                       anchor.y, accuracy: 0.00001)
                        XCTAssertEqual(orientation.rotatedSize(layout.petFrame.size),
                                       NSSize(width: 260 * size.scale, height: 148 * size.scale))
                        if orientation == .bottom, anchor.y == area.minY {
                            XCTAssertTrue(placement.counterAboveDog)
                        } else if orientation == .top, anchor.y == area.maxY {
                            XCTAssertTrue(placement.counterAboveDog)
                        } else if orientation.isVertical {
                            XCTAssertFalse(placement.counterAboveDog)
                        }
                    }
                }}
            }
        }
    }

    func testUnrotatedFreePlacementCanStayInTheFormerTopDeadZone() async {
        await MainActor.run {
            let screen = NSRect(x: 0, y: 0, width: 1710, height: 1112)
            let workArea = NSRect(x: 0, y: 48, width: 1710, height: 1026)
            for size in DogSize.allCases {
                for y in [workArea.maxY - 36, screen.maxY - 8] {
                    let anchor = NSPoint(x: screen.midX, y: y)
                    let oldPlacement = DogWindowPlacement(anchor: anchor, scale: size.scale,
                        orientation: .bottom, visibleFrame: workArea)
                    let oldLayout = DogLayout(scale: size.scale, orientation: .bottom,
                        counterInside: oldPlacement.counterAboveDog)
                    XCTAssertLessThan(oldPlacement.frame.minY + oldLayout.baselineAnchor.y, y)

                    let placement = DogWindowPlacement(anchor: anchor, scale: size.scale,
                        orientation: .bottom, visibleFrame: screen, allowsPartialVisibility: true)
                    let layout = DogLayout(scale: size.scale, orientation: .bottom,
                        counterInside: placement.counterAboveDog)
                    XCTAssertEqual(placement.frame.minY + layout.baselineAnchor.y, y, accuracy: 0.00001)
                    XCTAssertEqual(layout.petFrame.size,
                                   NSSize(width: 260 * size.scale, height: 148 * size.scale))
                    if y > workArea.maxY {
                        // The transparent canvas may cross the display top; its
                        // bounds must not force the chosen anchor downward.
                        XCTAssertGreaterThan(placement.frame.maxY, screen.maxY)
                    }
                }
            }
        }
    }

    func testFreePlacementClampsOffscreenAnchorsWithoutMovingTheOtherAxis() async {
        await MainActor.run {
            let area = NSRect(x: -1440, y: -200, width: 1440, height: 900)
            let samples: [(requested: NSPoint, expected: NSPoint)] = [
                (NSPoint(x: -5000, y: 5000), NSPoint(x: area.minX, y: area.maxY)),
                (NSPoint(x: 5000, y: -5000), NSPoint(x: area.maxX, y: area.minY)),
                (NSPoint(x: area.midX, y: area.maxY + 1), NSPoint(x: area.midX, y: area.maxY)),
                (NSPoint(x: area.minX - 1, y: area.midY), NSPoint(x: area.minX, y: area.midY))
            ]
            for size in DogSize.allCases { for orientation in DogOrientation.allCases {
                for sample in samples {
                    let placement = DogWindowPlacement(anchor: sample.requested, scale: size.scale,
                        orientation: orientation, visibleFrame: area, allowsPartialVisibility: true)
                    let layout = DogLayout(scale: size.scale, orientation: orientation,
                        counterInside: placement.counterAboveDog)
                    let actual = NSPoint(x: placement.frame.minX + layout.baselineAnchor.x,
                                         y: placement.frame.minY + layout.baselineAnchor.y)
                    XCTAssertEqual(actual.x, sample.expected.x, accuracy: 0.00001)
                    XCTAssertEqual(actual.y, sample.expected.y, accuracy: 0.00001)
                }
            }}
        }
    }

    func testRotatedDogHitTestingAndAccessibilityFrameFollowTheVisibleHead() async {
        await MainActor.run {
            _ = NSApplication.shared
            let panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            for orientation in DogOrientation.allCases {
                let canonical = NSSize(width: 130, height: 74)
                let view = DogCompanionView(pet: PetView(frame: .zero), scale: 0.5)
                view.orientation = orientation
                panel.setContentSize(view.layoutGeometry.size)
                panel.contentView = view
                view.layoutSubtreeIfNeeded()
                let transform = orientation.transform(size: canonical)
                let head = NSPoint(x: 52, y: 20).applying(transform)
                let clear = NSPoint(x: 4, y: 68).applying(transform)
                XCTAssertTrue(view.pet.containsInteraction(head))
                XCTAssertFalse(view.pet.containsInteraction(clear))
                XCTAssertTrue(view.pet.accessibilityFrame().contains(panel.convertPoint(toScreen: view.pet.convert(head, to: nil))))
                panel.updatePointerRouting(at: view.pet.convert(clear, to: view), pressedButtons: 0)
                XCTAssertTrue(panel.ignoresMouseEvents)
                panel.updatePointerRouting(at: view.pet.convert(head, to: view), pressedButtons: 0)
                XCTAssertFalse(panel.ignoresMouseEvents)
            }
        }
    }

    func testGrowingCounterDoesNotPushVerticalBaselineAwayFromTheBar() async {
        await MainActor.run {
            let area = NSRect(x: 0, y: 0, width: 1400, height: 900)
            for orientation in [DogOrientation.left, .right] {
                let anchor = NSPoint(x: orientation == .left ? area.minX : area.maxX, y: area.midY)
                for width: CGFloat in [30, 50, 90, 140] {
                    let placement = DogWindowPlacement(anchor: anchor, scale: 0.5,
                        orientation: orientation, badgeWidth: width, visibleFrame: area)
                    let layout = DogLayout(scale: 0.5, orientation: orientation,
                                           counterInside: false, badgeWidth: width)
                    XCTAssertEqual(placement.frame.minX + layout.baselineAnchor.x, anchor.x, accuracy: 0.00001)
                    XCTAssertEqual(placement.frame.minY + layout.baselineAnchor.y, anchor.y, accuracy: 0.00001)
                    XCTAssertEqual(layout.petFrame.size, NSSize(width: 74, height: 130))
                }
            }
        }
    }
}
