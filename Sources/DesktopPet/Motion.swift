import Foundation

/// Only transient animation state. No activity history or input data is persisted.
struct PetMotion {
    static let sleepDelay = Double(AutoNap.defaultValue.rawValue)
    private(set) var autoNap: AutoNap
    private(set) var lastInteraction: TimeInterval
    private(set) var sleepStarted: TimeInterval?
    private(set) var reactionStarted: TimeInterval?
    private(set) var landingStarted: TimeInterval?
    private(set) var isDragging = false
    private var blush = BlushState()
    private var rest = RestMotion()
    private var duang = DuangMotion()
    private var sleepingAutomatically = false
    var dogYawnEnabled = false
    private var dogYawn = DogYawnMotion()

    init(now: TimeInterval, autoNap: AutoNap = .defaultValue) {
        lastInteraction = now
        self.autoNap = autoNap
    }

    mutating func setAutoNap(_ option: AutoNap, now: TimeInterval) {
        autoNap = option
        if option == .off, sleepingAutomatically { wake(now: now) }
        if sleepStarted == nil { lastInteraction = now }
    }

    mutating func advance(now: TimeInterval) {
        if let delay = autoNap.delay, !isDragging, sleepStarted == nil, now - lastInteraction >= delay {
            enterSleep(now: lastInteraction + delay, automatic: true)
        }
    }

    mutating func wake(now: TimeInterval) {
        // Already waking? Further clicks must not restart the opening eyelids.
        if sleepStarted != nil {
            rest.wake(now: now)
            dogYawn.cancel(now: now)
        }
        lastInteraction = now
        sleepStarted = nil
        sleepingAutomatically = false
    }

    mutating func sleep(now: TimeInterval) {
        enterSleep(now: now, automatic: false)
    }

    private mutating func enterSleep(now: TimeInterval, automatic: Bool) {
        guard sleepStarted == nil else { return }
        rest.sleep(now: now)
        if dogYawnEnabled { dogYawn.start(now: now) }
        sleepStarted = now
        reactionStarted = nil
        sleepingAutomatically = automatic
        duang.settle(now: now)
    }

    mutating func click(now: TimeInterval) {
        wake(now: now)
        duang.kick(now: now, strength: 0.75)
        reactionStarted = now
        blush.warm(now: now)
    }

    /// Global keyboard and pointer activity wake quietly and postpone the next nap.
    mutating func inputActivity(now: TimeInterval) { wake(now: now) }

    /// A local stroke warms the cheeks without restarting a full click bounce.
    mutating func stroke(now: TimeInterval, bounces: Bool) {
        wake(now: now)
        if bounces { duang.kick(now: now, strength: 0.22) }
        reactionStarted = now
        blush.warm(now: now)
    }

    /// Hovering warms the cheeks without interrupting sleep or the yawn timeline.
    mutating func sootheSleeping(now: TimeInterval) {
        guard sleepStarted != nil else { return }
        reactionStarted = now
        blush.warm(now: now)
    }

    mutating func beginDrag(now: TimeInterval) {
        wake(now: now)
        isDragging = true
        landingStarted = nil
        reactionStarted = nil
        duang.cancel()
    }

    mutating func endDrag(now: TimeInterval) {
        isDragging = false
        wake(now: now)
        landingStarted = now
        duang.kick(now: now, strength: 1)
    }

    mutating func cancelDrag(now: TimeInterval) {
        isDragging = false
        landingStarted = nil
        duang.cancel()
        wake(now: now)
    }

    func pose(now: TimeInterval, reducedMotion: Bool = false) -> PetPose {
        let resting = rest.pose(now: now)
        let decoration = dogYawnEnabled && !reducedMotion ? dogYawn.sleepDecorationAmount(now: now) : 1
        return PetPose(
            breath: reducedMotion ? 0 : sin(now * .pi * 2 / 4.6) * (1 + resting.settle * 0.35),
            sleep: resting.closed,
            sleepAge: resting.phaseAge,
            sleepBubble: resting.bubble * decoration,
            sleepLetters: resting.letters * decoration,
            sleepSettle: reducedMotion ? 0 : resting.settle,
            wakeStretch: reducedMotion ? 0 : resting.stretch,
            affection: blush.value(now: now),
            squash: reducedMotion ? 0 : duang.value(now: now),
            reducedMotion: reducedMotion,
            yawn: dogYawnEnabled && !reducedMotion ? dogYawn.pose(now: now) : nil
        )
    }

    static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Starts at rest and ends at rest; about three diminishing oscillations.
    static func landing(at age: TimeInterval) -> Double {
        guard age >= 0 else { return 0 }
        var spring = DuangMotion()
        spring.kick(now: 0, strength: 1)
        return spring.value(now: age)
    }

    func isAnimatingQuickly(now: TimeInterval) -> Bool {
        isDragging || duang.isMoving(now: now)
            || reactionStarted.map { now - $0 < 2.6 } == true
            || rest.isTransitioning(now: now)
            || (dogYawnEnabled && dogYawn.isAnimating(now: now))
    }
}

/// Blushing is a lingering emotion, independent of the per-click body reaction.
private struct BlushState {
    private static let warmup = 0.45
    private static let hold = 2.0
    private static let fade = 2.8
    private var transition: (started: TimeInterval, from: Double, target: Double)?

    mutating func warm(now: TimeInterval) {
        let current = value(now: now)
        let stillWarm = transition.map { now - $0.started < Self.warmup + Self.hold } ?? false
        let target: Double
        if stillWarm, let transition {
            target = min(1, max(current, transition.target) + 0.2)
        } else {
            target = min(1, current + 0.65)
        }
        // Capture the displayed level instead of restarting from transparent.
        transition = (now, current, target)
    }

    func value(now: TimeInterval) -> Double {
        guard let transition else { return 0 }
        let age = max(0, now - transition.started)
        if age < Self.warmup {
            let progress = PetMotion.smoothstep(age / Self.warmup)
            return transition.from + (transition.target - transition.from) * progress
        }
        let fadeProgress = min(1, max(0, (age - Self.warmup - Self.hold) / Self.fade))
        return transition.target * (1 - PetMotion.smoothstep(fadeProgress))
    }
}

struct PetPose {
    var breath: Double = 0
    var sleep: Double = 0
    var sleepAge: Double = 0
    var sleepBubble: Double = 0
    var sleepLetters: Double = 0
    var sleepSettle: Double = 0
    var wakeStretch: Double = 0
    var affection: Double = 0
    var hearts: [HeartPose] = []
    var squash: Double = 0
    var reducedMotion = false
    var yawn: DogYawnPose?
}

struct HeartPose {
    let x: Double
    let y: Double
    let scale: Double
    let rotation: Double
    let alpha: Double
    let sparkle: Double
}
