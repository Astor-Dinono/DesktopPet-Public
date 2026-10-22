import Foundation

/// A damped body spring. Every new touch inherits position and velocity.
struct DuangMotion {
    private struct State { var value = 0.0; var velocity = 0.0 }
    private var started: TimeInterval?
    private var from = State()
    private var strength = 0.0
    static let duration = 1.25

    mutating func kick(now: TimeInterval, strength: Double) {
        from = sample(now: now)
        started = now
        self.strength = strength
    }

    mutating func settle(now: TimeInterval) {
        guard isMoving(now: now) else { return }
        kick(now: now, strength: 0)
    }

    mutating func cancel() { started = nil; from = State(); strength = 0 }

    func value(now: TimeInterval) -> Double {
        // Smoothly bound rapid clicks without cutting off the displayed motion.
        0.20 * tanh(sample(now: now).value / 0.20)
    }

    func isMoving(now: TimeInterval) -> Bool {
        started.map { now - $0 < Self.duration } ?? false
    }

    private func sample(now: TimeInterval) -> State {
        guard let started else { return State() }
        let age = max(0, now - started)
        guard age < Self.duration else { return State() }
        let frequency = 20.0
        let damping = 3.7
        let sine = sin(age * frequency)
        let cosine = cos(age * frequency)
        let decay = exp(-damping * age)
        let coefficient = (from.velocity + damping * from.value) / frequency
        let residual = from.value * cosine + coefficient * sine
        let residualVelocity = frequency * (-from.value * sine + coefficient * cosine) - damping * residual
        // Rise from zero position AND velocity, so a retrigger cannot snap either.
        let riseDecay = exp(-60 * age)
        let rise = 1 - riseDecay
        let pulse = 0.17 * strength * sine * rise
        let pulseVelocity = 0.17 * strength * (frequency * cosine * rise + 60 * sine * riseDecay - damping * sine * rise)
        let value = decay * (residual + pulse)
        let velocity = decay * (residualVelocity + pulseVelocity)
        let progress = min(1, max(0, (age - 0.8) / 0.45))
        let window = 1 - PetMotion.smoothstep(progress)
        let windowVelocity = progress > 0 && progress < 1 ? -6 * progress * (1 - progress) / 0.45 : 0
        return State(value: value * window, velocity: velocity * window + value * windowVelocity)
    }
}
