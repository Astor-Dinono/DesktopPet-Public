import AppKit

@MainActor
final class DogPreviewController: NSWindowController, NSWindowDelegate {
    private let stage = DogStudyView(frame: NSRect(x: 16, y: 118, width: 588, height: 232))
    private weak var desktopDog: PetView?
    private let onPinDesktop: () -> Void
    private let onHideDesktop: () -> Void
    private var suspended = false
    private let subtitle = NSTextField(labelWithString: "")

    init(desktopDog: PetView, autoNap: AutoNap, onPet: @escaping (NSPoint) -> Bool,
         onEffectsFrame: @escaping () -> Void, onEffectsCleared: @escaping () -> Void,
         onPinDesktop: @escaping () -> Void, onHideDesktop: @escaping () -> Void) {
        self.desktopDog = desktopDog
        self.onPinDesktop = onPinDesktop
        self.onHideDesktop = onHideDesktop
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        stage.dogs.forEach { $0.setAutoNap(autoNap) }
        stage.dogs.forEach { $0.tailSize = desktopDog.tailSize }
        setPositionLocked(desktopDog.positionLocked)
        stage.dogs.forEach {
            $0.onPet = onPet
            $0.onEffectsFrame = onEffectsFrame
            $0.onEffectsCleared = onEffectsCleared
        }
        window.title = "小狗互动预览"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let content = window.contentView!
        let title = NSTextField(labelWithString: "小狗也会害羞、打盹和 duang")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.frame = NSRect(x: 24, y: 383, width: 572, height: 25)
        content.addSubview(title)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 358, width: 572, height: 20)
        content.addSubview(subtitle)
        content.addSubview(stage)
        for (title, action, x) in [
            ("摸摸它", #selector(pet), 22.0),
            ("睡一会儿", #selector(rest), 166.0),
            ("叫醒", #selector(wake), 310.0),
            ("摇尾巴（模拟）", #selector(wag), 454.0)
        ] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 72, width: 144, height: 32)
            content.addSubview(button)
        }
        for (title, action, x) in [
            ("贴回屏幕边缘", #selector(pinToBottom), 110.0),
            ("收起贴边小狗", #selector(hideDesktopDog), 330.0)
        ] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 24, width: 180, height: 32)
            content.addSubview(button)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspace.addObserver(self, selector: #selector(suspend), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspace.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var visibleDogs: [PetView] {
        var views: [PetView] = []
        if window?.isVisible == true, window?.isMiniaturized == false { views += stage.dogs }
        if let desktopDog, desktopDog.window?.isVisible == true { views.append(desktopDog) }
        return views
    }

    func present() {
        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(nil)
        if !suspended { stage.start() }
    }

    @objc private func pet() { visibleDogs.forEach { $0.pet() } }
    @objc private func rest() { visibleDogs.forEach { $0.rest() } }
    @objc private func wake() { visibleDogs.forEach { $0.wake() } }
    @objc private func wag() { visibleDogs.forEach { $0.wag() } }

    @objc private func pinToBottom() { onPinDesktop() }
    @objc private func hideDesktopDog() { onHideDesktop() }

    @objc private func suspend() {
        suspended = true
        stage.stop()
    }

    @objc private func resume() {
        suspended = false
        if window?.isVisible == true, window?.isMiniaturized == false { stage.start() }
    }

    func stop() { stage.stop() }
    func setAutoNap(_ option: AutoNap) { stage.dogs.forEach { $0.setAutoNap(option) } }
    func setTailSize(_ size: DogTailSize) { stage.dogs.forEach { $0.tailSize = size } }
    func setPositionLocked(_ locked: Bool) {
        stage.dogs.forEach { $0.positionLocked = locked }
        subtitle.stringValue = locked
            ? "按住来回摸摸 · 双击按住第二下拖动 · 松手恢复摸摸"
            : "拖动到边缘自动贴合 · 点击选中后按 R 旋转 · 点击空白取消选择"
    }
    func keyboardPress() {
        guard window?.isVisible == true, window?.isMiniaturized == false else { return }
        stage.dogs.forEach { $0.keyboardPress() }
    }
    func pointerClick() {
        guard window?.isVisible == true, window?.isMiniaturized == false else { return }
        stage.dogs.forEach { $0.pointerClick() }
    }
    func windowWillClose(_ notification: Notification) { stage.stop() }
    func windowDidMiniaturize(_ notification: Notification) { stage.stop() }
    func windowDidDeminiaturize(_ notification: Notification) { if !suspended { stage.start() } }
}

@MainActor
private final class DogStudyView: NSView {
    private let canvases: [DogPreviewCanvas]
    var dogs: [PetView] { canvases.map(\.pet) }

    override init(frame frameRect: NSRect) {
        canvases = [
            DogPreviewCanvas(frame: NSRect(x: 8, y: 24, width: 366, height: 204),
                             scale: 0.62, name: "桌面预览小狗"),
            DogPreviewCanvas(frame: NSRect(x: 400, y: 24, width: 180, height: 204),
                             scale: 0.5, name: "侧栏预览小狗", sidebar: true)
        ]
        super.init(frame: frameRect)
        canvases.forEach { addSubview($0) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func start() { dogs.forEach { $0.start() } }
    func stop() { canvases.forEach { $0.stop() } }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(nil) }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ("桌面预览" as NSString).draw(at: NSPoint(x: 158, y: 3), withAttributes: attributes)
        ("侧栏预览" as NSString).draw(at: NSPoint(x: 466, y: 3), withAttributes: attributes)
    }
}

/// Placement uses the drawn baseline rather than the transparent inset beneath it.
@MainActor
struct DogPreviewPlacement {
    let canonicalSize: NSSize
    let area: NSRect
    var turnBounds: DogTurnBounds {
        DogTurnBounds(canonicalSize: canonicalSize, area: area,
                      baseline: 1 + DogRenderer.baselineY * canonicalSize.width / DogRenderer.canvas.width)
    }

    func offsets(angle: Double) -> NSRect {
        turnBounds.offsets(angle: angle)
    }

    func center(_ proposed: NSPoint, angle: Double, snapping: Bool = false) -> NSPoint {
        let box = offsets(angle: angle)
        func fit(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            guard low <= high else { return (low + high) / 2 }
            let result = min(high, max(low, value))
            guard snapping else { return result }
            if min(result - low, high - result) <= 12 {
                return result - low <= high - result ? low : high
            }
            return result
        }
        return NSPoint(x: fit(proposed.x, area.minX - box.minX, area.maxX - box.maxX),
                       y: fit(proposed.y, area.minY - box.minY, area.maxY - box.maxY))
    }
}

/// A local preview surface: no global shortcuts, saved positions or extra animation clock.
@MainActor
final class DogPreviewCanvas: NSView {
    let pet = PetView(frame: .zero)
    let canonicalSize: NSSize
    private let name: String
    private let sidebar: Bool
    private let clock: () -> TimeInterval
    private(set) var orientation: DogOrientation = .bottom
    private(set) var pose = DogTurnPose(angle: 0, center: .zero, badgeCenter: .zero)
    private var turn: DogTurnMotion?
    private var dragOrigin: NSPoint?
    private var dragOffset = NSPoint.zero
    private var snapAfterTurn = false
    private var selected = false
    private var placement: DogPreviewPlacement {
        DogPreviewPlacement(canonicalSize: canonicalSize, area: bounds.insetBy(dx: 2, dy: 2))
    }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, scale: Double, name: String, sidebar: Bool = false,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        canonicalSize = NSSize(width: DogRenderer.canvas.width * scale, height: DogRenderer.canvas.height * scale)
        self.name = name
        self.sidebar = sidebar
        self.clock = clock
        super.init(frame: frame)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        addSubview(pet)
        pet.allowsWindowDragging = false
        pet.onSelection = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
        pet.onPointerPress = { [weak self] in
            guard let self else { return }
            self.advanceAnimation(at: self.clock())
            self.dragOrigin = self.pose.center
            self.dragOffset = .zero
        }
        pet.onDragOffset = { [weak self] offset, _ in self?.drag(to: offset) }
        pet.onPositionChanged = { [weak self] in self?.snapToEdges() }
        pet.onPointerRelease = { [weak self] in self?.dragOrigin = nil }
        pet.onInteractionFrame = { [weak self] in
            guard let self, self.turn != nil else { return }
            self.advanceAnimation(at: self.clock())
        }
        pet.setAccessibilityHelp("拖动可在本区域内移动，松手靠近边缘会贴合并保持朝向。点击选中后按 R 平滑旋转，点击空白取消选择。")
        pose.center = placement.center(NSPoint(x: bounds.midX, y: bounds.minY), angle: 0)
        updateLabel()
        presentPose()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func becomeFirstResponder() -> Bool {
        selected = true
        updateLabel()
        return true
    }

    override func resignFirstResponder() -> Bool {
        selected = false
        updateLabel()
        return true
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(nil) }

    override func keyDown(with event: NSEvent) {
        guard window?.firstResponder === self, selected, DogRotationKey.matches(event) else {
            super.keyDown(with: event)
            return
        }
        // A held R is one turn, not an endlessly spinning dog.
        if !event.isARepeat { rotate() }
    }

    func rotate() {
        pet.cancelStroke()
        let time = clock()
        advanceAnimation(at: time)
        orientation = DogOrientation(rawValue: (orientation.rawValue + 90) % 360) ?? .bottom
        let proposed = dragOrigin.map { NSPoint(x: $0.x + dragOffset.x, y: $0.y + dragOffset.y) } ?? pose.center
        move(to: placement.center(proposed, angle: Double(orientation.rawValue)),
             angle: Double(orientation.rawValue), at: time)
        updateLabel()
    }

    private func drag(to offset: NSPoint) {
        guard let dragOrigin else { return }
        let time = clock()
        advanceAnimation(at: time)
        dragOffset = offset
        let proposed = NSPoint(x: dragOrigin.x + offset.x, y: dragOrigin.y + offset.y)
        pose.center = placement.center(proposed, angle: pose.angle)
        if turn != nil {
            move(to: placement.center(proposed, angle: Double(orientation.rawValue)),
                 angle: Double(orientation.rawValue), at: time)
        } else { presentPose() }
    }

    private func snapToEdges() {
        if turn != nil { snapAfterTurn = true; return }
        let target = placement.center(pose.center, angle: pose.angle, snapping: true)
        guard target != pose.center else { return }
        move(to: target, angle: pose.angle, at: clock(), duration: 0.18)
    }

    private func move(to center: NSPoint, angle: Double, at time: TimeInterval, duration: TimeInterval? = nil) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            turn = nil
            pose = DogTurnPose(angle: angle, center: center, badgeCenter: .zero)
            presentPose()
            return
        }
        let velocity = turn?.velocity(now: time)
        turn = DogTurnMotion(now: time, from: pose, targetAngle: angle,
                             center: center, badgeCenter: .zero, velocity: velocity, duration: duration,
                             bounds: placement.turnBounds)
        presentPose()
    }

    func advanceAnimation(at time: TimeInterval) {
        guard let turn else { return }
        pose = turn.pose(now: time)
        if turn.isFinished(now: time) {
            self.turn = nil
            if snapAfterTurn {
                snapAfterTurn = false
                snapToEdges()
            }
        }
        presentPose()
    }

    private func presentPose() {
        if turn != nil {
            let side = DogTurnPresentation.enclosingSide(for: canonicalSize)
            pet.frame = NSRect(x: pose.center.x - side / 2, y: pose.center.y - side / 2,
                               width: side, height: side)
            pet.setTurnPresentation(DogTurnPresentation(canonicalSize: canonicalSize, angle: pose.angle))
        } else {
            pet.orientation = orientation
            pet.setTurnPresentation(nil)
            let pivot = DogTurnPresentation.pivot(in: canonicalSize).applying(orientation.transform(size: canonicalSize))
            pet.frame = NSRect(origin: NSPoint(x: pose.center.x - pivot.x, y: pose.center.y - pivot.y),
                               size: orientation.rotatedSize(canonicalSize))
        }
    }

    func stop() {
        if let turn {
            pose = turn.to
            pose.center = placement.center(pose.center, angle: pose.angle, snapping: snapAfterTurn)
        }
        turn = nil
        snapAfterTurn = false
        dragOrigin = nil
        presentPose()
        pet.stop()
    }

    private func updateLabel() {
        pet.setAccessibilityLabel("\(name)\(selected ? "，已选中，按 R 旋转" : "，点击选中")，\(orientation.title)")
    }

    override func draw(_ dirtyRect: NSRect) {
        (sidebar ? NSColor.quaternaryLabelColor.withAlphaComponent(0.12) : .controlBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        if sidebar {
            NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setFill()
            for y in [170.0, 150, 130] {
                NSBezierPath(roundedRect: NSRect(x: 20, y: y, width: 108, height: 4), xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}
