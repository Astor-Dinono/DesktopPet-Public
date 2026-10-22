import Foundation

struct TailPose {
    var angle: Double = 0
    var bend: Double = 0
}

/// Transient animation only. A spring envelope preserves position AND speed on retrigger.
struct DogMotion {
    private struct State {
        var value: Double = 0
        var velocity: Double = 0
    }
    private struct Transition {
        let started: TimeInterval
        let from: State
        let settling: Bool
    }
    private var phaseStarted: TimeInterval?
    private var transition: Transition?
    private static let hold = 0.42
    private static let decay = 0.88

    mutating func wag(now: TimeInterval) {
        let current = envelope(now: now)
        if !isMoving(now: now) { phaseStarted = now }
        transition = Transition(started: now, from: current, settling: false)
    }

    mutating func settle(now: TimeInterval) {
        guard isMoving(now: now) else { return }
        transition = Transition(started: now, from: envelope(now: now), settling: true)
    }

    func pose(now: TimeInterval, reducedMotion: Bool = false) -> TailPose {
        guard let phaseStarted, !reducedMotion else { return TailPose() }
        let age = max(0, now - phaseStarted)
        // A quick cheerful burst; a slight tempo change prevents a metronomic swing.
        let phase = age * 15.6 + sin(age * 5.5) * 0.28
        let energy = envelope(now: now).value
        return TailPose(
            angle: (sin(phase) + 0.12 * sin(phase * 2)) / 1.12 * 0.21 * energy,
            bend: sin(phase - 0.60) * 0.36 * energy
        )
    }

    func angle(now: TimeInterval, reducedMotion: Bool = false) -> Double {
        pose(now: now, reducedMotion: reducedMotion).angle
    }

    func isMoving(now: TimeInterval) -> Bool {
        guard let transition else { return false }
        return now - transition.started < (transition.settling ? 0.45 : Self.hold + Self.decay)
    }

    private func envelope(now: TimeInterval) -> State {
        guard let transition else { return State() }
        let age = max(0, now - transition.started)
        if transition.settling {
            return fall(from: transition.from, age: age, duration: 0.45, frequency: 12)
        }
        if age <= Self.hold {
            return spring(from: transition.from, target: 1, age: age, frequency: 25)
        }
        let peak = spring(from: transition.from, target: 1, age: Self.hold, frequency: 25)
        return fall(from: peak, age: age - Self.hold, duration: Self.decay, frequency: 7)
    }

    private func spring(from state: State, target: Double, age: Double, frequency: Double) -> State {
        let displacement = state.value - target
        let coefficient = state.velocity + frequency * displacement
        let decay = exp(-frequency * age)
        return State(
            value: target + (displacement + coefficient * age) * decay,
            velocity: (coefficient - frequency * (displacement + coefficient * age)) * decay
        )
    }

    private func fall(from state: State, age: Double, duration: Double, frequency: Double) -> State {
        guard age < duration else { return State() }
        let base = spring(from: state, target: 0, age: age, frequency: frequency)
        let fadeDuration = min(0.2, duration)
        let progress = min(1, max(0, (age - (duration - fadeDuration)) / fadeDuration))
        let window = 1 - PetMotion.smoothstep(progress)
        let velocity = progress > 0 && progress < 1 ? -6 * progress * (1 - progress) / fadeDuration : 0
        return State(value: base.value * window, velocity: base.velocity * window + base.value * velocity)
    }

    /// A brief, quiet blink. RestMotion owns the slower sleeping eyelids.
    static func blink(now: TimeInterval, reducedMotion: Bool = false) -> Double {
        guard !reducedMotion else { return 0 }
        let age = now.truncatingRemainder(dividingBy: 7.3) - 5.2
        guard age >= 0, age < 0.28 else { return 0 }
        if age < 0.10 { return PetMotion.smoothstep(age / 0.10) }
        return 1 - PetMotion.smoothstep((age - 0.10) / 0.18)
    }
}
