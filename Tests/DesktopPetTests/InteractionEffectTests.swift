import AppKit
import XCTest
@testable import DesktopPet

final class InteractionEffectTests: XCTestCase, @unchecked Sendable {
    func testMissingPreferenceKeepsHeartAndExplicitZeroStaysOffAfterReload() throws {
        XCTAssertEqual(InteractionEffectSelection().mask, 1)
        let name = "DesktopPet.EffectTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var selection = InteractionEffectSelection()
        selection.toggle(.heart)
        defaults.set(selection.mask, forKey: InteractionEffectSelection.preferenceKey)
        XCTAssertEqual(InteractionEffectSelection(stored: defaults.object(forKey: InteractionEffectSelection.preferenceKey) as? Int).mask, 0)
        selection.toggle(.paw); selection.toggle(.star)
        defaults.set(selection.mask, forKey: InteractionEffectSelection.preferenceKey)
        XCTAssertEqual(InteractionEffectSelection(stored: defaults.object(forKey: InteractionEffectSelection.preferenceKey) as? Int), selection)
    }

    func testAllSixteenCombinationsOnlyChooseEnabledKindsAndAvoidImmediateRepeats() {
        for mask in 0..<16 {
            let selection = InteractionEffectSelection(stored: mask)
            var picker = InteractionEffectPicker()
            var previous: InteractionEffect?
            let enabled = InteractionEffect.allCases.filter(selection.contains)
            for index in 0..<100 {
                let result = picker.next(in: selection, choose: { index % $0 })
                if let result {
                    XCTAssertTrue(enabled.contains(result))
                    if enabled.count > 1 { XCTAssertNotEqual(result, previous) }
                } else { XCTAssertTrue(enabled.isEmpty) }
                previous = result
            }
            for index in enabled.indices {
                var fresh = InteractionEffectPicker()
                XCTAssertEqual(fresh.next(in: selection, choose: { _ in index }), enabled[index])
            }
        }
    }

    func testDisabledSelectionDoesNotConsumeRandomnessAndChangingItIsImmediate() {
        var picker = InteractionEffectPicker()
        XCTAssertNil(picker.next(in: InteractionEffectSelection(stored: 0), choose: { _ in XCTFail("Disabled effects must not draw"); return 0 }))
        XCTAssertEqual(picker.next(in: InteractionEffectSelection(stored: 8)), .star)
        XCTAssertEqual(picker.next(in: InteractionEffectSelection(stored: 4)), .paw)
        XCTAssertEqual(picker.next(in: InteractionEffectSelection(stored: 4)), .paw)
        XCTAssertEqual(InteractionEffectSelection(stored: 0xF3).mask, 3)
    }

    func testEveryKindStartsAtTheClickStaysBoundedAndNaturallyExpires() throws {
        for effect in InteractionEffect.allCases {
            let particle = ClickHeart(origin: CGPoint(x: -80, y: 40), started: 0, variant: 0, effect: effect)
            let initial = try XCTUnwrap(particle.pose(now: 0))
            XCTAssertEqual(initial.x, -80); XCTAssertEqual(initial.y, 40); XCTAssertEqual(initial.alpha, 0)
            for step in 0..<240 {
                let pose = try XCTUnwrap(particle.pose(now: Double(step) / 120))
                XCTAssertTrue((0...1).contains(pose.alpha))
                XCTAssertTrue((0...1).contains(pose.scale))
                XCTAssertTrue((-83 ... -77).contains(pose.x))
                XCTAssertTrue((40...70).contains(pose.y))
                let still = try XCTUnwrap(particle.pose(now: Double(step) / 120, reducedMotion: true))
                XCTAssertEqual(still.x, -80); XCTAssertEqual(still.y, 40)
                XCTAssertEqual(still.scale, effect.baseScale); XCTAssertEqual(still.rotation, 0)
            }
            XCTAssertNil(particle.pose(now: 2))
        }
        let star = ClickHeart(origin: .zero, started: 0, variant: 0, effect: .star)
        XCTAssertEqual(try XCTUnwrap(star.pose(now: 0.13)).scale, InteractionEffect.star.baseScale * 1.16, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(star.pose(now: 0.32)).scale, InteractionEffect.star.baseScale, accuracy: 1e-12)
    }

    func testMixingKindsDoesNotMoveRestartOrReclassifyEarlierParticles() throws {
        var motion = ClickHeartMotion()
        motion.emit(at: CGPoint(x: 4, y: 5), now: 0, effect: .star)
        let before = try XCTUnwrap(motion.poses(now: 0.4).first)
        for index in 1...4 { motion.emit(at: .zero, now: Double(index) * 0.1, effect: .paw) }
        let first = try XCTUnwrap(motion.effectPoses(now: 0.4).first)
        XCTAssertEqual(first.effect, .star)
        XCTAssertEqual(first.pose.x, before.x); XCTAssertEqual(first.pose.y, before.y)
        XCTAssertEqual(first.pose.scale, before.scale)
        motion.advance(now: 2.31)
        XCTAssertEqual(motion.hearts.count, 1)
        XCTAssertEqual(motion.hearts.first?.effect, .paw)
        motion.advance(now: 3)
        XCTAssertTrue(motion.hearts.isEmpty)
    }
}
