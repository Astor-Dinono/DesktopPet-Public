import AppKit

/// Geometry only: a fixed-size hint never covers the dog or its visible counter.
enum DogInteractionHintLayout {
    static let size = NSSize(width: 210, height: 104)
    static let gap: CGFloat = 10

    static func frame(anchor: NSRect, obstacle: NSRect?, screen: NSRect) -> NSRect? {
        func finite(_ rect: NSRect) -> Bool {
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                && rect.width > 0 && rect.height > 0
        }
        guard finite(anchor), finite(screen), screen.width >= size.width, screen.height >= size.height else { return nil }
        let obstacles = [anchor] + (obstacle.flatMap { finite($0) ? $0 : nil }.map { [$0] } ?? [])
        let envelope = obstacles.reduce(anchor) { $0.union($1) }
        func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            min(upper, max(lower, value))
        }
        // Clamp only the orthogonal axis. An unavailable above position must
        // move below/alongside, rather than being clamped through the character.
        func candidates(around target: NSRect) -> [NSRect] {
            let x = clamp(target.midX - size.width / 2, screen.minX, screen.maxX - size.width)
            let y = clamp(target.midY - size.height / 2, screen.minY, screen.maxY - size.height)
            return [
                NSRect(x: x, y: target.maxY + gap, width: size.width, height: size.height),
                NSRect(x: x, y: target.minY - gap - size.height, width: size.width, height: size.height),
                NSRect(x: target.minX - gap - size.width, y: y, width: size.width, height: size.height),
                NSRect(x: target.maxX + gap, y: y, width: size.width, height: size.height)
            ]
        }
        // The envelope also lets an above-counter bubble remain near the dog.
        let options = candidates(around: envelope) + candidates(around: anchor)
        return options.first { candidate in
            screen.contains(candidate)
                && !obstacles.contains { candidate.intersects($0.insetBy(dx: -gap / 2, dy: -gap / 2)) }
        }
    }
}

/// A single-session hint. Only the explicit “不再提示” action writes a preference.
@MainActor
final class DogInteractionHint: NSObject {
    static let disabledKey = "dog.interactionHintDisabled"
    private let defaults: UserDefaults
    private var disabled: Bool
    private var dismissedThisSession = false
    private(set) var isRequested = false
    private var presentation: Presentation?
    private var panel: DogInteractionHintPanel?
    private var content: DogInteractionHintContentView?
    private var lastFrame: NSRect?
    private var lastLevel: NSWindow.Level?
    private var lastOwnerNumber: Int?
    private var lastLocked: Bool?
    private var layoutUnavailable = false

    private struct Presentation {
        let anchor: NSRect
        let obstacle: NSRect?
        let screen: NSRect
        let visible: Bool
        let level: NSWindow.Level
        let positionLocked: Bool
        weak var owner: NSWindow?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        disabled = defaults.bool(forKey: Self.disabledKey)
        super.init()
    }

    func requestAutomatically() {
        guard !disabled, !dismissedThisSession else { return }
        isRequested = true
    }

    func showManually() {
        isRequested = true
    }

    func dismiss(permanently: Bool) {
        isRequested = false
        dismissedThisSession = true
        if permanently, !disabled {
            disabled = true
            defaults.set(true, forKey: Self.disabledKey)
        }
        hide()
    }

    /// A hidden dog or temporarily insufficient room must not consume the hint.
    func hide() {
        if panel?.isVisible == true { panel?.orderOut(nil) }
    }

    func update(anchor: NSRect, obstacle: NSRect? = nil, screen: NSRect, visible: Bool,
                level: NSWindow.Level, positionLocked: Bool = true, owner: NSWindow? = nil) {
        if let old = presentation,
           old.anchor == anchor, old.obstacle == obstacle, old.screen == screen,
           old.visible == visible, old.level == level, old.positionLocked == positionLocked,
           old.owner === owner, (!isRequested || !visible || layoutUnavailable || panel?.isVisible == true) { return }
        presentation = Presentation(anchor: anchor, obstacle: obstacle, screen: screen,
            visible: visible, level: level, positionLocked: positionLocked, owner: owner)
        presentIfNeeded()
    }

    private func presentIfNeeded() {
        guard isRequested, let p = presentation, p.visible else {
            hide()
            return
        }
        guard let frame = DogInteractionHintLayout.frame(anchor: p.anchor, obstacle: p.obstacle, screen: p.screen) else {
            layoutUnavailable = true
            hide()
            return
        }
        layoutUnavailable = false
        if panel == nil {
            let created = DogInteractionHintPanel(contentRect: NSRect(origin: .zero, size: DogInteractionHintLayout.size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.isReleasedWhenClosed = false
            created.title = "小狗操作提示"
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.hidesOnDeactivate = false
            created.becomesKeyOnlyIfNeeded = true
            created.animationBehavior = .none
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            let view = DogInteractionHintContentView(frame: NSRect(origin: .zero, size: DogInteractionHintLayout.size))
            view.closeButton.target = self
            view.closeButton.action = #selector(closeClicked)
            view.disableButton.target = self
            view.disableButton.action = #selector(disableClicked)
            created.contentView = view
            panel = created
            content = view
        }
        guard let panel else { return }
        let changedFrame = lastFrame != frame
        let level = NSWindow.Level(rawValue: min(NSWindow.Level.statusBar.rawValue + 2, p.level.rawValue + 1))
        let changedLevel = lastLevel != level
        let ownerNumber = p.owner?.windowNumber
        let changedOwner = lastOwnerNumber != ownerNumber
        if lastLocked != p.positionLocked {
            content?.setPositionLocked(p.positionLocked)
            lastLocked = p.positionLocked
        }
        if changedFrame { panel.setFrame(frame, display: false); lastFrame = frame }
        if changedLevel { panel.level = level; lastLevel = level }
        if changedFrame || changedLevel || changedOwner || !panel.isVisible {
            panel.order(.above, relativeTo: ownerNumber ?? 0)
            lastOwnerNumber = ownerNumber
        }
    }

    @objc private func closeClicked() { dismiss(permanently: false) }
    @objc private func disableClicked() { dismiss(permanently: true) }
}

@MainActor
private final class DogInteractionHintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Also used by the isolated offscreen preview; this is not a screenshot of a user's desktop.
@MainActor
final class DogInteractionHintContentView: NSView {
    let closeButton = NSButton(title: "关闭", target: nil, action: nil)
    let disableButton = NSButton(title: "不再提示", target: nil, action: nil)
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // The card is always warm white; do not inherit dark-mode button ink.
        appearance = NSAppearance(named: .aqua)
        setAccessibilityRole(.group)
        setAccessibilityLabel("小狗操作提示")
        label.frame = NSRect(x: 16, y: 51, width: 178, height: 40)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.24, alpha: 1)
        addSubview(label)
        for (button, frame) in [(closeButton, NSRect(x: 29, y: 13, width: 65, height: 24)),
                                (disableButton, NSRect(x: 102, y: 13, width: 80, height: 24))] {
            button.frame = frame
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11)
            button.contentTintColor = NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.24, alpha: 1)
            button.focusRingType = .none
            button.setAccessibilityElement(true)
            button.setAccessibilityRole(.button)
            button.setAccessibilityLabel(button.title)
            addSubview(button)
        }
        closeButton.toolTip = "这次先收起，下次启动小狗仍会提示"
        disableButton.toolTip = "下次启动也不自动提示；需要时可从菜单再次打开"
        setPositionLocked(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setPositionLocked(_ locked: Bool) {
        label.stringValue = locked ? "双击按住拖动我\n按住来回摸摸我" : "按住拖动我\n点一下摸摸我"
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        NSColor(calibratedRed: 1, green: 0.99, blue: 0.96, alpha: 1).setFill()
        outline.fill()
        NSColor(calibratedRed: 0.83, green: 0.85, blue: 0.81, alpha: 1).setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }
}
