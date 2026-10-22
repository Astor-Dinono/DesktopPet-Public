import Foundation

/// Only current-day and lifetime aggregates. Never stores individual input events.
struct KeyCounts: Codable, Equatable {
    private(set) var day: String
    private(set) var today: Int
    private(set) var total: Int

    init(day: String, today: Int = 0, total: Int = 0) {
        self.day = day
        self.today = max(0, today)
        self.total = max(self.today, total)
    }

    @discardableResult
    mutating func refreshDay(_ current: String) -> Bool {
        guard day != current else { return false }
        day = current
        today = 0
        return true
    }

    mutating func record(on current: String) {
        refreshDay(current)
        if today < Int.max { today += 1 }
        if total < Int.max { total += 1 }
    }
}

@MainActor
final class KeyCountStore {
    static let storageKey = "input.aggregate.v1"
    static let legacyKeys = ["keyboard.aggregate.v1", "pointer.aggregate.v1"]
    private let defaults: UserDefaults
    private let clock: () -> Date
    private var flushTimer: Timer?
    private var dirty = false
    private(set) var counts: KeyCounts
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        let day = Self.day(for: clock())
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(KeyCounts.self, from: data) {
            counts = KeyCounts(day: saved.day, today: saved.today, total: saved.total)
        } else {
            counts = KeyCounts(day: day)
            // Import once into the unified aggregate. Keep legacy preferences intact.
            var imported = false
            for key in Self.legacyKeys {
                guard let data = defaults.data(forKey: key),
                      let saved = try? JSONDecoder().decode(KeyCounts.self, from: data) else { continue }
                let clean = KeyCounts(day: saved.day, today: saved.today, total: saved.total)
                func add(_ a: Int, _ b: Int) -> Int { a > Int.max - b ? Int.max : a + b }
                counts = KeyCounts(day: day,
                    today: add(counts.today, clean.day == day ? clean.today : 0),
                    total: add(counts.total, clean.total))
                imported = true
            }
            if imported { dirty = true; flush() }
        }
        if counts.refreshDay(day) { changed() }
    }

    func recordPress() {
        counts.record(on: Self.day(for: clock()))
        changed()
    }

    func refreshDay() {
        if counts.refreshDay(Self.day(for: clock())) { changed() }
    }

    private static func day(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func changed() {
        dirty = true
        onChange?()
        guard flushTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    func flush() {
        flushTimer?.invalidate()
        flushTimer = nil
        guard dirty, let data = try? JSONEncoder().encode(counts) else { return }
        defaults.set(data, forKey: Self.storageKey)
        dirty = false
    }
}
