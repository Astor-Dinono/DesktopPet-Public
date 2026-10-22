import Foundation

enum AutoNap: Int, CaseIterable, Sendable {
    case off = 0
    case thirtySeconds = 30
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300

    static let defaultValue = AutoNap.threeMinutes
    static let preferenceKey = "dog.autoNapDelay"

    init(storedValue: Int?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? Self.defaultValue
    }

    var delay: TimeInterval? { self == .off ? nil : Double(rawValue) }
    var title: String {
        switch self {
        case .off: return "关闭"
        case .thirtySeconds: return "30 秒"
        case .oneMinute: return "1 分钟"
        case .threeMinutes: return "3 分钟"
        case .fiveMinutes: return "5 分钟"
        }
    }
}
