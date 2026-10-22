import AppKit

/// Menu-band geometry for system slots and user-chosen horizontal positions.
struct DogTopbarPlacement {
    static let width: CGFloat = 148
    static let baselineInset: CGFloat = 1.8
    static let detachDistance: CGFloat = 14
    static let dropDistance: CGFloat = 12

    /// Use the released head's geometry as well as the event point; grabbing
    /// a low part of the dog must not leave a head inside the menu band unaligned.
    static func dropFrame(pointer: CGPoint, startedInTopbar: Bool,
                          screen: CGRect, topInset: CGFloat, menuHeight: CGFloat,
                          left: CGRect?, right: CGRect?, drawingSize: CGSize? = nil,
                          dogFrame: CGRect? = nil, centerX: CGFloat? = nil, attachmentY: CGFloat? = nil) -> CGRect? {
        let height = max(22, topInset > 0 ? topInset : menuHeight)
        guard pointer.x.isFinite, pointer.y.isFinite,
              pointer.x >= screen.minX, pointer.x <= screen.maxX else { return nil }
        // Leaving the strip must not immediately snap back just because the
        // head still overlaps it. But returning the pointer to the actual band
        // within the same gesture is an intentional re-entry, not an exit.
        if startedInTopbar, !(screen.maxY - height...screen.maxY).contains(pointer.y) { return nil }
        let nearPointer = pointer.y >= screen.maxY - height - dropDistance && pointer.y <= screen.maxY
        let band = CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        let overlap = dogFrame?.intersection(band) ?? .null
        guard nearPointer || (!overlap.isNull && overlap.width > 0 && overlap.height > 0) else { return nil }
        return freeFrame(centerX: centerX ?? pointer.x, screen: screen, topInset: topInset,
                         menuHeight: menuHeight, left: left, right: right, drawingSize: drawingSize, attachmentY: attachmentY)
    }

    static func shouldDetach(pointerY: CGFloat, frame: CGRect, pressedY: CGFloat? = nil) -> Bool {
        let threshold = min(frame.minY - detachDistance, (pressedY ?? frame.minY) - detachDistance)
        return pointerY < threshold
    }

    /// Manual placement uses only display geometry, not other apps' menus.
    /// Choose the nearest whole visible segment so the notch never clips the dog.
    static func freeFrame(centerX: CGFloat, screen: CGRect, topInset: CGFloat, menuHeight: CGFloat,
                          left: CGRect?, right: CGRect?, drawingSize: CGSize? = nil, attachmentY: CGFloat? = nil) -> CGRect? {
        guard centerX.isFinite else { return nil }
        let height = max(22, topInset > 0 ? topInset : menuHeight)
        let band = CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        let size = drawingSize ?? CGSize(width: width, height: height)
        guard size.width.isFinite, size.height.isFinite, size.width > 0,
              size.height >= height, size.height <= screen.height else { return nil }
        let auxiliary = [left, right].compactMap { $0 }
        let areas = auxiliary.isEmpty ? [band] : auxiliary.map { $0.intersection(band) }
        return areas.compactMap { area -> CGRect? in
            guard !area.isNull, area.width >= size.width, area.height >= height - 0.5 else { return nil }
            let x = min(area.maxX - size.width, max(area.minX, centerX - size.width / 2))
            return CGRect(x: x, y: (attachmentY ?? band.minY) - baselineInset, width: size.width, height: size.height)
        }.min { abs($0.midX - centerX) < abs($1.midX - centerX) }
    }

    static func frame(slot: CGRect, screen: CGRect, topInset: CGFloat, menuHeight: CGFloat,
                      left: CGRect?, right: CGRect?, drawingSize: CGSize? = nil, attachmentY: CGFloat? = nil) -> CGRect? {
        let height = max(22, topInset > 0 ? topInset : menuHeight)
        let band = CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
        let size = drawingSize ?? CGSize(width: width, height: height)
        guard slot.intersects(band), slot.width >= size.width - 1,
              size.width.isFinite, size.height.isFinite, size.width > 0,
              size.height >= height, size.height <= screen.height else { return nil }
        let footprint = CGRect(x: slot.midX - size.width / 2, y: band.minY, width: size.width, height: height)
        let area = [left, right].compactMap { $0 }
        if !area.isEmpty {
            guard area.contains(where: { $0.insetBy(dx: -0.5, dy: -0.5).contains(footprint) }) else { return nil }
        } else if !band.contains(footprint) { return nil }
        return CGRect(x: footprint.minX, y: (attachmentY ?? band.minY) - baselineInset, width: size.width, height: size.height)
    }
}

/// A single user-chosen position, never a movement history.
struct DogTopbarPosition: Equatable {
    static let fractionKey = "dog.topbarXFraction"
    static let displayKey = "dog.topbarDisplay"
    let fraction: Double
    let displayID: UInt32

    static func load(from defaults: UserDefaults) -> Self? {
        guard let fraction = defaults.object(forKey: fractionKey) as? NSNumber,
              let display = defaults.object(forKey: displayKey) as? NSNumber,
              fraction.doubleValue.isFinite, (0...1).contains(fraction.doubleValue),
              display.doubleValue >= 0, display.doubleValue <= Double(UInt32.max) else { return nil }
        return Self(fraction: fraction.doubleValue, displayID: display.uint32Value)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(fraction, forKey: Self.fractionKey)
        defaults.set(displayID, forKey: Self.displayKey)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: fractionKey)
        defaults.removeObject(forKey: displayKey)
    }
}
