import Foundation

/// A short pleased expression, independent of other characters and input data.
/// Retriggering preserves the current value and velocity rather than reopening.
struct DogPetExpression {
    private struct State { var value = 0.0; var velocity = 0.0 }
    private var started: TimeInterval?
    private var from = State()
    static let duration = 0.85

    mutating func touch(now: TimeInterval) {
        guard now.isFinite, started.map({ now >= $0 }) ?? true else { return }
        from = sample(now: now)
        started = now
    }

    func value(now: TimeInterval) -> Double {
        min(1, max(0, sample(now: now).value))
    }

    func isMoving(now: TimeInterval) -> Bool {
        guard now.isFinite, let started else { return false }
        return now - started < Self.duration
    }

    mutating func cancel() { started = nil; from = State() }

    private func sample(now: TimeInterval) -> State {
        guard now.isFinite, let started else { return State() }
        let age = max(0, now - started)
        if age <= 0.35 { return spring(from, target: 1, age: age, frequency: 32) }
        let releaseAge = age - 0.35
        guard releaseAge < 0.5 else { return State() }
        let held = spring(from, target: 1, age: 0.35, frequency: 32)
        let base = spring(held, target: 0, age: releaseAge, frequency: 15)
        let progress = min(1, max(0, (releaseAge - 0.3) / 0.2))
        let weight = 1 - progress * progress * (3 - 2 * progress)
        let derivative = progress > 0 && progress < 1 ? -6 * progress * (1 - progress) / 0.2 : 0
        return State(value: base.value * weight, velocity: base.velocity * weight + base.value * derivative)
    }

    private func spring(_ state: State, target: Double, age: Double, frequency: Double) -> State {
        let displacement = state.value - target
        let coefficient = state.velocity + frequency * displacement
        let decay = exp(-frequency * age)
        return State(value: target + (displacement + coefficient * age) * decay,
                     velocity: (coefficient - frequency * (displacement + coefficient * age)) * decay)
    }
}
