import XCTest
import CoreGraphics
@testable import DesktopPet

final class KeyCountTests: XCTestCase, @unchecked Sendable {
    func testOneDownCountsOnceAndNewDayKeepsLifetimeTotal() {
        var counts = KeyCounts(day: "2026-10-14")
        for _ in 0..<7 { counts.record(on: "2026-10-14") }
        XCTAssertEqual(counts.today, 7)
        XCTAssertEqual(counts.total, 7)
        counts.record(on: "2026-10-15")
        XCTAssertEqual(counts.today, 1)
        XCTAssertEqual(counts.total, 8)
        XCTAssertFalse(counts.refreshDay("2026-10-15"))
        XCTAssertTrue(counts.refreshDay("2026-10-16"))
        XCTAssertEqual(counts.today, 0)
        XCTAssertEqual(counts.total, 8)
    }

    func testLongHoldReleaseAndModifierOnlyEventsDoNotInflateCount() {
        let events: [(CGEventType, Bool)] = [
            (.keyDown, false), (.keyDown, true), (.keyDown, true),
            (.keyUp, false), (.flagsChanged, false), (.keyDown, false)
        ]
        var counts = KeyCounts(day: "2026-10-14")
        for (type, repeatFlag) in events where KeyPressPolicy.accepts(type, repeating: repeatFlag) {
            counts.record(on: "2026-10-14")
        }
        XCTAssertEqual(counts.today, 2)
        XCTAssertEqual(counts.total, 2)
    }

    func testInvalidCountsAreSanitizedAndCountersDoNotOverflow() {
        XCTAssertEqual(KeyCounts(day: "2026-10-14", today: -3, total: -7).total, 0)
        XCTAssertEqual(KeyCounts(day: "2026-10-14", today: 7, total: 3).total, 7)
        var counts = KeyCounts(day: "2026-10-14", today: Int.max, total: Int.max)
        counts.record(on: "2026-10-14")
        XCTAssertEqual(counts.today, Int.max)
        XCTAssertEqual(counts.total, Int.max)
    }

    func testKeyboardAndPointerDownsShareOneTotalWithoutCountingMotionOrReleases() {
        let events: [(CGEventType, Bool)] = [
            (.keyDown, false), (.keyDown, true), (.keyUp, false), (.flagsChanged, false),
            (.leftMouseDown, false), (.leftMouseUp, false),
            (.leftMouseDown, false), (.leftMouseUp, false), // double click counts twice
            (.rightMouseDown, false), (.otherMouseDown, false),
            (.mouseMoved, false), (.leftMouseDragged, false), (.scrollWheel, false)
        ]
        var counts = KeyCounts(day: "2026-10-14")
        for (type, repeating) in events {
            if KeyPressPolicy.accepts(type, repeating: repeating) || PointerClickPolicy.accepts(type) {
                counts.record(on: "2026-10-14")
            }
        }
        XCTAssertEqual(counts.total, 5)
        XCTAssertEqual(counts.today, 5)
    }

    func testLegacyCountsMergeOnceAndPreserveExistingTotals() async throws {
        try await MainActor.run {
            let name = "local.desktop-pet.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
            let key = try JSONEncoder().encode(KeyCounts(day: "2026-10-14", today: 7, total: 31))
            let pointer = try JSONEncoder().encode(KeyCounts(day: "2026-10-13", today: 8, total: 12))
            defaults.set(key, forKey: KeyCountStore.legacyKeys[0])
            defaults.set(pointer, forKey: KeyCountStore.legacyKeys[1])
            let store = KeyCountStore(defaults: defaults, clock: { date })
            XCTAssertEqual(store.counts.today, 7)
            XCTAssertEqual(store.counts.total, 43)
            XCTAssertEqual(defaults.data(forKey: KeyCountStore.legacyKeys[0]), key)
            store.recordPress()
            store.flush()
            let next = KeyCountStore(defaults: defaults, clock: { date })
            XCTAssertEqual(next.counts.today, 8)
            XCTAssertEqual(next.counts.total, 44)
            next.flush()
        }
    }

    func testMigrationSaturatesBothSameDayAggregates() async throws {
        try await MainActor.run {
            let name = "local.desktop-pet.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
            for key in KeyCountStore.legacyKeys {
                defaults.set(try JSONEncoder().encode(KeyCounts(day: "2026-10-14", today: Int.max, total: Int.max)), forKey: key)
            }
            let store = KeyCountStore(defaults: defaults, clock: { date })
            XCTAssertEqual(store.counts.today, Int.max)
            XCTAssertEqual(store.counts.total, Int.max)
            store.flush()
        }
    }

    func testOnlyAggregateFieldsAreEncoded() throws {
        let data = try JSONEncoder().encode(KeyCounts(day: "2026-10-14", today: 3, total: 8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["day", "today", "total"]))
    }

    func testPersistenceAndMidnightRolloverUseAnIsolatedPreferenceDomain() async {
        await MainActor.run {
            let name = "local.desktop-pet.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            var date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
            let store = KeyCountStore(defaults: defaults, clock: { date })
            store.recordPress()
            store.recordPress()
            XCTAssertNil(defaults.data(forKey: KeyCountStore.storageKey))
            store.flush()
            let restored = KeyCountStore(defaults: defaults, clock: { date })
            XCTAssertEqual(restored.counts.today, 2)
            XCTAssertEqual(restored.counts.total, 2)
            date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
            restored.refreshDay()
            XCTAssertEqual(restored.counts.today, 0)
            XCTAssertEqual(restored.counts.total, 2)
            restored.recordPress()
            restored.flush()
            let next = KeyCountStore(defaults: defaults, clock: { date })
            XCTAssertEqual(next.counts.today, 1)
            XCTAssertEqual(next.counts.total, 3)
            next.flush()
        }
    }

    func testMissingPermissionAndPauseNeverDeliverPressesOrPromptOnRefresh() async {
        await MainActor.run {
            let name = "local.desktop-pet.tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            var requests = 0
            var presses = 0
            var clicks = 0
            let monitor = InputMonitor(defaults: defaults, permissionCheck: { false }, permissionRequest: {
                requests += 1
                return false
            })
            monitor.onPress = { presses += 1 }
            monitor.onClick = { clicks += 1 }
            monitor.refresh()
            XCTAssertEqual(requests, 0)
            XCTAssertEqual(monitor.status, .off)
            monitor.receive(type: .keyDown, repeating: false)
            monitor.receive(type: .leftMouseDown, repeating: false)
            monitor.setEnabled(true)
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(monitor.status, .needsPermission)
            monitor.receive(type: .keyDown, repeating: false)
            monitor.receive(type: .rightMouseDown, repeating: false)
            monitor.refresh()
            monitor.refresh(retry: true)
            XCTAssertEqual(requests, 1)
            monitor.suspend()
            XCTAssertEqual(monitor.status, .sleeping)
            monitor.receive(type: .keyDown, repeating: false)
            monitor.receive(type: .otherMouseDown, repeating: false)
            monitor.resume()
            monitor.setEnabled(false)
            XCTAssertEqual(monitor.status, .off)
            XCTAssertFalse(defaults.bool(forKey: "keyboard.countingEnabled"))
            XCTAssertEqual(presses, 0)
            XCTAssertEqual(clicks, 0)
            monitor.stop()
        }
    }

    func testGlobalInputWakesWithoutHeartsBlushOrClickSquashAndDoesNotRestartWake() {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 0)
        let asleep = motion.pose(now: 3)
        motion.inputActivity(now: 3)
        XCTAssertEqual(motion.pose(now: 3).sleep, asleep.sleep)
        motion.inputActivity(now: 3.2)
        motion.inputActivity(now: 3.4)
        let awake = motion.pose(now: 4.2)
        XCTAssertEqual(awake.sleep, 0)
        XCTAssertEqual(awake.sleepBubble, 0)
        XCTAssertEqual(awake.affection, 0)
        XCTAssertEqual(awake.squash, 0)
        XCTAssertNil(motion.reactionStarted)
        XCTAssertNil(motion.landingStarted)
    }

    func testGlobalClicksPostponeSleepUntilActivityStops() {
        var motion = PetMotion(now: 0)
        for time in [30.0, 60, 90] {
            motion.inputActivity(now: time)
            motion.advance(now: time)
            XCTAssertNil(motion.sleepStarted)
        }
        motion.advance(now: 90 + PetMotion.sleepDelay - 0.01)
        XCTAssertNil(motion.sleepStarted)
        motion.advance(now: 90 + PetMotion.sleepDelay)
        XCTAssertEqual(motion.sleepStarted, 90 + PetMotion.sleepDelay)
        motion.inputActivity(now: 90 + PetMotion.sleepDelay + 5)
        XCTAssertNil(motion.sleepStarted)
        XCTAssertEqual(motion.lastInteraction, 90 + PetMotion.sleepDelay + 5)
        XCTAssertNil(motion.reactionStarted)
    }
}
