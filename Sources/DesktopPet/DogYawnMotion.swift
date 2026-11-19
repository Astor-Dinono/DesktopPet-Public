import Foundation

/// A single local clip before sleep. Interruptions retain the displayed frame
/// for a brief handoff; repeated activity never restarts that handoff.
struct DogYawnMotion {
    static let duration = 4.062548752834467
    static let handoff = 0.24
    private var started: TimeInterval?
    private var interruption: (started: TimeInterval, pose: DogYawnPose)?
    private enum Decoration {
        case followingYawn
        case held(Double)
        case recovering(started: TimeInterval, from: Double)
    }
    private var decoration = Decoration.followingYawn

    mutating func start(now: TimeInterval) {
        started = now
        interruption = nil
        decoration = .followingYawn
    }

    mutating func cancel(now: TimeInterval) {
        let decorationAmount = sleepDecorationAmount(now: now)
        if interruption == nil, let current = pose(now: now) {
            interruption = (now, current)
        }
        started = nil
        decoration = .held(decorationAmount)
    }

    /// A quick return to sleep keeps the interrupted silhouette instead of
    /// jumping back to a new clip. Decorations return from their visible level.
    mutating func resumeSleep(now: TimeInterval) {
        decoration = .recovering(started: now, from: sleepDecorationAmount(now: now))
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
        switch decoration {
        case .held(let amount): return amount
        case .recovering(let started, let from):
            return from + (1 - from) * ease((now - started) / 0.7)
        case .followingYawn:
            guard let started else { return 1 }
            return ease((now - started - Self.duration) / 0.7)
        }
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
