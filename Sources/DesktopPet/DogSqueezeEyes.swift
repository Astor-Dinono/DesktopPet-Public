import AppKit

/// The selected B expression only: left >, right <, in the original face space.
@MainActor
enum DogSqueezeEyes {
    struct Pose {
        let normal: NSBezierPath
        let squeeze: NSBezierPath
        let normalAlpha: Double
        let squeezeAlpha: Double
        let strokeWidth: CGFloat = 1.7
    }

    static func effectiveAmount(petting: Double, sleep: Double, reducedMotion: Bool = false) -> Double {
        let amount = (petting.isFinite ? min(1, max(0, petting)) : 0) * (1 - min(1, max(0, sleep)))
        return reducedMotion ? (amount > 0.05 ? 1 : 0) : amount
    }

    static func pose(at center: NSPoint, left: Bool, normalClosed: Double, amount: Double) -> Pose {
        let a = amount.isFinite ? min(1, max(0, amount)) : 0
        let normal = DogRenderer.eyeOutline(at: center, closed: normalClosed + (1 - normalClosed) * smooth(a / 0.4))
        let squeezeAlpha = smooth((a - 0.15) / 0.65)
        let sign = left ? 1.0 : -1.0
        let squeeze = NSBezierPath()
        squeeze.move(to: NSPoint(x: center.x - sign * 3.7, y: center.y + 4.6))
        squeeze.line(to: NSPoint(x: center.x + sign * 3.7, y: center.y))
        squeeze.line(to: NSPoint(x: center.x - sign * 3.7, y: center.y - 4.6))
        squeeze.lineCapStyle = .round
        squeeze.lineJoinStyle = .round
        return Pose(normal: normal, squeeze: squeeze, normalAlpha: 1 - squeezeAlpha, squeezeAlpha: squeezeAlpha)
    }

    static func draw(at center: NSPoint, left: Bool, normalClosed: Double, amount: Double) {
        let pose = pose(at: center, left: left, normalClosed: normalClosed, amount: amount)
        if pose.normalAlpha > 0 {
            NSColor.black.withAlphaComponent(pose.normalAlpha).setFill()
            pose.normal.fill()
        }
        if pose.squeezeAlpha > 0 {
            NSColor.black.withAlphaComponent(pose.squeezeAlpha).setStroke()
            pose.squeeze.lineWidth = pose.strokeWidth
            pose.squeeze.stroke()
        }
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
