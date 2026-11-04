import Foundation
import CoreGraphics

/// The same local pointer gesture as Windows StrokeGesture. Points are logical
/// screen points supplied by the owning view; no listener, timer, or persistence.
struct DogStrokeGesture {
    static let dragThreshold = 4.0
    static let pulseDistance = 10.0
    static let pulseInterval = 0.12

    private var origin: CGPoint = .zero
    private var last: CGPoint = .zero
    private var distance = 0.0
    private var lastTime = 0.0
    private var lastPulse = 0.0
    private var inside = false
    private var pulsed = false
    private var clickEligible = false
    private(set) var active = false
    private(set) var didStroke = false

    mutating func cancel() { self = Self() }

    mutating func begin(_ point: CGPoint, now: Double, inside: Bool) {
        cancel()
        guard inside, Self.finite(point), now.isFinite else { return }
        origin = point
        last = point
        lastTime = now
        active = true
        self.inside = true
        clickEligible = true
    }

    /// Returns at most one response per movement. Repeated samples at the same
    /// position cannot consume accumulated travel or produce delayed responses.
    mutating func move(_ point: CGPoint, now: Double, inside: Bool) -> Bool {
        guard active else { return false }
        guard Self.finite(point), now.isFinite, now >= lastTime else {
            cancel()
            return false
        }
        let step = Self.distance(point, last)
        let excursion = Self.distance(point, origin)
        guard step.isFinite, excursion.isFinite else {
            cancel()
            return false
        }
        let wasStroke = didStroke
        if excursion > Self.dragThreshold { didStroke = true }
        last = point
        lastTime = now

        // Captured events may leave the silhouette. Neither that travel nor the
        // segment returning to the dog should count as touching its fur.
        guard inside else {
            self.inside = false
            clickEligible = false
            distance = 0
            return false
        }
        guard self.inside else {
            self.inside = true
            distance = 0
            return false
        }
        guard step != 0, didStroke else { return false }
        // Ignore jitter inside the click tolerance; afterwards use travelled
        // distance rather than displacement so back-and-forth motion counts.
        distance = min(Self.pulseDistance, wasStroke ? distance + step : excursion)
        guard distance >= Self.pulseDistance,
              !pulsed || now - lastPulse >= Self.pulseInterval else { return false }
        distance = 0
        lastPulse = now
        pulsed = true
        return true
    }

    /// Returns whether the release is one ordinary click, then clears all state.
    /// A stroke must not receive an extra click response when the button lifts.
    mutating func finish(_ point: CGPoint, inside: Bool) -> Bool {
        let click = active && clickEligible && inside && Self.finite(point)
            && !didStroke && Self.distance(point, origin) <= Self.dragThreshold
        cancel()
        return click
    }

    private static func finite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }
}
