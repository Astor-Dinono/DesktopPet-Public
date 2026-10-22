import Foundation

/// Separate, staggered channels for eyelids, posture, bubble and sleep letters.
/// Every interruption captures the displayed pose so none of the channels jump.
struct RestMotion {
    private var transition: (started: TimeInterval, from: RestPose, sleeping: Bool)?

    mutating func sleep(now: TimeInterval) {
        transition = (now, pose(now: now), true)
    }

    mutating func wake(now: TimeInterval) {
        transition = (now, pose(now: now), false)
    }

    func pose(now: TimeInterval) -> RestPose {
        guard let transition else { return RestPose() }
        let age = max(0, now - transition.started)
        let from = transition.from
        func blend(_ value: Double, to target: Double, delay: Double, duration: Double) -> Double {
            let progress = PetMotion.smoothstep(min(1, max(0, (age - delay) / duration)))
            return value + (target - value) * progress
        }
        let residualStretch = from.stretch * (1 - PetMotion.smoothstep(min(age / 0.35, 1)))
        if transition.sleeping {
            return RestPose(
                closed: blend(from.closed, to: 1, delay: 0, duration: 1.35),
                bubble: blend(from.bubble, to: 1, delay: 0.85, duration: 0.9),
                letters: blend(from.letters, to: 1, delay: 1.45, duration: 1),
                settle: blend(from.settle, to: 1, delay: 0.15, duration: 1.55),
                stretch: residualStretch,
                phaseAge: from.phaseAge + age
            )
        }
        // A tiny waking inhale, not another landing bounce.
        let inhaleProgress = min(1, max(0, (age - 0.15) / 0.95))
        let inhale = pow(sin(inhaleProgress * .pi), 2) * 0.014 * from.settle
        return RestPose(
            closed: blend(from.closed, to: 0, delay: 0.15, duration: 0.65),
            bubble: blend(from.bubble, to: 0, delay: 0, duration: 0.45),
            letters: blend(from.letters, to: 0, delay: 0, duration: 0.35),
            settle: blend(from.settle, to: 0, delay: 0.1, duration: 0.95),
            stretch: residualStretch + inhale,
            phaseAge: from.phaseAge + age
        )
    }

    func isTransitioning(now: TimeInterval) -> Bool {
        guard let transition else { return false }
        return now - transition.started < (transition.sleeping ? 2.45 : 1.1)
    }
}

struct RestPose {
    var closed: Double = 0
    var bubble: Double = 0
    var letters: Double = 0
    var settle: Double = 0
    var stretch: Double = 0
    var phaseAge: Double = 0
}
