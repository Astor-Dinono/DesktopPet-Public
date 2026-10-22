import Foundation

enum InteractionEffect: Int, CaseIterable, Sendable {
    case heart, flower, paw, star
    var title: String { ["爱心", "小花", "小爪子", "小星星"][rawValue] }
    var baseScale: Double { 20 / [30.0, 29, 29.5, 27][rawValue] }
}

/// Only this four-bit preference is persisted; the last drawn kind stays in memory.
struct InteractionEffectSelection: Equatable {
    static let preferenceKey = "dog.interactionEffects"
    private(set) var mask: Int
    init(stored: Int? = nil) { mask = stored.map { $0 & 15 } ?? 1 }
    func contains(_ effect: InteractionEffect) -> Bool { mask & (1 << effect.rawValue) != 0 }
    mutating func toggle(_ effect: InteractionEffect) { mask ^= 1 << effect.rawValue }
}

struct InteractionEffectPicker {
    private(set) var last: InteractionEffect?
    mutating func next(in selection: InteractionEffectSelection,
                       choose: (Int) -> Int = { Int.random(in: 0..<$0) }) -> InteractionEffect? {
        let enabled = InteractionEffect.allCases.filter(selection.contains)
        guard !enabled.isEmpty else { return nil }
        let choices = enabled.count > 1 ? enabled.filter { $0 != last } : enabled
        let result = choices[choose(choices.count)]
        last = result
        return result
    }
}

struct ClickEffectPose {
    let pose: HeartPose
    let effect: InteractionEffect
}
