import AppKit

/// Native playback of the bundled yawn artwork. The recorded face and head use
/// their original presentation times; only the deliberately fitted tail is continuous.
@MainActor
enum DogYawnArtwork {
    static var available: Bool { artwork != nil }
    static var duration: Double { artwork?.duration ?? 4.062548752834467 }
    static var frameCount: Int { artwork?.frames.count ?? 0 }

    private static let sourceScale = 260.0 / 749.0
    private static let videoScale = 1280.0 / 749.0
    private static let videoToCanvas = 260.0 / 1280.0
    private static let clip = CGRect(x: 0, y: DogRenderer.baselineY,
        width: DogRenderer.canvas.width, height: DogRenderer.canvas.height - DogRenderer.baselineY)
    private static let black = CGColor(gray: 0, alpha: 1)
    private static let white = CGColor(gray: 1, alpha: 1)
    private static let faceColor = color(0x090909)
    private static let sourceHead = DogRenderer.headOutline.cgPath
    private static let sourceEars = DogRenderer.earLines.cgPath
    private static let baseline = DogRenderer.baselineOutline.cgPath
    private static let baselineInk = baseline.copy(strokingWithWidth: 2.5,
        lineCap: .round, lineJoin: .round, miterLimit: 10)

    private struct Source: Decodable {
        let version: Int
        let duration: Double
        let tailTip: [Double]
        let frames: [SourceFrame]
    }

    private struct SourceFrame: Decodable {
        let t: Double
        let h: Double
        let w: Double
        let x: Double
        let face: [Double]
        let colors: [SourceLayer]
    }

    private struct SourceLayer: Decodable {
        let fill: UInt32
        let path: [Double]
    }

    private struct Layer {
        let path: CGPath
        let color: CGColor
    }

    private struct Frame {
        let time: Double
        let headTransform: CGAffineTransform
        let head: CGPath
        let headInk: CGPath
        let ears: CGPath
        let face: CGPath
        let colors: [Layer]
        let headBounds: CGRect
    }

    private struct Artwork {
        let duration: Double
        let initialTailVector: CGPoint
        let frames: [Frame]
    }

    /// Compact resource commands are 0 = M, 1 = L, 2 = Z. No paths are parsed
    /// while drawing. The bundled resource stores only the paths and timing
    /// needed for playback, omitting empty color layers.
    private static func tracedPath(_ numbers: [Double]) -> CGPath? {
        let path = CGMutablePath()
        var index = 0
        var hasStart = false
        while index < numbers.count {
            let command = numbers[index]
            index += 1
            if command == 2 {
                guard hasStart else { return nil }
                path.closeSubpath()
                hasStart = false
            } else {
                guard command == 0 || command == 1, index + 1 < numbers.count,
                      numbers[index].isFinite, numbers[index + 1].isFinite,
                      command == 0 || hasStart else { return nil }
                let point = CGPoint(x: numbers[index] * videoToCanvas,
                    y: (696 - numbers[index + 1]) * videoToCanvas + DogRenderer.baselineY)
                if command == 0 { path.move(to: point); hasStart = true }
                else { path.addLine(to: point) }
                index += 2
            }
        }
        return path.copy()
    }

    private static let artwork: Artwork? = {
        guard let url = Bundle.module.url(forResource: "DogYawn", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let source = try? JSONDecoder().decode(Source.self, from: data),
              source.version == 1, source.duration.isFinite, source.duration > 0,
              source.frames.count == 97, let rest = source.frames.first,
              rest.t == 0, rest.w > 0, rest.h < 696,
              source.tailTip.count == 2, source.tailTip.allSatisfy(\.isFinite) else { return nil }

        let head = sourceHead
        let ears = sourceEars
        let anchor = CGPoint(x: 305 * sourceScale, y: DogRenderer.baselineY)
        var frames: [Frame] = []
        var palette: [UInt32: CGColor] = [:]
        for recorded in source.frames {
            guard recorded.t.isFinite, recorded.t >= 0, recorded.t <= source.duration,
                  frames.last.map({ recorded.t > $0.time }) ?? true,
                  recorded.h.isFinite, recorded.h < 696,
                  recorded.w.isFinite, recorded.w > 0, recorded.x.isFinite,
                  let face = tracedPath(recorded.face) else { return nil }
            var transform = CGAffineTransform(
                translationX: anchor.x + (recorded.x - rest.x) * videoToCanvas, y: anchor.y)
                .scaledBy(x: recorded.w / rest.w, y: (696 - recorded.h) / (696 - rest.h))
                .translatedBy(x: -anchor.x, y: -anchor.y)
            guard let movedHead = head.copy(using: &transform),
                  let movedEars = ears.copy(using: &transform) else { return nil }
            let headInk = inkOutline(movedHead)
            var layers: [Layer] = []
            for layer in recorded.colors {
                guard let path = tracedPath(layer.path), layer.fill <= 0xFFFFFF else { return nil }
                let fill = palette[layer.fill] ?? color(layer.fill)
                palette[layer.fill] = fill
                layers.append(Layer(path: path, color: fill))
            }
            frames.append(Frame(time: recorded.t, headTransform: transform, head: movedHead, headInk: headInk,
                ears: movedEars, face: face, colors: layers,
                headBounds: headInk.boundingBoxOfPath.intersection(clip)))
        }
        let root = CGPoint(x: 574 * videoScale, y: 696 + 12 * videoScale)
        let initial = CGPoint(x: source.tailTip[0] - root.x, y: source.tailTip[1] - root.y)
        guard hypot(initial.x, initial.y) > 0 else { return nil }
        return Artwork(duration: source.duration, initialTailVector: initial, frames: frames)
    }()

    private static func color(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    private static func inkOutline(_ path: CGPath) -> CGPath {
        path.copy(strokingWithWidth: 3.6, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    private static func boundedTime(_ time: Double) -> Double {
        time.isFinite ? min(duration, max(0, time)) : 0
    }

    static func frameIndex(at time: Double) -> Int {
        guard let frames = artwork?.frames else { return 0 }
        let time = boundedTime(time)
        var low = 0, high = frames.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if frames[middle].time <= time + 1e-7 { low = middle }
            else { high = middle - 1 }
        }
        return low
    }

    private static let dropKeys: [(Double, Double)] = [
        (0, 0), (0.25, 0), (1.0 / 3, 0.07), (0.5, 0.46), (2.0 / 3, 0.69),
        (1, 0.97), (7.0 / 6, 1), (1.5, 1), (5.0 / 3, 0.73),
        (11.0 / 6, 0.35), (2, 0.16), (2.25, 0), (4.062548752834467, 0)
    ]
    private static let dropSlopes: [Double] = dropKeys.indices.map { index in
        guard index > 0, index < dropKeys.count - 1 else { return 0 }
        let a = dropKeys[index - 1], p = dropKeys[index], b = dropKeys[index + 1]
        let h0 = p.0 - a.0, h1 = b.0 - p.0
        let d0 = (p.1 - a.1) / h0, d1 = (b.1 - p.1) / h1
        guard d0 * d1 > 0 else { return 0 }
        let w0 = 2 * h1 + h0, w1 = h1 + 2 * h0
        return (w0 + w1) / (w0 / d0 + w1 / d1)
    }

    private static func tailDrop(at time: Double) -> Double {
        var index = 0
        while index < dropKeys.count - 2 && time > dropKeys[index + 1].0 { index += 1 }
        let a = dropKeys[index], b = dropKeys[index + 1], h = b.0 - a.0
        let u = min(1, max(0, (time - a.0) / h)), u2 = u * u, u3 = u2 * u
        return (2 * u3 - 3 * u2 + 1) * a.1 + (u3 - 2 * u2 + u) * h * dropSlopes[index]
            + (-2 * u3 + 3 * u2) * b.1 + (u3 - u2) * h * dropSlopes[index + 1]
    }

    struct TailPose: Equatable {
        /// Angle is already converted to the native y-up coordinate system.
        let angle: Double
        let scale: Double
        let bend: Double
    }

    static func tailPose(at time: Double) -> TailPose {
        guard let artwork else { return TailPose(angle: 0, scale: 1, bend: 0) }
        let time = boundedTime(time), amount = tailDrop(at: time)
        let root = CGPoint(x: 574 * videoScale, y: 696 + 12 * videoScale)
        let initial = artwork.initialTailVector
        let target = CGPoint(x: 1121 - root.x, y: 574.8 - root.y)
        let now = CGPoint(x: initial.x + (target.x - initial.x) * amount,
                          y: initial.y + (target.y - initial.y) * amount)
        var wag = 0.0, bend = 0.0
        if time > 3 && time < 3.85 {
            let u = (time - 3) / 0.85, sine = sin(.pi * u), envelope = sine * sine
            wag = 0.11 * sin(2 * .pi * u) * envelope
            bend = 0.20 * sin(2 * .pi * u - 0.5) * envelope
        }
        return TailPose(angle: -(atan2(now.y, now.x) - atan2(initial.y, initial.x) + wag),
            scale: hypot(now.x, now.y) / hypot(initial.x, initial.y), bend: bend)
    }

    private struct TailGeometry {
        let pose: TailPose
        let size: DogTailSize
        let path: CGPath
        let ink: CGPath
    }
    // All large recorded paths are immutable caches. The four-curve tail alone
    // deforms continuously; reuse its most recent geometry for drawing and hit tests.
    private static var lastTail: TailGeometry?
    private static func tail(at time: Double, size: DogTailSize) -> TailGeometry {
        tail(pose: tailPose(at: time), size: size)
    }

    private static func tail(pose: TailPose, size: DogTailSize) -> TailGeometry {
        if let lastTail, lastTail.pose == pose, lastTail.size == size { return lastTail }
        let root = CGPoint(x: 574 * sourceScale, y: -12 * sourceScale + DogRenderer.baselineY)
        var transform = CGAffineTransform(translationX: root.x, y: root.y)
            .rotated(by: pose.angle).scaledBy(x: pose.scale, y: pose.scale)
            .translatedBy(x: -root.x, y: -root.y)
        let path = DogRenderer.tailPath(bend: pose.bend, tailSize: size).cgPath.copy(using: &transform)!
        let result = TailGeometry(pose: pose, size: size, path: path, ink: inkOutline(path))
        lastTail = result
        return result
    }

    private static func placement(size: NSSize) -> CGAffineTransform? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        let scale = min(size.width / DogRenderer.canvas.width, size.height / DogRenderer.canvas.height)
        return CGAffineTransform(translationX: (size.width - DogRenderer.canvas.width * scale) / 2, y: 1)
            .scaledBy(x: scale, y: scale)
    }

    static func draw(in context: CGContext, size: NSSize, time: Double, tailSize: DogTailSize = .small) {
        guard let artwork, let placement = placement(size: size) else { return }
        let frame = artwork.frames[frameIndex(at: time)], tail = tail(at: time, size: tailSize)
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(placement)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.saveGState()
        context.clip(to: clip)
        for path in [tail.path, frame.head] {
            context.setFillColor(white)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(black)
            context.setLineWidth(3.6)
            context.addPath(path)
            context.strokePath()
        }
        context.setFillColor(black)
        context.addPath(frame.ears)
        context.fillPath(using: .evenOdd)
        context.setFillColor(faceColor)
        context.addPath(frame.face)
        context.fillPath(using: .evenOdd)
        for layer in frame.colors {
            context.setFillColor(layer.color)
            context.addPath(layer.path)
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
        context.setStrokeColor(black)
        context.setLineWidth(2.5)
        context.addPath(baseline)
        context.strokePath()
    }

    private static func blendedTransform(_ normal: CGAffineTransform, _ recorded: CGAffineTransform,
                                         weight: Double) -> CGAffineTransform {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * weight }
        return CGAffineTransform(a: mix(normal.a, recorded.a), b: mix(normal.b, recorded.b),
            c: mix(normal.c, recorded.c), d: mix(normal.d, recorded.d),
            tx: mix(normal.tx, recorded.tx), ty: mix(normal.ty, recorded.ty))
    }

    private struct BlendedHead {
        let transform: CGAffineTransform
        let path: CGPath
        let ink: CGPath
    }

    private static func blendedHead(frame: Frame, normalPose: PetPose, weight: Double) -> BlendedHead {
        let normal = DogRenderer.headTransform(normalPose)
        var transform = blendedTransform(normal, frame.headTransform, weight: weight)
        let path = sourceHead.copy(using: &transform)!
        // Regular breathing scales its stroke along with the head; the clip keeps a
        // constant-width pen. Interpolate the pen too, so neither endpoint pops.
        var pen = blendedTransform(CGAffineTransform(a: normal.a, b: normal.b,
            c: normal.c, d: normal.d, tx: 0, ty: 0), .identity, weight: weight)
        var inversePen = pen.inverted()
        let unscaled = path.copy(using: &inversePen)!
        let ink = inkOutline(unscaled).copy(using: &pen)!
        return BlendedHead(transform: transform, path: path, ink: ink)
    }

    private static func blendedTail(time: Double, weight: Double, normalAngle: Double,
                                    normalBend: Double, size: DogTailSize) -> TailGeometry {
        let recorded = tailPose(at: time)
        return tail(pose: TailPose(angle: normalAngle + (recorded.angle - normalAngle) * weight,
            scale: 1 + (recorded.scale - 1) * weight,
            bend: normalBend + (recorded.bend - normalBend) * weight), size: size)
    }

    /// Morph one opaque silhouette through the short handoff. Only the face
    /// changes opacity, so the outer rim and ear creases cannot form double edges.
    static func drawBlended(in context: CGContext, size: NSSize, time: Double, tailSize: DogTailSize,
                            weight: Double, normalPose: PetPose, normalAngle: Double, normalBend: Double,
                            blink: Double, petting: Double) {
        guard let artwork, let placement = placement(size: size) else { return }
        let weight = weight.isFinite ? min(1, max(0, weight)) : 0
        if weight >= 1 {
            draw(in: context, size: size, time: time, tailSize: tailSize)
            return
        }
        if weight <= 0 {
            var normal = normalPose
            normal.yawn = nil
            DogRenderer.draw(in: context, size: size, pose: normal, angle: normalAngle,
                bend: normalBend, blink: blink, tailSize: tailSize, petting: petting)
            return
        }
        let frame = artwork.frames[frameIndex(at: time)]
        let head = blendedHead(frame: frame, normalPose: normalPose, weight: weight)
        var headTransform = head.transform
        let ears = sourceEars.copy(using: &headTransform)!
        let tail = blendedTail(time: time, weight: weight, normalAngle: normalAngle, normalBend: normalBend, size: tailSize)

        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(placement)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.saveGState()
        context.clip(to: clip)
        for (path, ink) in [(tail.path, tail.ink), (head.path, head.ink)] {
            context.setFillColor(white)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
            context.setFillColor(black)
            context.addPath(ink)
            context.fillPath()
        }
        context.setFillColor(black)
        context.addPath(ears)
        context.fillPath(using: .evenOdd)

        // Each complete face is weighted once, then added in an isolated layer.
        // This keeps overlapping black features dark instead of blending twice
        // against the white head, while leaving the silhouette fully opaque.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.saveGState()
        context.setAlpha(1 - weight)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.concatenate(headTransform)
        DogRenderer.drawFace(in: context, pose: normalPose, blink: blink, petting: petting)
        context.endTransparencyLayer()
        context.restoreGState()

        context.saveGState()
        context.setBlendMode(.plusLighter)
        context.setAlpha(weight)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        // The traced face is already in the recorded head's canvas coordinates.
        // Undo that pose before applying the shared interpolated head transform.
        context.concatenate(headTransform)
        context.concatenate(frame.headTransform.inverted())
        context.setFillColor(faceColor)
        context.addPath(frame.face)
        context.fillPath(using: .evenOdd)
        for layer in frame.colors {
            context.setFillColor(layer.color)
            context.addPath(layer.path)
            context.fillPath(using: .evenOdd)
        }
        context.endTransparencyLayer()
        context.restoreGState()
        context.endTransparencyLayer()

        context.restoreGState()
        context.setStrokeColor(black)
        context.setLineWidth(2.5)
        context.addPath(baseline)
        context.strokePath()
        var fadedNormal = normalPose
        fadedNormal.sleepLetters *= 1 - weight
        DogRenderer.drawSleepLetters(in: context, pose: fadedNormal)
    }

    static func headBoundsBlended(size: NSSize, time: Double, weight: Double, normalPose: PetPose) -> CGRect {
        guard let artwork, let placement = placement(size: size) else { return .null }
        let weight = weight.isFinite ? min(1, max(0, weight)) : 0
        let frame = artwork.frames[frameIndex(at: time)]
        let head = blendedHead(frame: frame, normalPose: normalPose, weight: weight)
        return head.ink.boundingBoxOfPath.intersection(clip).applying(placement)
    }

    static func containsBlended(_ point: NSPoint, size: NSSize, time: Double, tailSize: DogTailSize,
                                weight: Double, normalPose: PetPose, normalAngle: Double, normalBend: Double,
                                includesBaseline: Bool = true) -> Bool {
        guard let artwork, point.x.isFinite, point.y.isFinite,
              let placement = placement(size: size) else { return false }
        let local = point.applying(placement.inverted())
        if includesBaseline, baselineInk.contains(local) { return true }
        guard clip.contains(local) else { return false }
        let weight = weight.isFinite ? min(1, max(0, weight)) : 0
        let frame = artwork.frames[frameIndex(at: time)]
        let head = blendedHead(frame: frame, normalPose: normalPose, weight: weight)
        if head.path.contains(local, using: .evenOdd) || head.ink.contains(local) { return true }
        let tail = blendedTail(time: time, weight: weight, normalAngle: normalAngle, normalBend: normalBend, size: tailSize)
        return tail.path.contains(local, using: .evenOdd) || tail.ink.contains(local)
    }

    static func contains(_ point: NSPoint, size: NSSize, time: Double, tailSize: DogTailSize = .small,
                         includesBaseline: Bool = true) -> Bool {
        guard let artwork, point.x.isFinite, point.y.isFinite,
              let placement = placement(size: size) else { return false }
        let local = point.applying(placement.inverted())
        if includesBaseline, baselineInk.contains(local) { return true }
        guard clip.contains(local) else { return false }
        let frame = artwork.frames[frameIndex(at: time)]
        if frame.head.contains(local, using: .evenOdd) || frame.headInk.contains(local) { return true }
        let tail = tail(at: time, size: tailSize)
        return tail.path.contains(local, using: .evenOdd) || tail.ink.contains(local)
    }

    static func headBounds(size: NSSize, time: Double) -> CGRect {
        guard let artwork, let placement = placement(size: size) else { return .null }
        return artwork.frames[frameIndex(at: time)].headBounds.applying(placement)
    }
}
