import AppKit

enum DogSize: Int, CaseIterable {
    // The raw values identify menu choices; tiny keeps the old fitted topbar
    // scale exactly rather than rounding it to an integer percentage.
    case tiny = 36, small = 50, medium = 62, large = 75

    var title: String {
        switch self {
        case .tiny: "小小号"
        case .small: "小号"
        case .medium: "中号"
        case .large: "大号"
        }
    }

    @MainActor var scale: Double {
        self == .tiny ? DogTopbarRenderer.tinyScale : Double(rawValue) / 100
    }

    @MainActor static func matching(_ stored: Double) -> Self? {
        guard stored.isFinite else { return nil }
        return allCases.first { abs($0.scale - stored) <= 1e-6 }
    }
}

enum DogTailSize: Int, CaseIterable {
    case small = 80, original = 100
    static let preferenceKey = "dog.tailSize"
    init(storedValue: Int?) { self = storedValue.flatMap(Self.init(rawValue:)) ?? .small }
    var scale: Double { Double(rawValue) / 100 }
    var title: String { self == .small ? "小一圈" : "原来大小" }
}

/// Vector dog artwork with independent head and tail.
/// Coordinates are y-up; the bottom edge stays fixed through breathing and landing.
@MainActor
enum DogRenderer {
    static let canvas = NSSize(width: 260, height: 148)
    static let baselineY = 3.8
    static let defaultScale = 0.62
    private static let ink = NSColor.black
    private static let sourceScale = 260.0 / 749.0

    private static func p(_ x: Double, _ y: Double) -> NSPoint {
        NSPoint(x: x * sourceScale, y: (268 - y) * sourceScale + baselineY)
    }

    private static func headPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: p(70, 284))
        path.curve(to: p(88, 180), controlPoint1: p(57, 254), controlPoint2: p(65, 211))
        path.curve(to: p(64, 150), controlPoint1: p(68, 174), controlPoint2: p(62, 163))
        path.curve(to: p(81, 112), controlPoint1: p(58, 132), controlPoint2: p(62, 121))
        path.curve(to: p(115, 99), controlPoint1: p(91, 103), controlPoint2: p(102, 102))
        path.curve(to: p(170, 61), controlPoint1: p(135, 87), controlPoint2: p(155, 63))
        path.curve(to: p(197, 58), controlPoint1: p(181, 53), controlPoint2: p(185, 53))
        path.curve(to: p(228, 77), controlPoint1: p(208, 60), controlPoint2: p(218, 72))
        path.curve(to: p(330, 61), controlPoint1: p(260, 64), controlPoint2: p(297, 60))
        path.curve(to: p(433, 93), controlPoint1: p(374, 61), controlPoint2: p(410, 80))
        path.curve(to: p(484, 84), controlPoint1: p(451, 81), controlPoint2: p(472, 78))
        path.curve(to: p(516, 108), controlPoint1: p(500, 87), controlPoint2: p(505, 98))
        path.curve(to: p(566, 141), controlPoint1: p(534, 124), controlPoint2: p(555, 130))
        path.curve(to: p(578, 163), controlPoint1: p(575, 147), controlPoint2: p(578, 152))
        path.curve(to: p(573, 195), controlPoint1: p(578, 175), controlPoint2: p(578, 184))
        path.curve(to: p(557, 219), controlPoint1: p(568, 213), controlPoint2: p(563, 218))
        path.curve(to: p(532, 210), controlPoint1: p(545, 225), controlPoint2: p(536, 219))
        path.curve(to: p(543, 267), controlPoint1: p(536, 231), controlPoint2: p(541, 251))
        path.line(to: p(543, 284))
        path.close()
        return path
    }

    static func tailPath(bend: Double = 0, tailSize: DogTailSize = .small) -> NSBezierPath {
        let root = p(574, 280)
        func q(_ x: Double, _ y: Double) -> NSPoint {
            let point = p(x, y)
            let along = min(1, max(0, (point.y - root.y) / 45))
            let influence = along * along
            let bent = NSPoint(x: point.x - sin(bend) * 29 * influence,
                               y: point.y - abs(bend) * 2.5 * influence)
            // Scale the deformed silhouette around its fixed root, keeping the ink width.
            return NSPoint(x: root.x + (bent.x - root.x) * tailSize.scale,
                           y: root.y + (bent.y - root.y) * tailSize.scale)
        }
        let path = NSBezierPath()
        path.move(to: q(550, 282))
        path.curve(to: q(628, 199), controlPoint1: q(588, 248), controlPoint2: q(614, 230))
        path.curve(to: q(649, 165), controlPoint1: q(641, 168), controlPoint2: q(640, 161))
        path.curve(to: q(677, 181), controlPoint1: q(659, 158), controlPoint2: q(671, 167))
        path.curve(to: q(668, 259), controlPoint1: q(695, 207), controlPoint2: q(682, 238))
        path.line(to: q(650, 282))
        path.close()
        return path
    }

    static let headOutline = headPath()

    static let earLines: NSBezierPath = {
        let ears = NSBezierPath()
        ears.move(to: p(145, 110))
        ears.curve(to: p(88, 180), controlPoint1: p(139, 145), controlPoint2: p(113, 188))
        ears.move(to: p(478, 136))
        ears.curve(to: p(518, 191), controlPoint1: p(484, 160), controlPoint2: p(499, 180))
        ears.curve(to: p(532, 210), controlPoint1: p(522, 198), controlPoint2: p(525, 205))
        return ears
    }()

    static let mouthOutline: NSBezierPath = {
        let mouth = NSBezierPath()
        mouth.move(to: p(255, 220))
        mouth.curve(to: p(281, 225), controlPoint1: p(252, 242), controlPoint2: p(272, 237))
        mouth.curve(to: p(312, 225), controlPoint1: p(291, 242), controlPoint2: p(307, 246))
        return mouth
    }()

    private static func headTransform(_ pose: PetPose) -> CGAffineTransform {
        let anchorX = p(305, 268).x
        // Slow, visible breathing at the smallest size, anchored to the bottom edge.
        let height = 1 + pose.breath * 0.040 - pose.squash - pose.sleepSettle * 0.025 + pose.wakeStretch
        let width = 1 - pose.breath * 0.012 + pose.squash * 0.48 + pose.sleepSettle * 0.010 - pose.wakeStretch * 0.4
        return CGAffineTransform(translationX: anchorX, y: baselineY)
            .scaledBy(x: width, y: height).translatedBy(x: -anchorX, y: -baselineY)
    }

    private static func tailTransform(_ angle: Double) -> CGAffineTransform {
        let root = p(574, 280)
        return CGAffineTransform(translationX: root.x, y: root.y)
            .rotated(by: angle).translatedBy(x: -root.x, y: -root.y)
    }

    static func contains(_ point: NSPoint, size: NSSize, pose: PetPose = PetPose(),
                         angle: Double = 0, bend: Double = 0, tailSize: DogTailSize = .small,
                         includesBaseline: Bool = true) -> Bool {
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        guard scale > 0 else { return false }
        let local = NSPoint(x: (point.x - (size.width - canvas.width * scale) / 2) / scale,
                            y: (point.y - 1) / scale)
        // Include the visible ink, but not the transparent margins or floating effects.
        if includesBaseline, (0...canvas.width).contains(local.x), abs(local.y - baselineY) <= 1.25 { return true }
        guard local.y >= baselineY else { return false }
        func hits(_ path: NSBezierPath, _ transform: CGAffineTransform) -> Bool {
            let p = local.applying(transform.inverted())
            return path.contains(p) || path.cgPath.copy(strokingWithWidth: 3.6,
                lineCap: .round, lineJoin: .round, miterLimit: 10).contains(p)
        }
        return hits(headOutline, headTransform(pose)) || hits(tailPath(bend: bend, tailSize: tailSize), tailTransform(angle))
    }

    /// Placement-only geometry. Excludes the transparent canvas and sleep letters.
    static func headBounds(size: NSSize, pose: PetPose) -> CGRect {
        var transform = headTransform(pose)
        let head = headOutline.cgPath.copy(strokingWithWidth: 3.6,
            lineCap: .round, lineJoin: .round, miterLimit: 10).copy(using: &transform)!.boundingBoxOfPath
            .intersection(CGRect(x: 0, y: baselineY, width: canvas.width, height: canvas.height - baselineY))
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        return head.applying(CGAffineTransform(translationX: (size.width - canvas.width * scale) / 2, y: 1)
            .scaledBy(x: scale, y: scale))
    }

    /// A stable obstacle for nearby UI, not an interaction region. Construct
    /// the vector envelope once so breathing and wagging cannot jitter a hint.
    /// Sleep letters and independently floating effects are intentionally absent.
    private static let interactionHintEnvelope: CGRect = {
        let clip = CGRect(x: 0, y: baselineY, width: canvas.width, height: canvas.height - baselineY)
        let headInk = headOutline.cgPath.copy(strokingWithWidth: 3.6,
            lineCap: .round, lineJoin: .round, miterLimit: 10)
        // PetMotion breath reaches ±1.35 while asleep; DuangMotion bounds
        // squash at ±0.20. Wake inhale is 0.014; 0.03 also leaves room for an
        // interrupted rest transition. These two poses bound both affine axes.
        var wide = headTransform(PetPose(breath: -1.35, sleepSettle: 1, squash: 0.20))
        var tall = headTransform(PetPose(breath: 1.35, wakeStretch: 0.03, squash: -0.20))
        let head = headInk.copy(using: &wide)!.boundingBoxOfPath
            .union(headInk.copy(using: &tall)!.boundingBoxOfPath).intersection(clip)

        // The largest tail is sufficient for both menu sizes. Bound the bend
        // displacement (nominal ±0.36, conservatively ±0.45), then enclose the
        // resulting path in a circle around its actual pivot. A circle contains
        // every root rotation, including values between sampled tail frames.
        let root = p(574, 280)
        let bentTail = tailPath(tailSize: .original).cgPath.boundingBoxOfPath
            .insetBy(dx: -sin(0.45) * 29, dy: -0.45 * 2.5)
        let radius = [
            hypot(bentTail.minX - root.x, bentTail.minY - root.y),
            hypot(bentTail.minX - root.x, bentTail.maxY - root.y),
            hypot(bentTail.maxX - root.x, bentTail.minY - root.y),
            hypot(bentTail.maxX - root.x, bentTail.maxY - root.y)].max()! + 1.8
        let tail = CGRect(x: root.x - radius, y: root.y - radius,
                          width: radius * 2, height: radius * 2).intersection(clip)
        let baseline = CGRect(x: -1.25, y: baselineY - 1.25,
                              width: canvas.width + 2.5, height: 2.5)
        // One canonical point for edge antialiasing; not the 148-point canvas.
        return head.union(tail).union(baseline).insetBy(dx: -1, dy: -1)
    }()

    /// Uses precisely draw()'s centering, uniform scale, and one-point y offset.
    /// Callers apply the existing orientation/turn or topbar transform afterwards.
    static func interactionHintBounds(size: NSSize) -> NSRect {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .null }
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        return interactionHintEnvelope.applying(CGAffineTransform(
            translationX: (size.width - canvas.width * scale) / 2, y: 1)
            .scaledBy(x: scale, y: scale))
    }

    static func draw(in context: CGContext, size: NSSize, pose: PetPose = PetPose(),
                     angle: Double = 0, bend: Double = 0, blink: Double = 0, tailSize: DogTailSize = .small,
                     petting: Double = 0) {
        context.saveGState()
        defer { context.restoreGState() }
        let scale = min(size.width / canvas.width, size.height / canvas.height)
        context.translateBy(x: (size.width - canvas.width * scale) / 2, y: 1)
        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // The hidden body and rotating tail root are clipped at the stationary edge.
        context.saveGState()
        context.clip(to: NSRect(x: 0, y: baselineY, width: canvas.width, height: canvas.height - baselineY))
        context.saveGState()
        context.concatenate(tailTransform(angle))
        let tail = tailPath(bend: bend, tailSize: tailSize)
        NSColor.white.setFill(); tail.fill()
        stroke(tail, width: 3.6)
        context.restoreGState()

        context.saveGState()
        context.concatenate(headTransform(pose))
        let head = headOutline
        NSColor.white.setFill(); head.fill()
        stroke(head, width: 3.6)

        let ears = Self.earLines
        stroke(ears, width: 3.3)

        context.translateBy(x: 0, y: -pose.sleepSettle * 1.1)
        if pose.affection > 0 {
            for center in [p(164, 228), p(438, 244)] {
                let cheek = NSBezierPath(ovalIn: NSRect(x: center.x - 9.2, y: center.y - 3.3, width: 18.4, height: 6.6))
                NSColor(calibratedRed: 1, green: 0.50, blue: 0.60, alpha: pose.affection * 0.36).setFill()
                cheek.fill()
            }
        }
        // Sleep retains the original eye. Petting briefly hands off to the selected >< lid.
        let closed = 1 - (1 - pose.sleep) * (1 - blink)
        let happy = DogSqueezeEyes.effectiveAmount(petting: petting, sleep: pose.sleep, reducedMotion: pose.reducedMotion)
        if happy > 0 {
            DogSqueezeEyes.draw(at: p(200, 198), left: true, normalClosed: closed, amount: happy)
            DogSqueezeEyes.draw(at: p(398, 218), left: false, normalClosed: closed, amount: happy)
        } else {
            drawEye(at: p(200, 198), closed: closed)
            drawEye(at: p(398, 218), closed: closed)
        }

        let noseCenter = p(285, 206)
        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: noseCenter.x - 6.1, y: noseCenter.y - 3.8, width: 12.2, height: 7.6)).fill()
        let mouth = Self.mouthOutline
        stroke(mouth, width: 3.4)

        if pose.sleepBubble > 0 { drawBubble(pose, in: context) }
        context.restoreGState()
        context.restoreGState()

        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: 0, y: baselineY))
        edge.line(to: NSPoint(x: canvas.width, y: baselineY))
        stroke(edge, width: 2.5)

        context.saveGState()
        context.translateBy(x: -4, y: -70)
        if pose.sleepLetters > 0 { DogEffectsRenderer.drawSleep(pose) }
        context.restoreGState()
    }

    static func drawEye(at center: NSPoint, closed: Double) {
        let eye = eyeOutline(at: center, closed: closed)
        ink.setFill(); eye.fill()
    }

    static func eyeOutline(at center: NSPoint, closed: Double) -> NSBezierPath {
        let halfWidth = 5.4 + closed * 0.9
        let halfHeight = 5.4 * (1 - closed) + closed * 0.65
        let sag = -closed * 1.8
        let top = center.y + halfHeight + sag
        let bottom = center.y - halfHeight + sag
        let k = 0.55228475
        let eye = NSBezierPath()
        eye.move(to: NSPoint(x: center.x - halfWidth, y: center.y))
        eye.curve(to: NSPoint(x: center.x, y: top),
                  controlPoint1: NSPoint(x: center.x - halfWidth, y: center.y + (top - center.y) * k),
                  controlPoint2: NSPoint(x: center.x - halfWidth * k, y: top))
        eye.curve(to: NSPoint(x: center.x + halfWidth, y: center.y),
                  controlPoint1: NSPoint(x: center.x + halfWidth * k, y: top),
                  controlPoint2: NSPoint(x: center.x + halfWidth, y: center.y + (top - center.y) * k))
        eye.curve(to: NSPoint(x: center.x, y: bottom),
                  controlPoint1: NSPoint(x: center.x + halfWidth, y: center.y + (bottom - center.y) * k),
                  controlPoint2: NSPoint(x: center.x + halfWidth * k, y: bottom))
        eye.curve(to: NSPoint(x: center.x - halfWidth, y: center.y),
                  controlPoint1: NSPoint(x: center.x - halfWidth * k, y: bottom),
                  controlPoint2: NSPoint(x: center.x - halfWidth, y: center.y + (bottom - center.y) * k))
        eye.close()
        return eye
    }

    static func drawBubble(_ pose: PetPose, in context: CGContext) {
        let tip = p(301, 208)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: tip.x, y: tip.y)
        let growth = pose.reducedMotion ? 1 : max(0.001, pose.sleepBubble)
        context.scaleBy(x: growth, y: growth)
        let puff = 1 + pose.breath * 0.09
        func b(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x * puff, y: y * puff) }
        let drop = NSBezierPath()
        drop.move(to: .zero)
        drop.curve(to: b(20, -10), controlPoint1: b(6, -3), controlPoint2: b(19, -3))
        drop.curve(to: b(13, -17), controlPoint1: b(21, -14), controlPoint2: b(18, -17))
        drop.curve(to: b(6, -10), controlPoint1: b(7, -17), controlPoint2: b(4, -14))
        drop.curve(to: .zero, controlPoint1: b(6, -6), controlPoint2: b(3, -3))
        drop.close()
        NSColor(calibratedRed: 0.82, green: 0.93, blue: 1, alpha: 0.35 * pose.sleepBubble).setFill()
        drop.fill()
        stroke(drop, color: NSColor(calibratedRed: 0.40, green: 0.62, blue: 0.72, alpha: 0.65 * pose.sleepBubble), width: 0.85)
        let glint = NSBezierPath()
        glint.move(to: b(9, -12))
        glint.curve(to: b(10, -8), controlPoint1: b(8, -10), controlPoint2: b(9, -8))
        stroke(glint, color: .white.withAlphaComponent(0.8 * pose.sleepBubble), width: 1.4)
    }

    private static func stroke(_ path: NSBezierPath, color: NSColor = .black, width: CGFloat) {
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// The app icon uses the same artwork as the pet; it is generated only while packaging.
    static func renderAppIcon(to url: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                                xRadius: 190, yRadius: 190)
        tile.addClip()
        NSGradient(starting: NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.86, alpha: 1),
                   ending: NSColor(calibratedRed: 0.84, green: 0.89, blue: 0.76, alpha: 1))!
            .draw(in: tile, angle: -90)
        context.translateBy(x: 0, y: 370)
        draw(in: context, size: NSSize(width: 1024, height: 1024 * canvas.height / canvas.width),
             pose: PetPose(affection: 0.45), angle: -0.06, bend: 0.05)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    static func renderPNG(angle: Double = 0, bend: Double = 0, pose: PetPose = PetPose(), blink: Double = 0,
                          petting: Double = 0, to url: URL, background: NSColor? = nil) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 780, pixelsHigh: 444,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: 3, y: 3)
        if let background {
            background.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()
        }
        draw(in: graphics.cgContext, size: canvas, pose: pose, angle: angle, bend: bend, blink: blink, petting: petting)
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
