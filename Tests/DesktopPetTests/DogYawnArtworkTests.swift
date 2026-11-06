import AppKit
import XCTest
@testable import DesktopPet

final class DogYawnArtworkTests: XCTestCase, @unchecked Sendable {
    func testWakingEyesStayOneOpaqueShapeAndKeepBothEndpoints() async throws {
        try await MainActor.run {
            let centers = [CGPoint(x: 200 * 260.0 / 749, y: 70 * 260.0 / 749 + 3.8),
                           CGPoint(x: 398 * 260.0 / 749, y: 50 * 260.0 / 749 + 3.8)]
            for amount in [0.001, 0.1, 0.25, 0.5, 0.75, 0.9, 0.999] {
                let pose = PetPose(sleep: amount, sleepSettle: 0.4)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: 1040, pixelsHigh: 592, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                graphics.cgContext.scaleBy(x: 4, y: 4)
                DogRenderer.drawFace(in: graphics.cgContext, pose: pose, blink: 0, petting: 0)
                NSGraphicsContext.restoreGraphicsState()
                for (index, center) in centers.enumerated() {
                    let shape = try XCTUnwrap(DogYawnArtwork.sleepTransitionEye(index: index, center: center,
                        sleep: amount, blink: 0, settle: pose.sleepSettle))
                    var shift = CGAffineTransform(translationX: 0, y: -pose.sleepSettle * 1.1)
                    let placed = try XCTUnwrap(shape.copy(using: &shift))
                    let box = placed.boundingBoxOfPath.insetBy(dx: -1, dy: -1)
                    var opaqueInterior = 0, translucentInterior = 0, ghostPixels = 0
                    for y in Int(floor(box.minY * 4))...Int(ceil(box.maxY * 4)) {
                        for x in Int(floor(box.minX * 4))...Int(ceil(box.maxX * 4)) {
                            let p = CGPoint(x: (Double(x)+0.5)/4, y: (Double(y)+0.5)/4)
                            let near = [p, CGPoint(x:p.x-0.35,y:p.y), CGPoint(x:p.x+0.35,y:p.y),
                                CGPoint(x:p.x,y:p.y-0.35), CGPoint(x:p.x,y:p.y+0.35)]
                            let coverage = near.map { placed.contains($0) }
                            let alpha = bitmap.colorAt(x: x, y: bitmap.pixelsHigh-1-y)!.alphaComponent
                            if coverage.allSatisfy({ $0 }) { opaqueInterior += 1; if alpha < 0.98 { translucentInterior += 1 } }
                            if coverage.allSatisfy({ !$0 }) && alpha > 0.02 { ghostPixels += 1 }
                        }
                    }
                    XCTAssertGreaterThan(opaqueInterior, 10)
                    XCTAssertEqual(translucentInterior, 0, "Eye must open as solid ink, not fade out at \(amount)")
                    XCTAssertEqual(ghostPixels, 0, "A second eye escaped the moving contour")
                }
            }
            for (index, center) in centers.enumerated() {
                let sleep = try XCTUnwrap(DogYawnArtwork.sleepTransitionEye(index: index, center: center, sleep: 1, blink: 0, settle: 0))
                XCTAssertEqual(sleep, DogYawnArtwork.sleepEyeOutlines![index])
                let open = try XCTUnwrap(DogYawnArtwork.sleepTransitionEye(index: index, center: center, sleep: 0, blink: 0, settle: 0))
                XCTAssertEqual(open, DogRenderer.eyeOutline(at: center, closed: 0).cgPath)
            }
            if let directory = ProcessInfo.processInfo.environment["DESKTOP_PET_WAKE_PREVIEWS"] {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                var motion = PetMotion(now: 0); motion.dogYawnEnabled = true
                motion.sleep(now: 0); motion.wake(now: 5)
                for time in [0.0, 0.2, 0.35, 0.5, 0.65, 0.8] {
                    try DogRenderer.renderPNG(pose: motion.pose(now: 5+time), to: url.appendingPathComponent("wake-\(time).png"),
                        background: NSColor(calibratedWhite: 0.12, alpha: 1))
                }
            }
        }
    }

    func testFinalYawnLidsKeepTheirSizeAndPositionThroughSleepHandoff() async throws {
        try await MainActor.run {
            // Independently measured final resource contours, in canonical y-up points.
            let recorded = [CGRect(x: 59.71875, y: 23.096875, width: 17.0625, height: 6.90625),
                            CGRect(x: 128.984375, y: 17.20625, width: 17.265625, height: 7.71875)]
            let anchor = CGPoint(x: 305 * 260.0 / 749, y: DogRenderer.baselineY)
            let finalHead = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                .scaledBy(x: 1, y: 366.0 / 370).translatedBy(x: -anchor.x, y: -anchor.y)
            let outlines = try XCTUnwrap(DogYawnArtwork.sleepEyeOutlines)
            XCTAssertEqual(outlines.count, 2)
            for (index, path) in outlines.enumerated() {
                let actual = path.boundingBoxOfPath.applying(finalHead)
                XCTAssertEqual(actual.minX, recorded[index].minX, accuracy: 1e-8)
                XCTAssertEqual(actual.minY, recorded[index].minY, accuracy: 1e-8)
                XCTAssertEqual(actual.width, recorded[index].width, accuracy: 1e-8)
                XCTAssertEqual(actual.height, recorded[index].height, accuracy: 1e-8)
            }
            for scale in [0.36, 0.62, 0.75] { for settle in [0.0, 1.0] {
                let size = NSSize(width: 260 * scale, height: 148 * scale)
                let normal = PetPose(breath: 0.5, sleep: 1, sleepSettle: settle)
                let regularHead = DogRenderer.headTransform(normal)
                for weight in [1.0, 0.75, 0.5, 0.25, 0.0] {
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                        pixelsWide: Int(ceil(size.width * 4)), pixelsHigh: Int(ceil(size.height * 4)),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                    graphics.cgContext.scaleBy(x: 4, y: 4)
                    DogYawnArtwork.drawBlended(in: graphics.cgContext, size: size, time: DogYawnArtwork.duration,
                        tailSize: .small, weight: weight, normalPose: normal, normalAngle: 0,
                        normalBend: 0, blink: 0, petting: 0)
                    NSGraphicsContext.restoreGraphicsState()
                    func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * weight }
                    let head = CGAffineTransform(a: mix(regularHead.a, finalHead.a), b: 0, c: 0,
                        d: mix(regularHead.d, finalHead.d), tx: mix(regularHead.tx, finalHead.tx),
                        ty: mix(regularHead.ty, finalHead.ty))
                    let placement = CGAffineTransform(translationX: 0, y: 1).scaledBy(x: scale, y: scale)
                    for path in outlines {
                        let box = path.boundingBoxOfPath.applying(head).applying(placement)
                        var ink = CGRect.null
                        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                            let point = CGPoint(x: (Double(x) + 0.5) / 4,
                                y: (Double(bitmap.pixelsHigh - y) - 0.5) / 4)
                            guard box.insetBy(dx: -1, dy: -1).contains(point),
                                  let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                                  color.alphaComponent > 0.9, color.redComponent < 0.3 else { continue }
                            ink = ink.union(CGRect(x: point.x - 0.125, y: point.y - 0.125, width: 0.25, height: 0.25))
                        }}
                        XCTAssertFalse(ink.isNull)
                        XCTAssertEqual(ink.width, box.width, accuracy: 0.75, "Sleep handoff shrank the lid at weight \(weight)")
                        XCTAssertEqual(ink.height, box.height, accuracy: 0.75)
                        XCTAssertEqual(ink.midX, box.midX, accuracy: 0.5)
                        XCTAssertEqual(ink.midY, box.midY, accuracy: 0.5)
                    }
                }
            }}
        }
    }

    func testResourceKeepsEveryRecordedPresentationTimeAndLastFrameHold() async {
        await MainActor.run {
            XCTAssertTrue(DogYawnArtwork.available)
            XCTAssertEqual(DogYawnArtwork.frameCount, 97)
            XCTAssertEqual(DogYawnArtwork.duration, 4.062548752834467, accuracy: 1e-12)
            for index in 0..<97 {
                let time = Double(index) / 24
                XCTAssertEqual(DogYawnArtwork.frameIndex(at: time), index)
                XCTAssertEqual(DogYawnArtwork.frameIndex(at: time + 0.02), index)
                if index > 0 {
                    XCTAssertEqual(DogYawnArtwork.frameIndex(at: time - 0.000001), index - 1)
                }
            }
            XCTAssertEqual(DogYawnArtwork.frameIndex(at: 4.05), 96)
            XCTAssertEqual(DogYawnArtwork.frameIndex(at: 100), 96)
            XCTAssertEqual(DogYawnArtwork.frameIndex(at: -1), 0)
            XCTAssertEqual(DogYawnArtwork.frameIndex(at: .nan), 0)
        }
    }

    func testTailMatchesIndependentReferenceSamples() async {
        await MainActor.run {
            // Reference head transforms, converted to native y-up.
            let samples: [(Double, Double, Double, Double)] = [
                (0.4, -0.03512683142937234, 0.9945832750304672, 0),
                (1.3, -0.1715046369687948, 0.9854226334133491, 0),
                (2, -0.02702736449967358, 0.9957181475680419, 0),
                (3.2125, -0.05499999999999996, 1, 0.08775825618903717),
                (3.6375, 0.054999999999999924, 1, -0.08775825618903722)
            ]
            for (time, angle, scale, bend) in samples {
                let pose = DogYawnArtwork.tailPose(at: time)
                XCTAssertEqual(pose.angle, angle, accuracy: 1e-12)
                XCTAssertEqual(pose.scale, scale, accuracy: 1e-12)
                XCTAssertEqual(pose.bend, bend, accuracy: 1e-12)
            }
        }
    }

    func testTailIsExactlyStillBetweenGesturesAndJoinsWithZeroSpeed() async {
        await MainActor.run {
            let rest = DogYawnArtwork.TailPose(angle: 0, scale: 1, bend: 0)
            for range in [0.0...0.25, 2.25...3.0, 3.85...DogYawnArtwork.duration] {
                for time in stride(from: range.lowerBound, through: range.upperBound, by: 0.001) {
                    XCTAssertEqual(DogYawnArtwork.tailPose(at: time), rest)
                }
            }
            let step = 1e-6
            for time in [0.25, 2.25, 3.0, 3.85] {
                let before = DogYawnArtwork.tailPose(at: time - step)
                let after = DogYawnArtwork.tailPose(at: time + step)
                XCTAssertEqual((after.angle - before.angle) / (2 * step), 0, accuracy: 0.0001)
                XCTAssertEqual((after.bend - before.bend) / (2 * step), 0, accuracy: 0.0001)
            }
        }
    }

    func testHeadBoundsPreserveRecordedShapeAndConstantInkWidth() async {
        await MainActor.run {
            // Reference measurements for frames 0, 12, 31, 48 and 96.
            let measurements: [(Double, Double, Double, Double)] = [
                (0, 326, 870, 547), (0.5, 309, 854, 549),
                (31.0 / 24, 284, 839, 550.5), (2, 299, 859, 551.5), (4, 330, 870, 547)
            ]
            let anchor = CGPoint(x: 305 * 260.0 / 749, y: DogRenderer.baselineY)
            let clip = CGRect(x: 0, y: DogRenderer.baselineY, width: 260, height: 148 - DogRenderer.baselineY)
            for (time, top, width, center) in measurements {
                var transform = CGAffineTransform(translationX: anchor.x + (center - 547) * 260 / 1280,
                    y: anchor.y).scaledBy(x: width / 870, y: (696 - top) / 370)
                    .translatedBy(x: -anchor.x, y: -anchor.y)
                let head = DogRenderer.headOutline.cgPath.copy(using: &transform)!
                let ink = head.copy(strokingWithWidth: 3.6, lineCap: .round, lineJoin: .round, miterLimit: 10)
                let expected = ink.boundingBoxOfPath.intersection(clip)
                for scale in [0.36, 0.62, 0.75, 1.0] {
                    let size = NSSize(width: 260 * scale + 40, height: 148 * scale)
                    let bounds = DogYawnArtwork.headBounds(size: size, time: time)
                    XCTAssertEqual(bounds.minX, expected.minX * scale + 20, accuracy: 1e-8)
                    XCTAssertEqual(bounds.minY, expected.minY * scale + 1, accuracy: 1e-8)
                    XCTAssertEqual(bounds.width, expected.width * scale, accuracy: 1e-8)
                    XCTAssertEqual(bounds.height, expected.height * scale, accuracy: 1e-8)
                }
            }
        }
    }

    func testBothTailSizesAndIntermediateFramesMatchRenderedHitRegions() async throws {
        try await MainActor.run {
            for scale in [0.5, 0.75] { for tailSize in DogTailSize.allCases {
                for time in [0.0, 0.4, 1.3, 2.0, 3.2125, 3.6375, 4.05] {
                    let size = NSSize(width: 260 * scale + 20, height: 148 * scale)
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                        pixelsWide: Int(ceil(size.width * 2)), pixelsHigh: Int(ceil(size.height * 2)),
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                    graphics.cgContext.scaleBy(x: 2, y: 2)
                    DogYawnArtwork.draw(in: graphics.cgContext, size: size, time: time, tailSize: tailSize)
                    var mismatches = 0, opaque = 0
                    for y in stride(from: 2, to: bitmap.pixelsHigh - 2, by: 4) {
                        for x in stride(from: 2, to: bitmap.pixelsWide - 2, by: 4) {
                            let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                            guard alpha < 0.01 || alpha > 0.99 else { continue }
                            let point = CGPoint(x: (Double(x) + 0.5) / 2,
                                y: (Double(bitmap.pixelsHigh - y) - 0.5) / 2)
                            let hit = DogYawnArtwork.contains(point, size: size, time: time, tailSize: tailSize)
                            if alpha > 0.99 { opaque += 1 }
                            if hit != (alpha > 0.99) { mismatches += 1 }
                        }
                    }
                    XCTAssertGreaterThan(opaque, 100)
                    XCTAssertLessThanOrEqual(mismatches, 2, "scale \(scale), tail \(tailSize), time \(time)")
                }
            }}
        }
    }

    func testBaselineExclusionClippingAndInvalidSizesStayClickThrough() async {
        await MainActor.run {
            let edge = NSPoint(x: DogRenderer.baselineRange.lowerBound + 1, y: DogRenderer.baselineY + 1)
            for time in [0.0, 1.5, 3.5, 4.05] {
                XCTAssertTrue(DogYawnArtwork.contains(edge, size: DogRenderer.canvas, time: time))
                XCTAssertFalse(DogYawnArtwork.contains(edge, size: DogRenderer.canvas,
                    time: time, includesBaseline: false))
                XCTAssertFalse(DogYawnArtwork.contains(NSPoint(x: 100, y: 1), size: DogRenderer.canvas, time: time))
                XCTAssertFalse(DogYawnArtwork.contains(NSPoint(x: 100, y: 140), size: DogRenderer.canvas, time: time))
            }
            for size in [NSSize.zero, NSSize(width: -1, height: 10),
                         NSSize(width: CGFloat.nan, height: 148), NSSize(width: 260, height: CGFloat.infinity)] {
                XCTAssertFalse(DogYawnArtwork.contains(.zero, size: size, time: 0))
                XCTAssertTrue(DogYawnArtwork.headBounds(size: size, time: 0).isNull)
            }
        }
    }

    func testHandoffDrawsOneOpaqueSilhouetteMatchingItsHitGeometry() async throws {
        try await MainActor.run {
            let size = DogRenderer.canvas
            let normal = PetPose(breath: 1, squash: 0.15)
            for weight in [0.2, 0.5, 0.8] {
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                    pixelsWide: 520, pixelsHigh: 296, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphics
                graphics.cgContext.scaleBy(x: 2, y: 2)
                DogYawnArtwork.drawBlended(in: graphics.cgContext, size: size, time: 1.3,
                    tailSize: .original, weight: weight, normalPose: normal, normalAngle: 0.2,
                    normalBend: 0.3, blink: 0, petting: 0)
                NSGraphicsContext.restoreGraphicsState()
                @MainActor func hits(_ point: CGPoint) -> Bool {
                    DogYawnArtwork.containsBlended(point, size: size, time: 1.3, tailSize: .original,
                        weight: weight, normalPose: normal, normalAngle: 0.2, normalBend: 0.3)
                }
                var strayInk = 0
                for y in stride(from: 4, to: 292, by: 6) { for x in stride(from: 4, to: 516, by: 6) {
                    let alpha = bitmap.colorAt(x: x, y: y)!.alphaComponent
                    guard alpha > 0.03 else { continue }
                    let point = CGPoint(x: (Double(x) + 0.5) / 2, y: (296 - Double(y) - 0.5) / 2)
                    if hits(point) { continue }
                    // One raster pixel around the mathematical outline is antialiasing.
                    let touchesEdge = [-0.5, 0, 0.5].contains { dx in
                        [-0.5, 0, 0.5].contains { dy in hits(CGPoint(x: point.x + dx, y: point.y + dy)) }
                    }
                    if !touchesEdge { strayInk += 1 }
                }}
                XCTAssertEqual(strayInk, 0, "A second faded outline escaped the single blended silhouette")
                XCTAssertEqual(bitmap.colorAt(x: 200, y: 216)!.alphaComponent, 1,
                    "The white head remains opaque during the face handoff")
            }
            let expectedStart = DogRenderer.headBounds(size: size, pose: normal)
            let expectedEnd = DogYawnArtwork.headBounds(size: size, time: 1.3)
            for (weight, expected) in [(1e-8, expectedStart), (1 - 1e-8, expectedEnd)] {
                let actual = DogYawnArtwork.headBoundsBlended(size: size, time: 1.3, weight: weight, normalPose: normal)
                XCTAssertEqual(actual.minX, expected.minX, accuracy: 1e-5)
                XCTAssertEqual(actual.maxY, expected.maxY, accuracy: 1e-5)
            }
        }
    }
}
