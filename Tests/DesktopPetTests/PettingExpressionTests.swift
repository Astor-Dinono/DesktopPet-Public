import AppKit
import XCTest
@testable import DesktopPet

final class PettingExpressionTests: XCTestCase, @unchecked Sendable {
    func testPettingDuringBlinkDoesNotFoldAnEyeCorner() async {
        await MainActor.run {
            func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
                (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
            }
            for left in [true, false] { for closed in [0.0, 0.5, 0.95, 1.0] {
                for amount in [0.001, 0.02, 0.04, 0.1, 0.5, 0.9, 0.999] {
                    let path = DogSqueezeEyes.transitionOutline(at: .zero, left: left, normalClosed: closed, amount: amount)
                    var points: [CGPoint] = []
                    path.applyWithBlock { e in
                        if e.pointee.type == .moveToPoint || e.pointee.type == .addLineToPoint {
                            points.append(e.pointee.points[0])
                        }
                    }
                    var intersections = 0
                    for i in 0..<(points.count-2) { for j in (i+2)..<points.count {
                        if i == 0 && j == points.count-1 { continue }
                        let a=points[i], b=points[(i+1)%points.count], c=points[j], d=points[(j+1)%points.count]
                        if cross(a,b,c)*cross(a,b,d) < -1e-15 && cross(c,d,a)*cross(c,d,b) < -1e-15 {
                            intersections += 1
                        }
                    }}
                    XCTAssertEqual(intersections, 0, "left=\(left), blink=\(closed), pet=\(amount)")
                }
            }}
        }
    }

    func testPettingTransitionDrawsSolidInkInsteadOfTwoFadingEyes() async throws {
        try await MainActor.run {
            let center = CGPoint(x: 20, y: 20)
            for left in [true, false] { for amount in [0.1, 0.25, 0.5, 0.75, 0.9] {
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 160,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                graphics.cgContext.scaleBy(x: 4, y: 4)
                DogSqueezeEyes.draw(at: center, left: left, normalClosed: 0, amount: amount)
                NSGraphicsContext.restoreGraphicsState()
                let outline = DogSqueezeEyes.transitionOutline(at: center, left: left, normalClosed: 0, amount: amount)
                var interior = 0, faded = 0, ghost = 0
                for y in 40..<120 { for x in 40..<120 {
                    let p = CGPoint(x: (Double(x)+0.5)/4, y: (Double(y)+0.5)/4)
                    let near = [p, CGPoint(x:p.x-0.35,y:p.y), CGPoint(x:p.x+0.35,y:p.y),
                        CGPoint(x:p.x,y:p.y-0.35), CGPoint(x:p.x,y:p.y+0.35)].map { outline.contains($0) }
                    let alpha = bitmap.colorAt(x: x, y: 159-y)!.alphaComponent
                    if near.allSatisfy({ $0 }) { interior += 1; if alpha < 0.98 { faded += 1 } }
                    if near.allSatisfy({ !$0 }) && alpha > 0.02 { ghost += 1 }
                }}
                XCTAssertGreaterThan(interior, 10)
                XCTAssertEqual(faded, 0); XCTAssertEqual(ghost, 0)
            }}
            for left in [true, false] {
                XCTAssertEqual(DogSqueezeEyes.transitionOutline(at: center, left: left, normalClosed: 0, amount: 0),
                    DogRenderer.eyeOutline(at: center, closed: 0).cgPath)
                let expected = DogSqueezeEyes.pose(at: center, left: left, normalClosed: 0, amount: 1).squeeze.cgPath
                    .copy(strokingWithWidth: 1.7, lineCap: .round, lineJoin: .round, miterLimit: 10)
                XCTAssertEqual(DogSqueezeEyes.transitionOutline(at: center, left: left, normalClosed: 0, amount: 1), expected)
            }
            if let directory = ProcessInfo.processInfo.environment["DESKTOP_PET_WAKE_PREVIEWS"] {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    try DogRenderer.renderPNG(petting: amount, to: url.appendingPathComponent("pet-\(amount).png"),
                        background: NSColor(calibratedWhite: 0.12, alpha: 1))
                }
            }
        }
    }

    func testRetouchKeepsPositionAndVelocityAndEventuallyClears() {
        for time in [0.08, 0.3, 0.48, 0.65, 0.82] {
            var motion = DogPetExpression()
            motion.touch(now: 0)
            let step = 0.000001
            let value = motion.value(now: time)
            let beforeVelocity = (value - motion.value(now: time - step)) / step
            motion.touch(now: time)
            XCTAssertEqual(motion.value(now: time), value, accuracy: 1e-12)
            let afterVelocity = (motion.value(now: time + step) - value) / step
            XCTAssertEqual(beforeVelocity, afterVelocity, accuracy: 0.003)
            for tick in 0...1000 {
                let current = motion.value(now: time + Double(tick) / 1000)
                XCTAssertTrue(current.isFinite && (0...1).contains(current))
            }
            XCTAssertEqual(motion.value(now: time + 1), 0)
            XCTAssertFalse(motion.isMoving(now: time + 1))
        }
    }

    func testPleasedExpressionIsBriefBoundedAndCanBeCancelled() {
        var motion = DogPetExpression()
        XCTAssertEqual(motion.value(now: 0), 0)
        motion.touch(now: 0)
        XCTAssertEqual(motion.value(now: 0), 0)
        XCTAssertGreaterThan(motion.value(now: 0.18), 0.97)
        XCTAssertGreaterThan(motion.value(now: 0.35), 0.999)
        XCTAssertEqual(motion.value(now: 0.85), 0)
        for tick in 0..<1000 { motion.touch(now: Double(tick) * 0.12) }
        XCTAssertGreaterThan(motion.value(now: 119.88), 0.99)
        motion.cancel()
        XCTAssertEqual(motion.value(now: 120), 0)
        XCTAssertFalse(motion.isMoving(now: 120))
        motion.touch(now: .nan)
        XCTAssertEqual(motion.value(now: 120), 0)
    }

    func testSelectedExpressionMatchesDraftAndCannotHaveBlankEyeHandoff() async {
        await MainActor.run {
            let center = NSPoint(x: 50, y: 50)
            for value in stride(from: 0.0, through: 1.0, by: 0.01) {
                let eye = DogSqueezeEyes.pose(at: center, left: true, normalClosed: 0, amount: value)
                XCTAssertEqual(eye.normalAlpha + eye.squeezeAlpha, 1, accuracy: 1e-12)
                XCTAssertGreaterThanOrEqual(max(eye.normalAlpha, eye.squeezeAlpha), 0.5)
            }
            for left in [true, false] {
                let eye = DogSqueezeEyes.pose(at: center, left: left, normalClosed: 0, amount: 1)
                XCTAssertEqual(eye.squeeze.elementCount, 3)
                XCTAssertEqual(eye.strokeWidth, 1.7)
                XCTAssertEqual(eye.normalAlpha, 0)
                XCTAssertEqual(eye.squeezeAlpha, 1)
                var points = [NSPoint](repeating: .zero, count: 3)
                _ = eye.squeeze.element(at: 1, associatedPoints: &points)
                XCTAssertEqual(points[0].x, 50 + (left ? 3.7 : -3.7), accuracy: 1e-12)
                XCTAssertEqual(points[0].y, 50)
            }
        }
    }

    func testZeroAmountLeavesOriginalContourAndSleepTakesPriority() async {
        await MainActor.run {
            let center = NSPoint(x: 71, y: 62)
            for closed in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let original = DogRenderer.eyeOutline(at: center, closed: closed)
                let pose = DogSqueezeEyes.pose(at: center, left: false, normalClosed: closed, amount: 0)
                XCTAssertEqual(pose.normalAlpha, 1)
                XCTAssertEqual(pose.squeezeAlpha, 0)
                XCTAssertEqual(pose.normal.elementCount, original.elementCount)
                for index in 0..<original.elementCount {
                    var expected = [NSPoint](repeating: .zero, count: 3)
                    var actual = expected
                    let type = original.element(at: index, associatedPoints: &expected)
                    XCTAssertEqual(pose.normal.element(at: index, associatedPoints: &actual), type)
                    let count = type == .curveTo ? 3 : type == .closePath ? 0 : 1
                    for point in 0..<count { XCTAssertEqual(actual[point], expected[point]) }
                }
            }
            XCTAssertEqual(DogSqueezeEyes.effectiveAmount(petting: 1, sleep: 1), 0)
            XCTAssertEqual(DogSqueezeEyes.effectiveAmount(petting: 1, sleep: 0.5), 0.5)
            XCTAssertEqual(DogSqueezeEyes.effectiveAmount(petting: .nan, sleep: 0), 0)
            XCTAssertEqual(DogSqueezeEyes.effectiveAmount(petting: 0.2, sleep: 0, reducedMotion: true), 1)
            XCTAssertEqual(DogSqueezeEyes.effectiveAmount(petting: 1, sleep: 1, reducedMotion: true), 0)
        }
    }

    func testPettingHitCanExcludeExtendedBaselineWithoutChangingDefault() async {
        await MainActor.run {
            let edge = NSPoint(x: DogRenderer.baselineRange.lowerBound + 1, y: DogRenderer.baselineY + 1)
            XCTAssertTrue(DogRenderer.contains(edge, size: DogRenderer.canvas))
            XCTAssertFalse(DogRenderer.contains(edge, size: DogRenderer.canvas, includesBaseline: false))
            let head = NSPoint(x: 100, y: 40)
            XCTAssertTrue(DogRenderer.contains(head, size: DogRenderer.canvas, includesBaseline: false))
            XCTAssertTrue(DogRenderer.contains(head, size: DogRenderer.canvas))
        }
    }
}
