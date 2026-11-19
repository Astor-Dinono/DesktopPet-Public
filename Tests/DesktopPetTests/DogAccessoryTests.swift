import AppKit
import XCTest
@testable import DesktopPet

final class DogAccessoryTests: XCTestCase, @unchecked Sendable {
    func testMissingAndUnknownPreferencesKeepTheOriginalDog() {
        XCTAssertEqual(DogAccessory(storedValue: nil), .none)
        XCTAssertEqual(DogAccessory(storedValue: -1), .none)
        XCTAssertEqual(DogAccessory(storedValue: 99), .none)
        for choice in DogAccessory.allCases {
            XCTAssertEqual(DogAccessory(storedValue: choice.rawValue), choice)
        }
    }

    @MainActor private func image(_ pose: PetPose, accessory: DogAccessory?, topbar: Bool = false) throws -> (Data, [UInt8]) {
        let scale = topbar ? DogTopbarRenderer.tinyScale : 0.62
        let size = topbar ? DogTopbarRenderer.drawingSize(scale: scale, bandHeight: 38)
            : NSSize(width: 260 * scale, height: 148 * scale)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(size.width * 2)), pixelsHigh: Int(ceil(size.height * 2)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pointer = try XCTUnwrap(bitmap.bitmapData)
        pointer.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.clear(CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        context.scaleBy(x: 2, y: 2)
        if topbar {
            if let accessory {
                DogTopbarRenderer.draw(in: context, size: size, pose: pose,
                    tail: TailPose(angle: 0, bend: 0), blink: 0, tailSize: .small, accessory: accessory)
            } else {
                DogTopbarRenderer.draw(in: context, size: size, pose: pose,
                    tail: TailPose(angle: 0, bend: 0), blink: 0, tailSize: .small)
            }
        } else if let accessory {
            DogRenderer.draw(in: context, size: size, pose: pose, accessory: accessory)
        } else {
            DogRenderer.draw(in: context, size: size, pose: pose)
        }
        NSGraphicsContext.restoreGraphicsState()
        let alphaIndex = bitmap.bitmapFormat.contains(.alphaFirst) ? 0 : 3
        let alpha = (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).map { x in pointer[y * bitmap.bytesPerRow + x * 4 + alphaIndex] }
        }
        return (Data(bytes: pointer, count: bitmap.bytesPerRow * bitmap.pixelsHigh), alpha)
    }

    func testNoneIsPixelIdenticalAndAccessoriesKeepTheOpaqueSilhouette() async throws {
        try await MainActor.run {
            let poses = [PetPose(), PetPose(breath: 1.35, squash: 0.2),
                PetPose(breath: -1.35, sleep: 1, sleepSettle: 1),
                PetPose(yawn: DogYawnPose(time: 1.45, weight: 1)),
                PetPose(yawn: DogYawnPose(time: 1.45, weight: 0.45))]
            for topbar in [false, true] { for pose in poses {
                let original = try image(pose, accessory: nil, topbar: topbar)
                XCTAssertEqual(original.0, try image(pose, accessory: DogAccessory.none, topbar: topbar).0)
                for accessory in [DogAccessory.scarf, .collar] {
                    let decorated = try image(pose, accessory: accessory, topbar: topbar)
                    XCTAssertNotEqual(original.0, decorated.0, "The optional detail must remain visible")
                    XCTAssertEqual(original.1, decorated.1, "An accessory must not expand or cut the original silhouette")
                }
            }}
        }
    }

    func testPreviewInheritsAndUpdatesTheSingleAccessoryChoice() async {
        await MainActor.run {
            _ = NSApplication.shared
            let desktop = PetView(frame: NSRect(x: 0, y: 0, width: 162, height: 92))
            desktop.accessory = .collar
            let preview = DogPreviewController(desktopDog: desktop, autoNap: .threeMinutes,
                onPet: { _ in false }, onEffectsFrame: {}, onEffectsCleared: {},
                onPinDesktop: {}, onHideDesktop: {})
            defer { preview.stop(); preview.close(); desktop.stop() }
            @MainActor func dogs(_ view: NSView) -> [PetView] {
                if let dog = view as? PetView { return [dog] }
                var result: [PetView] = []
                let children = view.subviews
                for child in children { result.append(contentsOf: dogs(child)) }
                return result
            }
            let pets = preview.window?.contentView.map(dogs) ?? []
            XCTAssertEqual(pets.count, 2)
            let inherited = pets.allSatisfy { $0.accessory == .collar }
            XCTAssertTrue(inherited)
            preview.setAccessory(.scarf)
            let changed = pets.allSatisfy { $0.accessory == .scarf }
            XCTAssertTrue(changed)
            preview.setAccessory(.none)
            let cleared = pets.allSatisfy { $0.accessory == .none }
            XCTAssertTrue(cleared)
        }
    }
}
