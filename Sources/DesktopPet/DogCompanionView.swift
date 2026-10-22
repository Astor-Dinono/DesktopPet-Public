import AppKit

/// Keep the counter upright while the dog faces any of the four edges.
@MainActor
final class DogCompanionView: NSView {
    static let footerHeight: CGFloat = 24
    let pet: PetView
    private let badge = NSTextField(labelWithString: "0")
    private var hoverArea: NSTrackingArea?
    private var hovering = false
    var alwaysShowCount = false { didSet { updateVisibility(); (window as? PetPanel)?.refreshPointerRouting() } }
    var counterAboveDog = false { didSet { needsLayout = true } }
    var orientation: DogOrientation = .bottom { didSet { pet.orientation = orientation; needsLayout = true } }
    var topbarHeight: CGFloat? {
        didSet { pet.topbarHeight = topbarHeight; needsLayout = true; updateVisibility(animated: false) }
    }
    var scale: Double { didSet { pet.topbarScale = scale; needsLayout = true } }
    var onCounterWidthChanged: (() -> Void)?
    var turnFrames: (pet: NSRect, badge: NSRect)? { didSet { needsLayout = true } }
    var badgeFrame: NSRect { badge.frame }
    var counterWidth: CGFloat { max(30, badge.intrinsicContentSize.width + 14) }
    var dogOffsetY: CGFloat { layoutGeometry.petFrame.minY }
    var layoutGeometry: DogLayout {
        DogLayout(scale: scale, orientation: orientation, counterInside: counterAboveDog, badgeWidth: counterWidth, topbarHeight: topbarHeight)
    }

    static func size(scale: Double, counterAboveDog: Bool = false, orientation: DogOrientation = .bottom,
                     badgeWidth: CGFloat = 30) -> NSSize {
        DogLayout(scale: scale, orientation: orientation, counterInside: counterAboveDog, badgeWidth: badgeWidth).size
    }

    init(pet: PetView, scale: Double) {
        self.pet = pet
        self.scale = scale
        pet.topbarScale = scale
        super.init(frame: NSRect(origin: .zero, size: Self.size(scale: scale)))
        autoresizingMask = [.width, .height]
        addSubview(pet)
        badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        badge.alignment = .center
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 6
        badge.layer?.borderWidth = 0.5
        badge.setAccessibilityLabel("点击次数")
        badge.setAccessibilityRole(.staticText)
        badge.alphaValue = 0
        badge.setAccessibilityHidden(true)
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }

    func updateCount(_ total: Int) {
        let oldSize = layoutGeometry.size
        badge.stringValue = total.formatted(.number.grouping(.never))
        badge.setAccessibilityValue(badge.stringValue)
        needsLayout = true
        if oldSize != layoutGeometry.size { onCounterWidthChanged?() }
    }

    override func layout() {
        super.layout()
        pet.frame = turnFrames?.pet ?? layoutGeometry.petFrame
        badge.frame = turnFrames?.badge ?? layoutGeometry.badgeFrame
        badge.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        badge.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        if let window {
            hovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else { hovering = false }
        updateVisibility(animated: false)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; updateVisibility() }
    override func mouseExited(with event: NSEvent) { hovering = false; updateVisibility() }

    func updatePointer(at point: NSPoint) {
        // Hover can reveal the badge without making any transparent padding clickable.
        let inside = bounds.contains(point)
        guard hovering != inside else { return }
        hovering = inside
        updateVisibility()
    }

    func containsInteraction(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        if pet.containsInteraction(pet.convert(point, from: self)) { return true }
        return badge.alphaValue >= 0.01 && NSBezierPath(roundedRect: badge.frame,
            xRadius: 6, yRadius: 6).contains(point)
    }

    private func updateVisibility(animated: Bool = true) {
        let show = topbarHeight == nil && (alwaysShowCount || hovering)
        badge.setAccessibilityHidden(!show)
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                badge.animator().alphaValue = show ? 1 : 0
            }
        } else { badge.alphaValue = show ? 1 : 0 }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsInteraction(convert(point, from: superview)) else { return nil }
        let target = super.hitTest(point)
        return target === self || (target === badge && badge.alphaValue < 0.01) ? nil : target
    }
}

/// Anchor the drawn baseline, not the transparent window or the counter footer.
@MainActor
struct DogWindowPlacement {
    let frame: NSRect
    let counterAboveDog: Bool

    init(x: CGFloat, baseline: CGFloat, scale: Double, visibleFrame area: NSRect) {
        self.init(anchor: NSPoint(x: x + DogRenderer.canvas.width * scale / 2, y: baseline),
                  scale: scale, orientation: .bottom, visibleFrame: area)
    }

    init(anchor: NSPoint, scale: Double, orientation: DogOrientation, badgeWidth: CGFloat = 30,
         visibleFrame area: NSRect, allowsPartialVisibility: Bool = false) {
        let depth = DogRenderer.canvas.height * scale
        let edge = 1 + DogRenderer.baselineY * scale
        var point = anchor
        if allowsPartialVisibility {
            point.x = min(area.maxX, max(area.minX, point.x))
            point.y = min(area.maxY, max(area.minY, point.y))
        }
        switch orientation {
        case .bottom:
            if !allowsPartialVisibility { point.y = min(max(point.y, area.minY), max(area.minY, area.maxY - depth + edge)) }
            counterAboveDog = point.y - edge - DogCompanionView.footerHeight < area.minY
        case .top:
            if !allowsPartialVisibility { point.y = max(min(point.y, area.maxY), min(area.maxY, area.minY + depth - edge)) }
            counterAboveDog = point.y + edge + DogCompanionView.footerHeight > area.maxY
        case .left:
            if !allowsPartialVisibility { point.x = min(max(point.x, area.minX), max(area.minX, area.maxX - depth + edge)) }
            counterAboveDog = false
        case .right:
            if !allowsPartialVisibility { point.x = max(min(point.x, area.maxX), min(area.maxX, area.minX + depth - edge)) }
            counterAboveDog = false
        }
        let layout = DogLayout(scale: scale, orientation: orientation,
                               counterInside: counterAboveDog, badgeWidth: badgeWidth)
        var origin = NSPoint(x: point.x - layout.baselineAnchor.x, y: point.y - layout.baselineAnchor.y)
        // Only clamp along the baseline: the tiny ink inset can extend past the attached edge.
        if !allowsPartialVisibility, orientation.isVertical {
            origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - layout.size.height))
        } else if !allowsPartialVisibility {
            origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - layout.size.width))
        }
        frame = NSRect(origin: origin, size: layout.size)
    }
}
