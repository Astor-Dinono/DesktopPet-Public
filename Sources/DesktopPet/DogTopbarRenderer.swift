import AppKit

/// The original dog at the user's chosen scale, positioned near the menu edge.
/// There is no topbar-specific head, face, tail or deformation.
@MainActor
enum DogTopbarRenderer {
    struct Layout {
        let scale: CGFloat
        let offset: CGPoint
    }

    // Keep one stable scale through breathing and interaction. Reserve space for
    // the existing bounded duang (-0.20), deep breath and waking inhale rather
    // than flattening the head or changing the scale every animation frame.
    private static let motionHeight: CGFloat = {
        let head = DogRenderer.headOutline.cgPath.copy(strokingWithWidth: 3.6,
            lineCap: .round, lineJoin: .round, miterLimit: 10).boundingBoxOfPath
        let headHeight = (head.maxY - DogRenderer.baselineY) * (1 + 1.35 * 0.04 + 0.20 + 0.014)
        let root = CGPoint(x: 574 * 260.0 / 749, y: (268 - 280) * 260.0 / 749 + DogRenderer.baselineY)
        var tailHeight: CGFloat = 0
        for angle in [-0.235, 0, 0.235] { for bend in [-0.36, 0, 0.36] {
            var rotation = CGAffineTransform(translationX: root.x, y: root.y)
                .rotated(by: angle).translatedBy(x: -root.x, y: -root.y)
            let tail = DogRenderer.tailPath(bend: bend, tailSize: .original).cgPath
                .copy(strokingWithWidth: 3.6, lineCap: .round, lineJoin: .round, miterLimit: 10)
                .copy(using: &rotation)!.boundingBoxOfPath
            tailHeight = max(tailHeight, tail.maxY - DogRenderer.baselineY)
        }}
        return max(headHeight, tailHeight)
    }()

    // Preserve exactly the old 148 × 38-point topbar dog's fitted size as a
    // selectable size. This reference never changes with the current display.
    // Freeze the original fitted scale: artwork refinements must not silently
    // resize existing pets or stop recognizing their saved size preference.
    static let tinyScale: Double = 0.3678859203570799

    static func drawingSize(scale: Double, bandHeight: CGFloat) -> CGSize {
        CGSize(width: max(148, DogRenderer.canvas.width * scale + 4),
               height: max(bandHeight, ceil(2.6 + motionHeight * scale)))
    }

    static func layout(size: CGSize, scale: Double = tinyScale) -> Layout {
        let baseline = DogTopbarPlacement.baselineInset
        // DogRenderer adds one canonical point below its baseline.
        return Layout(scale: scale, offset: CGPoint(
            x: (size.width - DogRenderer.canvas.width * scale) / 2,
            y: baseline - (1 + DogRenderer.baselineY) * scale))
    }

    static func contains(_ point: CGPoint, size: CGSize, pose: PetPose,
                         tail: TailPose, tailSize: DogTailSize, scale: Double = tinyScale,
                         includesBaseline: Bool = true) -> Bool {
        let layout = layout(size: size, scale: scale)
        let local = CGPoint(x: (point.x - layout.offset.x) / layout.scale,
                            y: (point.y - layout.offset.y) / layout.scale)
        return DogRenderer.contains(local, size: DogRenderer.canvas, pose: pose,
            angle: tail.angle, bend: tail.bend, tailSize: tailSize, includesBaseline: includesBaseline)
    }

    static func draw(in context: CGContext, size: CGSize, pose: PetPose,
                     tail: TailPose, blink: Double, tailSize: DogTailSize, scale: Double = tinyScale,
                     petting: Double = 0) {
        let layout = layout(size: size, scale: scale)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: layout.offset.x, y: layout.offset.y)
        context.scaleBy(x: layout.scale, y: layout.scale)
        var originalPose = pose
        originalPose.sleepLetters = 0 // Keep letters out of the narrow menu strip.
        DogRenderer.draw(in: context, size: DogRenderer.canvas, pose: originalPose,
            angle: tail.angle, bend: tail.bend, blink: blink, tailSize: tailSize, petting: petting)
    }
}
