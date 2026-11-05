import Foundation

/// A single local clip before sleep. Interruptions retain the displayed frame
/// for a brief handoff; repeated activity never restarts that handoff.
struct DogYawnMotion {
    static let duration = 4.062548752834467
    static let handoff = 0.24
    private var started: TimeInterval?
    private var interruption: (started: TimeInterval, pose: DogYawnPose, decoration: Double)?

    mutating func start(now: TimeInterval) {
        started = now
        interruption = nil
    }

    mutating func cancel(now: TimeInterval) {
        guard interruption == nil else { return }
        if let current = pose(now: now) {
            interruption = (now, current, sleepDecorationAmount(now: now))
        }
        started = nil
    }

    func pose(now: TimeInterval) -> DogYawnPose? {
        if let interruption {
            let weight = interruption.pose.weight * (1 - ease((now - interruption.started) / Self.handoff))
            return weight > 0 ? DogYawnPose(time: interruption.pose.time, weight: weight) : nil
        }
        guard let started else { return nil }
        let age = max(0, now - started)
        guard age < Self.duration + Self.handoff else { return nil }
        let weight = ease(age / 0.16) * (1 - ease((age - Self.duration) / Self.handoff))
        return DogYawnPose(time: min(age, Self.duration), weight: weight)
    }

    func isAnimating(now: TimeInterval) -> Bool { pose(now: now) != nil }

    /// Keep bubble and letters out of the yawn, then grow them normally.
    func sleepDecorationAmount(now: TimeInterval) -> Double {
        if let interruption { return interruption.decoration }
        guard let started else { return 1 }
        return ease((now - started - Self.duration) / 0.7)
    }

    private func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }
}

struct DogYawnPose {
    let time: TimeInterval
    let weight: Double
}
