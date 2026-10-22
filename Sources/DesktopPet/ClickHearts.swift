import AppKit

/// Local interaction positions exist only for the lifetime of these bounded visual effects.
struct ClickHeart {
    static let lifetime: TimeInterval = 2
    let origin: CGPoint
    let started: TimeInterval
    let variant: Int
    let effect: InteractionEffect

    init(origin: CGPoint, started: TimeInterval, variant: Int, effect: InteractionEffect = .heart) {
        self.origin = origin; self.started = started; self.variant = variant; self.effect = effect
    }

    func pose(now: TimeInterval, reducedMotion: Bool = false) -> HeartPose? {
        let age = now - started
        guard age >= 0, age < Self.lifetime else { return nil }
        let progress = age / Self.lifetime
        func ease(_ value: Double) -> Double { PetMotion.smoothstep(min(1, max(0, value))) }
        let idea = effect == .star
        var pop = reducedMotion ? 1 : 0.82 + 0.18 * ease(age / 0.22)
        if idea && !reducedMotion {
            pop = age <= 0.13 ? 0.42 + 0.74 * ease(age / 0.13)
                : 1 + 0.16 * (1 - ease((age - 0.13) / 0.19))
        }
        let scale = effect.baseScale * pop
        let drift = variant.isMultiple(of: 2) ? -3.0 : 3.0
        let alpha = PetMotion.smoothstep(min(1, age / (idea ? 0.055 : 0.12)))
            * (1 - PetMotion.smoothstep(min(1, max(0, (age - 0.7) / 1.3))))
        return HeartPose(x: origin.x + (reducedMotion ? 0 : sin(progress * .pi) * drift),
            y: origin.y + (reducedMotion ? 0 : progress * 30 * (idea ? ease(age / 0.18) : 1)),
            scale: scale, rotation: reducedMotion ? 0 : sin(progress * .pi) * 0.07,
            alpha: alpha, sparkle: 0.8 + sin(age * 4) * 0.15)
    }
}

struct ClickHeartMotion {
    private(set) var hearts: [ClickHeart] = []
    private var variant = 0

    mutating func emit(at point: CGPoint, now: TimeInterval, effect: InteractionEffect = .heart) {
        advance(now: now)
        // Every click gets its own fresh heart; replace the oldest when at capacity.
        if hearts.count >= 6 { hearts.removeFirst() }
        hearts.append(ClickHeart(origin: point, started: now, variant: variant, effect: effect))
        variant = (variant + 1) % 6
    }

    mutating func advance(now: TimeInterval) { hearts.removeAll { now - $0.started >= ClickHeart.lifetime } }
    mutating func clear() { hearts.removeAll() }
    func poses(now: TimeInterval, reducedMotion: Bool = false) -> [HeartPose] {
        hearts.compactMap { $0.pose(now: now, reducedMotion: reducedMotion) }
    }
    func effectPoses(now: TimeInterval, reducedMotion: Bool = false) -> [ClickEffectPose] {
        hearts.compactMap { heart in
            heart.pose(now: now, reducedMotion: reducedMotion).map { ClickEffectPose(pose: $0, effect: heart.effect) }
        }
    }

    var frame: CGRect {
        hearts.reduce(CGRect.null) { area, heart in
            area.union(CGRect(x: heart.origin.x - 18, y: heart.origin.y - 18, width: 36, height: 66))
        }.integral
    }
}

/// A passive overlay allows hearts to rise vertically even when the dog is rotated or pinned.
/// Its animation is advanced by existing visible pet clocks; it has no timer or input monitor.
@MainActor
final class ClickHeartOverlay {
    private let panel: PetPanel
    private let view = ClickHeartView(frame: .zero)
    private var motion = ClickHeartMotion()
    private var lastFrame: TimeInterval = -.infinity
    private let defaults: UserDefaults
    private(set) var selection: InteractionEffectSelection
    private var picker = InteractionEffectPicker()

    func setTopbarMode(_ enabled: Bool) {
        panel.level = NSWindow.Level(rawValue: (enabled ? NSWindow.Level.statusBar.rawValue : NSWindow.Level.floating.rawValue) + (enabled ? 2 : 1))
    }

    func toggle(_ effect: InteractionEffect) {
        selection.toggle(effect)
        defaults.set(selection.mask, forKey: InteractionEffectSelection.preferenceKey)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = InteractionEffectSelection(stored: defaults.object(forKey: InteractionEffectSelection.preferenceKey) as? Int)
        _ = InteractionEffectArtwork.shapes
        panel = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        panel.title = "互动特效"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Selection or dragging can raise the dog within its floating level.
        // Keep effects above that whole level without reordering either window every frame.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.hidesOnDeactivate = false
        // Hearts belong to the stationary companion, including while showing the desktop.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.contentView = view
        panel.setAccessibilityElement(false)
        view.setAccessibilityHidden(true)
    }

    @discardableResult func emit(at point: NSPoint) -> Bool {
        guard let effect = picker.next(in: selection) else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        motion.emit(at: point, now: now, effect: effect)
        lastFrame = -.infinity
        advance()
        panel.orderFrontRegardless()
        return true
    }

    func advance() {
        guard !motion.hearts.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 1 / 90 else { return }
        lastFrame = now
        motion.advance(now: now)
        guard !motion.hearts.isEmpty else { clear(); return }
        let frame = motion.frame
        if panel.frame != frame { panel.setPetFrame(frame) }
        let poses = motion.effectPoses(now: now, reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        view.poses = poses.map { item in
            let p = item.pose
            return ClickEffectPose(pose: HeartPose(x: p.x - frame.minX, y: p.y - frame.minY, scale: p.scale,
                      rotation: p.rotation, alpha: p.alpha, sparkle: p.sparkle), effect: item.effect)
        }
        view.needsDisplay = true
    }

    func clear() {
        motion.clear()
        view.poses = []
        panel.orderOut(nil)
        lastFrame = -.infinity
    }

    static func renderPreview(age: TimeInterval, to url: URL, effect: InteractionEffect = .heart) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 240,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        graphics.cgContext.scaleBy(x: 2, y: 2)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 160, height: 120).fill()
        let heart = ClickHeart(origin: NSPoint(x: 80, y: 40), started: 0, variant: 0, effect: effect)
        InteractionEffectRenderer.draw(heart.pose(now: age).map { [ClickEffectPose(pose: $0, effect: effect)] } ?? [], in: graphics.cgContext)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}

@MainActor
private final class ClickHeartView: NSView {
    var poses: [ClickEffectPose] = []
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        InteractionEffectRenderer.draw(poses, in: context)
    }
}
