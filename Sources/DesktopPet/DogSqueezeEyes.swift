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
        let context = NSGraphicsContext.current!.cgContext
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.addPath(transitionOutline(at: center, left: left, normalClosed: normalClosed, amount: amount))
        context.fillPath()
    }

    nonisolated private static let steps = 256
    /// Rays from the elbow stay inside the union of the two round-ended strokes.
    /// Cache the outline once; no opacity blending or intermediate eye-closing phase.
    private static let chevrons: [[CGPoint]] = [1.0, -1.0].map { sign in
        let elbow = CGPoint(x: sign * 3.7, y: 0)
        let tips = [CGPoint(x: -sign * 3.7, y: 4.6), CGPoint(x: -sign * 3.7, y: -4.6)]
        func inside(_ p: CGPoint) -> Bool {
            tips.contains { tip in
                let dx = tip.x-elbow.x, dy = tip.y-elbow.y
                let t = min(1, max(0, ((p.x-elbow.x)*dx+(p.y-elbow.y)*dy)/(dx*dx+dy*dy)))
                return hypot(p.x-elbow.x-t*dx, p.y-elbow.y-t*dy) <= 0.85
            }
        }
        return (0..<steps).map { index in
            let angle = Double(index) * 2 * .pi / Double(steps), dx = cos(angle), dy = sin(angle)
            var low = 0.0, high = 12.0
            for _ in 0..<40 {
                let mid = (low+high)/2
                if inside(CGPoint(x: elbow.x+dx*mid, y: elbow.y+dy*mid)) { low = mid } else { high = mid }
            }
            return CGPoint(x: elbow.x+dx*low, y: elbow.y+dy*low)
        }
    }

    static func transitionOutline(at center: CGPoint, left: Bool, normalClosed: Double, amount: Double) -> CGPath {
        let a = amount.isFinite ? min(1, max(0, amount)) : 0
        if a == 0 { return DogRenderer.eyeOutline(at: center, closed: normalClosed).cgPath }
        if a == 1 {
            return pose(at: center, left: left, normalClosed: normalClosed, amount: 1).squeeze.cgPath
                .copy(strokingWithWidth: 1.7, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        // Petting takes over a coincident blink continuously. Keeping a fully
        // closed crescent fixed would fold its pointed corner during the morph.
        let closed = min(1, max(0, normalClosed)) * max(0, 1 - 2*a)
        let w = 5.4+closed*0.9, h = 5.4*(1-closed)+closed*1.52, sag = -closed*1.8
        let top = h+sag, bottom = -h+sag, k = 0.55228475
        let quarters: [[CGPoint]] = [
            [.init(x:w,y:0),.init(x:w,y:top*k),.init(x:w*k,y:top),.init(x:0,y:top)],
            [.init(x:0,y:top),.init(x:-w*k,y:top),.init(x:-w,y:top*k),.init(x:-w,y:0)],
            [.init(x:-w,y:0),.init(x:-w,y:bottom*k),.init(x:-w*k,y:bottom),.init(x:0,y:bottom)],
            [.init(x:0,y:bottom),.init(x:w*k,y:bottom),.init(x:w,y:bottom*k),.init(x:w,y:0)]
        ]
        let target = chevrons[left ? 0 : 1], result = CGMutablePath()
        for i in 0..<steps {
            let section = i / (steps/4), t = Double(i % (steps/4)) / Double(steps/4), u = 1-t, p = quarters[section]
            let x = u*u*u*p[0].x+3*u*u*t*p[1].x+3*u*t*t*p[2].x+t*t*t*p[3].x
            let y = u*u*u*p[0].y+3*u*u*t*p[1].y+3*u*t*t*p[2].y+t*t*t*p[3].y
            let point = CGPoint(x: center.x+x+(target[i].x-x)*a, y: center.y+y+(target[i].y-y)*a)
            if i == 0 { result.move(to: point) } else { result.addLine(to: point) }
        }
        result.closeSubpath(); return result
    }

    private static func smooth(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
}
