import Foundation

struct DogTurnPose {
    var angle: Double
    /// Screen position of the visible head's pivot, not the transparent canvas centre.
    var center: CGPoint
    var badgeCenter: CGPoint
}

/// Bounds relative to the visible head pivot; the transparent strip below the baseline is excluded.
struct DogTurnBounds {
    let canonicalSize: CGSize
    var area: CGRect
    let baseline: CGFloat

    func offsets(angle: Double) -> CGRect {
        let drawing = CGRect(x: 0, y: baseline, width: canonicalSize.width,
                             height: canonicalSize.height - baseline)
        let pivot = DogTurnPresentation.pivot(in: canonicalSize)
        return drawing.applying(CGAffineTransform(rotationAngle: -angle * .pi / 180)
            .translatedBy(x: -pivot.x, y: -pivot.y))
    }

    func center(_ proposed: CGPoint, angle: Double) -> CGPoint {
        let box = offsets(angle: angle)
        func fit(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            low <= high ? min(high, max(low, value)) : (low + high) / 2
        }
        return CGPoint(x: fit(proposed.x, area.minX - box.minX, area.maxX - box.maxX),
                       y: fit(proposed.y, area.minY - box.minY, area.maxY - box.maxY))
    }
}

/// C1-continuous retargeting, with zero velocity and acceleration at the destination.
struct DogTurnMotion {
    let started: TimeInterval
    let duration: TimeInterval
    private(set) var from: DogTurnPose
    private(set) var to: DogTurnPose
    private let initialVelocity: DogTurnPose
    private let centerExcursion: CGPoint
    private var bounds: DogTurnBounds?
    let followsBoundsContinuously: Bool

    init(now: TimeInterval, from: DogTurnPose, targetAngle: Double, center: CGPoint,
         badgeCenter: CGPoint, velocity: DogTurnPose? = nil, duration: TimeInterval? = nil,
         bounds: DogTurnBounds? = nil) {
        started = now
        self.from = from
        var delta = (targetAngle - from.angle).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        if abs(abs(delta) - 180) < 0.00001 { delta = 180 }
        self.duration = duration ?? (0.52 + 0.13 * min(1, max(0, abs(delta) / 90 - 1)))
        to = DogTurnPose(angle: from.angle + delta, center: center, badgeCenter: badgeCenter)
        initialVelocity = velocity ?? DogTurnPose(angle: 0, center: .zero, badgeCenter: .zero)
        self.bounds = bounds
        let plan = Self.planClearance(from: from, to: to, velocity: initialVelocity,
                                      duration: self.duration, bounds: bounds)
        centerExcursion = plan.offset
        followsBoundsContinuously = plan.fits
    }

    func isFinished(now: TimeInterval) -> Bool { now - started >= duration }

    func pose(now: TimeInterval) -> DogTurnPose {
        let t = min(1, max(0, (now - started) / duration))
        if t == 0 { return from }
        if t == 1 { return to }
        let ease = t * t * t * (10 + t * (-15 + 6 * t))
        let carry = t - 6 * pow(t, 3) + 8 * pow(t, 4) - 3 * pow(t, 5)
        let clearance = 64 * pow(t * (1 - t), 3)
        func value(_ a: Double, _ b: Double, _ v: Double) -> Double {
            a + (b - a) * ease + v * duration * carry
        }
        let angle = value(from.angle, to.angle, initialVelocity.angle)
        var center = CGPoint(x: value(from.center.x, to.center.x, initialVelocity.center.x) + centerExcursion.x * clearance,
                             y: value(from.center.y, to.center.y, initialVelocity.center.y) + centerExcursion.y * clearance)
        if !followsBoundsContinuously, let bounds { center = bounds.center(center, angle: angle) }
        return DogTurnPose(angle: angle, center: center,
            badgeCenter: CGPoint(x: value(from.badgeCenter.x, to.badgeCenter.x, initialVelocity.badgeCenter.x),
                                 y: value(from.badgeCenter.y, to.badgeCenter.y, initialVelocity.badgeCenter.y)))
    }

    func velocity(now: TimeInterval) -> DogTurnPose {
        let t = min(1, max(0, (now - started) / duration))
        let ease = 30 * t * t * pow(1 - t, 2) / duration
        let carry = 1 - 18 * t * t + 32 * pow(t, 3) - 15 * pow(t, 4)
        let clearance = 192 * t * t * pow(1 - t, 2) * (1 - 2 * t) / duration
        func value(_ a: Double, _ b: Double, _ v: Double) -> Double { (b - a) * ease + v * carry }
        return DogTurnPose(angle: value(from.angle, to.angle, initialVelocity.angle),
            center: CGPoint(x: value(from.center.x, to.center.x, initialVelocity.center.x) + centerExcursion.x * clearance,
                            y: value(from.center.y, to.center.y, initialVelocity.center.y) + centerExcursion.y * clearance),
            badgeCenter: CGPoint(x: value(from.badgeCenter.x, to.badgeCenter.x, initialVelocity.badgeCenter.x),
                                 y: value(from.badgeCenter.y, to.badgeCenter.y, initialVelocity.badgeCenter.y)))
    }

    func translated(by offset: CGPoint) -> DogTurnMotion {
        var result = self
        result.from.center.x += offset.x; result.from.center.y += offset.y
        result.to.center.x += offset.x; result.to.center.y += offset.y
        result.from.badgeCenter.x += offset.x; result.from.badgeCenter.y += offset.y
        result.to.badgeCenter.x += offset.x; result.to.badgeCenter.y += offset.y
        if let bounds { result.bounds?.area = bounds.area.offsetBy(dx: offset.x, dy: offset.y) }
        return result
    }

    /// Plan once per turn, avoiding a rotation/translation pause or a per-frame hard clamp.
    private static func planClearance(from: DogTurnPose, to: DogTurnPose, velocity: DogTurnPose,
                                      duration: TimeInterval, bounds: DogTurnBounds?) -> (offset: CGPoint, fits: Bool) {
        guard let bounds else { return (.zero, true) }
        var low = CGPoint(x: -Double.infinity, y: -Double.infinity)
        var high = CGPoint(x: Double.infinity, y: Double.infinity)
        for sample in 1..<128 {
            let t = Double(sample) / 128
            let ease = t * t * t * (10 + t * (-15 + 6 * t))
            let carry = t - 6 * pow(t, 3) + 8 * pow(t, 4) - 3 * pow(t, 5)
            let clearance = 64 * pow(t * (1 - t), 3)
            let angle = from.angle + (to.angle - from.angle) * ease + velocity.angle * duration * carry
            let center = CGPoint(x: from.center.x + (to.center.x - from.center.x) * ease + velocity.center.x * duration * carry,
                                 y: from.center.y + (to.center.y - from.center.y) * ease + velocity.center.y * duration * carry)
            let box = bounds.offsets(angle: angle)
            low.x = max(low.x, (bounds.area.minX - box.minX - center.x) / clearance + 0.05)
            low.y = max(low.y, (bounds.area.minY - box.minY - center.y) / clearance + 0.05)
            high.x = min(high.x, (bounds.area.maxX - box.maxX - center.x) / clearance - 0.05)
            high.y = min(high.y, (bounds.area.maxY - box.maxY - center.y) / clearance - 0.05)
        }
        guard low.x <= high.x, low.y <= high.y else { return (.zero, false) }
        return (CGPoint(x: min(high.x, max(low.x, 0)), y: min(high.y, max(low.y, 0))), true)
    }
}

struct DogTurnPresentation {
    let canonicalSize: CGSize
    let angle: Double

    static func pivot(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 108 / 260, y: size.height * 42 / 148)
    }

    static func enclosingSide(for size: CGSize) -> CGFloat {
        let pivot = pivot(in: size)
        let radius = hypot(max(pivot.x, size.width - pivot.x), max(pivot.y, size.height - pivot.y))
        return ceil(radius) * 2 + 4
    }

    func transform(in bounds: CGRect) -> CGAffineTransform {
        let pivot = Self.pivot(in: canonicalSize)
        return CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .rotated(by: -angle * .pi / 180)
            .translatedBy(x: -pivot.x, y: -pivot.y)
    }
}
