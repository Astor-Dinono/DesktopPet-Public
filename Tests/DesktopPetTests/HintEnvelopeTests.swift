import AppKit
import XCTest
@testable import DesktopPet

final class HintEnvelopeTests: XCTestCase, @unchecked Sendable {
    func testEnvelopeExcludesTransparentHeadroomAndUsesDrawingCoordinates() async {
        await MainActor.run {
            let full = DogRenderer.interactionHintBounds(size: DogRenderer.canvas)
            XCTAssertGreaterThan(full.height, 75)
            XCTAssertLessThan(full.maxY, 110, "The hint should not attach to the 148-point transparent canvas")
            XCTAssertGreaterThan(full.minX, 0, "Trimmed baseline must no longer reserve the old left margin")
            XCTAssertGreaterThanOrEqual(full.maxX, DogRenderer.baselineRange.upperBound + 1.25)
            XCTAssertLessThanOrEqual(full.minY, 1 + DogRenderer.baselineY - 1.25)

            // The renderer's +1 point translation does not scale with the dog.
            for scale in [0.36, 0.5, 0.62, 0.75, 1.0] {
                let scaledSize = NSSize(width: 260 * scale, height: 148 * scale)
                let actual = DogRenderer.interactionHintBounds(size: scaledSize)
                XCTAssertEqual(actual.width, full.width * scale, accuracy: 0.000001)
                XCTAssertEqual(actual.height, full.height * scale, accuracy: 0.000001)
                XCTAssertEqual(actual.minX, full.minX * scale, accuracy: 0.000001)
                XCTAssertEqual(actual.minY, (full.minY - 1) * scale + 1, accuracy: 0.000001)
                let wide = DogRenderer.interactionHintBounds(size: NSSize(width: scaledSize.width + 40, height: scaledSize.height))
                XCTAssertEqual(wide.minX, actual.minX + 20, accuracy: 0.000001)
                XCTAssertEqual(wide.minY, actual.minY, accuracy: 0.000001)
                XCTAssertEqual(wide.size, actual.size)
            }
        }
    }

    func testHeadStrokeFitsThroughBreathBounceAndRestExtremes() async {
        await MainActor.run {
            for scale in [0.36, 0.62, 0.75] {
                let size = NSSize(width: 260 * scale, height: 148 * scale)
                let envelope = DogRenderer.interactionHintBounds(size: size)
                for breath in [-1.35, 0, 1.35] { for squash in [-0.20, 0, 0.20] {
                    for settle in [0.0, 1] { for stretch in [0.0, 0.014, 0.03] {
                        let head = DogRenderer.headBounds(size: size,
                            pose: PetPose(breath: breath, sleepSettle: settle, wakeStretch: stretch, squash: squash))
                        XCTAssertTrue(envelope.contains(head), "Head escaped at \(breath), \(squash), \(settle), \(stretch)")
                    }}
                }}
            }
        }
    }

    func testRealTailGeometryFitsForBothSizesAndIntermediateRootRotations() async {
        await MainActor.run {
            let size = DogRenderer.canvas
            let envelope = DogRenderer.interactionHintBounds(size: size)
            let root = CGPoint(x: 574 * 260.0 / 749, y: (268 - 280) * 260.0 / 749 + DogRenderer.baselineY)
            let clip = CGRect(x: 0, y: DogRenderer.baselineY, width: size.width,
                              height: size.height - DogRenderer.baselineY)
            for tailSize in DogTailSize.allCases {
                for bend in stride(from: -0.45, through: 0.45, by: 0.03) {
                    let ink = DogRenderer.tailPath(bend: bend, tailSize: tailSize).cgPath
                        .copy(strokingWithWidth: 3.6, lineCap: .round, lineJoin: .round, miterLimit: 10)
                    for angle in stride(from: -0.26, through: 0.26, by: 0.013) {
                        var transform = CGAffineTransform(translationX: root.x, y: root.y)
                            .rotated(by: angle).translatedBy(x: -root.x, y: -root.y)
                        let tail = ink.copy(using: &transform)!.boundingBoxOfPath.intersection(clip).offsetBy(dx: 0, dy: 1)
                        XCTAssertTrue(envelope.contains(tail), "Tail escaped at \(tailSize), \(angle), \(bend)")
                    }
                }
            }
        }
    }

    func testRepeatedRealInteractionsRemainInsideStableEnvelope() async {
        await MainActor.run {
            var body = PetMotion(now: 0, autoNap: .off)
            var tail = DogMotion()
            let envelope = DogRenderer.interactionHintBounds(size: DogRenderer.canvas)
            for tick in 0...1200 {
                let time = Double(tick) / 60
                if tick % 37 == 0 { body.click(now: time); tail.wag(now: time) }
                if tick % 113 == 0 { body.sleep(now: time); tail.settle(now: time) }
                if tick % 127 == 0 { body.wake(now: time) }
                let pose = body.pose(now: time)
                XCTAssertTrue(envelope.contains(DogRenderer.headBounds(size: DogRenderer.canvas, pose: pose)))
                let wag = tail.pose(now: time)
                XCTAssertLessThanOrEqual(abs(wag.bend), 0.45)
                XCTAssertLessThanOrEqual(abs(wag.angle), 0.26)
                XCTAssertEqual(DogRenderer.interactionHintBounds(size: DogRenderer.canvas), envelope)
            }
        }
    }

    func testInvalidDrawingSizesHaveNoHintObstacle() async {
        await MainActor.run {
            for size in [NSSize.zero, NSSize(width: -1, height: 10),
                         NSSize(width: CGFloat.nan, height: 148), NSSize(width: 260, height: CGFloat.infinity)] {
                XCTAssertTrue(DogRenderer.interactionHintBounds(size: size).isNull)
            }
        }
    }
}
