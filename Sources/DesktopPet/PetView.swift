import AppKit

@MainActor
final class PetPanel: NSPanel {
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private(set) var isRotationSelected = false
    override var canBecomeKey: Bool { isRotationSelected }
    override var canBecomeMain: Bool { false }
    var petFrame: NSRect {
        frame.offsetBy(dx: -(contentView?.bounds.minX ?? 0), dy: -(contentView?.bounds.minY ?? 0))
    }
    // Placement clamps the drawn baseline. AppKit must not clamp the transparent frame a second time.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func setPetFrame(_ desired: NSRect) {
        setFrame(desired, display: false)
        // AppKit rounds window origins to points. Keep the ink anchored at its requested subpixel position.
        contentView?.setBoundsOrigin(NSPoint(x: frame.minX - desired.minX, y: frame.minY - desired.minY))
        contentView?.needsDisplay = true
    }

    func selectForRotation(_ pet: PetView) {
        guard pet.onRotationRequest != nil else { return }
        isRotationSelected = true
        makeKey()
        makeFirstResponder(pet)
        pet.isRotationSelected = true
    }

    func clearRotationSelection() {
        if isKeyWindow { resignKey() }
        isRotationSelected = false
        makeFirstResponder(nil)
        ((contentView as? DogCompanionView)?.pet ?? contentView as? PetView)?.isRotationSelected = false
    }

    override func resignKey() {
        ((contentView as? DogCompanionView)?.pet ?? contentView as? PetView)?.cancelPointerInteraction()
        super.resignKey()
        isRotationSelected = false
        ((contentView as? DogCompanionView)?.pet ?? contentView as? PetView)?.isRotationSelected = false
        makeFirstResponder(nil)
    }

    func startPointerRouting() {
        guard globalPointerMonitor == nil, localPointerMonitor == nil else { return }
        acceptsMouseMovedEvents = true
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        // Read only the current cursor for hit testing; no clicks, keys or event data are extracted.
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPointerRouting() }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.refreshPointerRouting() }
            return event
        }
        refreshPointerRouting()
    }

    /// A desktop dog can now be freely placed inside the menu band. Keep that
    /// placement interactive too; transparent padding still uses pointer routing.
    @discardableResult
    func updateDesktopLevel(menuBands: [NSRect]) -> Bool {
        let overlapsMenu = menuBands.contains { $0.intersects(petFrame) }
        let desired = overlapsMenu ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
        if level != desired { level = desired }
        return overlapsMenu
    }

    func stopPointerRouting() {
        ((contentView as? DogCompanionView)?.pet ?? contentView as? PetView)?.cancelPointerInteraction()
        clearRotationSelection()
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        globalPointerMonitor = nil
        localPointerMonitor = nil
        ignoresMouseEvents = true
    }

    func refreshPointerRouting() {
        guard isVisible, let companion = contentView as? DogCompanionView else { return }
        let point = companion.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        updatePointerRouting(at: point, pressedButtons: NSEvent.pressedMouseButtons)
    }

    // Kept separate from cursor sampling so geometry, capture and foreign drags can be verified.
    func updatePointerRouting(at point: NSPoint, pressedButtons: Int, hoverTime: TimeInterval? = nil) {
        guard let companion = contentView as? DogCompanionView else { return }
        companion.updatePointer(at: point)
        companion.pet.updateHover(at: companion.pet.convert(point, from: companion),
            pressedButtons: pressedButtons, hoverTime: hoverTime)
        ignoresMouseEvents = !companion.pet.hasPointerCapture
            && (pressedButtons != 0 || !companion.containsInteraction(point))
    }
}

/// Used only by the selected view's normal responder chain, never by the global counter.
enum DogRotationKey {
    static func matches(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            && event.charactersIgnoringModifiers?.lowercased() == "r"
    }
}

@MainActor
final class PetView: NSView {
    var orientation: DogOrientation = .bottom {
        didSet { if oldValue != orientation { cancelHoverInteraction() }; needsDisplay = true }
    }
    var topbarHeight: CGFloat? {
        didSet {
            if oldValue != topbarHeight { cancelHoverInteraction() }
            needsDisplay = true
            if topbarHeight != nil {
                setAccessibilityLabel("顶栏小狗，左右拖动摆放，向下拖出")
                setAccessibilityHelp("左右拖动调整顶栏位置，向下拖出回到桌面；右键可以调整大小或重置位置。顶栏不显示数字框。")
            } else {
                setAccessibilityLabel("小狗，点击摸摸，拖放回弹")
                setAccessibilityHelp("点击摸摸并选中，按 R 平滑旋转 90°；拖到屏幕顶部附近松手可进入顶栏，往下拖出回到桌面。")
            }
            updateInteractionHelp()
        }
    }
    var topbarScale: Double = 0.5 { didSet { needsDisplay = true } }
    var tailSize: DogTailSize = .small { didSet { needsDisplay = true } }
    static let positionLockKey = "dog.positionLocked"
    var positionLocked = false {
        didSet {
            if oldValue != positionLocked { cancelPointerInteraction() }
            updateInteractionHelp()
        }
    }
    var motion = PetMotion(now: ProcessInfo.processInfo.systemUptime)
    var onSelection: (() -> Void)?
    var onDragOffset: ((NSPoint, NSPoint) -> Void)?
    var onRotationRequest: (() -> Void)?
    var onCancelSelection: (() -> Void)?
    var isRotationSelected = false {
        didSet {
            guard oldValue != isRotationSelected else { return }
            setAccessibilityLabel(isRotationSelected ? "小狗，已选中，按 R 旋转，Esc 取消" : "小狗，点击摸摸，拖放回弹")
        }
    }
    var onPositionChanged: (() -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onInteractionFrame: (() -> Void)?
    var onPointerPress: (() -> Void)?
    var onPointerRelease: (() -> Void)?
    var onPet: ((NSPoint) -> Bool)?
    var onEffectsFrame: (() -> Void)?
    var onEffectsCleared: (() -> Void)?
    private var heartAnimationUntil: TimeInterval = 0
    private(set) var turnPresentation: DogTurnPresentation?
    var hasPointerCapture: Bool { pressPoint != nil }
    var allowsWindowDragging = true
    var allowsHoverInteraction = true {
        didSet { if !allowsHoverInteraction { cancelHoverInteraction() } }
    }
    private var tail = DogMotion()
    private var running = false
    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var pressPoint: NSPoint?
    private var originalWindowOrigin: NSPoint?
    private var didDrag = false
    private var pressIsStroke = false
    private var pressCanClick = false
    private var stroke = DogStrokeGesture()
    private var hover = DogHoverGesture()
    private var petExpression = DogPetExpression()
    private var lastStrokeEffect: TimeInterval = -.infinity
    private var lastStrokeBounce: TimeInterval = -.infinity
    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        motion.dogYawnEnabled = DogYawnArtwork.available
        focusRingType = .none
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("小狗，点击摸摸，拖放回弹")
        setAccessibilityHelp("点击会脸红冒爱心；拖动可以移动。菜单栏中可以隐藏、休息或退出。")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { topbarHeight == nil && onRotationRequest != nil }
    override var needsPanelToBecomeKey: Bool { topbarHeight == nil && onRotationRequest != nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRotationSelected, window?.firstResponder === self else { super.keyDown(with: event); return }
        if DogRotationKey.matches(event) {
            if !event.isARepeat {
                cancelStroke()
                onRotationRequest?()
            }
        } else if event.charactersIgnoringModifiers == "\u{1b}" {
            onCancelSelection?()
        } else { super.keyDown(with: event) }
    }

    override func accessibilityFrame() -> NSRect {
        guard let window else { return super.accessibilityFrame() }
        if topbarHeight != nil { return window.convertToScreen(convert(topbarVisibleBounds, to: nil)) }
        let size = canonicalSize
        let scale = min(size.width / DogRenderer.canvas.width, size.height / DogRenderer.canvas.height)
        let head = NSRect(x: (size.width - DogRenderer.canvas.width * scale) / 2 + 22 * scale,
                          y: 1 + DogRenderer.baselineY * scale, width: 180 * scale, height: 75 * scale)
            .applying(dogTransform)
        return window.convertToScreen(convert(head, to: nil))
    }

    private var canonicalSize: NSSize { turnPresentation?.canonicalSize ?? orientation.rotatedSize(bounds.size) }
    /// Stable motion envelope: the hint must not bob along with breathing.
    var interactionHintFrame: NSRect? {
        guard let window else { return nil }
        let local: NSRect
        if topbarHeight != nil {
            let layout = DogTopbarRenderer.layout(size: bounds.size, scale: topbarScale)
            let transform = CGAffineTransform(translationX: layout.offset.x, y: layout.offset.y)
                .scaledBy(x: layout.scale, y: layout.scale)
            local = DogRenderer.interactionHintBounds(size: DogRenderer.canvas)
                .applying(transform).intersection(topbarVisibleBounds)
        } else {
            local = DogRenderer.interactionHintBounds(size: canonicalSize).applying(dogTransform)
                .intersection(bounds)
        }
        guard !local.isNull, !local.isEmpty else { return nil }
        return window.convertToScreen(convert(local, to: nil))
    }
    var desktopDockingFrame: NSRect? {
        guard topbarHeight == nil, let window else { return nil }
        let head = DogRenderer.headBounds(size: canonicalSize, pose: motion.pose(now: now, reducedMotion: reducedMotion))
            .applying(dogTransform)
        return window.convertToScreen(convert(head, to: nil))
    }
    private var dogTransform: CGAffineTransform {
        turnPresentation?.transform(in: bounds) ?? orientation.transform(size: canonicalSize)
    }

    func setTurnPresentation(_ presentation: DogTurnPresentation?) {
        if presentation != nil { cancelHoverInteraction() }
        turnPresentation = presentation
        needsDisplay = true
        if presentation != nil { schedule(interval: reducedMotion ? 1 / 10 : 1 / 60) }
    }

    // Transparent margins are not interaction targets within this view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return containsInteraction(p) ? self : nil
    }

    func containsInteraction(_ p: NSPoint, includesBaseline: Bool = true) -> Bool {
        guard bounds.contains(p) else { return false }
        if topbarHeight != nil, !topbarVisibleBounds.contains(p) { return false }
        let time = now
        let pose = motion.pose(now: time, reducedMotion: reducedMotion)
        let tailPose = tail.pose(now: time, reducedMotion: reducedMotion)
        if topbarHeight != nil {
            return DogTopbarRenderer.contains(p, size: bounds.size, pose: pose, tail: tailPose, tailSize: tailSize, scale: topbarScale, includesBaseline: includesBaseline)
        }
        let local = p.applying(dogTransform.inverted())
        return DogRenderer.contains(local, size: canonicalSize, pose: pose,
                                    angle: tailPose.angle, bend: tailPose.bend, tailSize: tailSize, includesBaseline: includesBaseline)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        let pose = motion.pose(now: now, reducedMotion: reducedMotion)
        context.saveGState()
        defer { context.restoreGState() }
        context.concatenate(dogTransform)
        let tailPose = tail.pose(now: now, reducedMotion: reducedMotion)
        if topbarHeight != nil {
            context.clip(to: topbarVisibleBounds)
            DogTopbarRenderer.draw(in: context, size: bounds.size, pose: pose, tail: tailPose,
                blink: DogMotion.blink(now: now, reducedMotion: reducedMotion), tailSize: tailSize, scale: topbarScale,
                petting: petExpression.value(now: now))
            return
        }
        DogRenderer.draw(in: context, size: canonicalSize, pose: pose,
            angle: tailPose.angle, bend: tailPose.bend,
            blink: DogMotion.blink(now: now, reducedMotion: reducedMotion), tailSize: tailSize,
            petting: petExpression.value(now: now))
    }

    // With a baseline on the menu edge, a large dog can extend above this
    // display. Do not paint or intercept clicks on a display placed above it.
    private var topbarVisibleBounds: NSRect {
        guard let topbarHeight else { return bounds }
        return bounds.intersection(NSRect(x: 0, y: 0, width: bounds.width,
            height: topbarHeight + DogTopbarPlacement.baselineInset))
    }

    func start() {
        running = true
        motion.advance(now: now)
        onInteractionFrame?()
        needsDisplay = true
        schedule(interval: reducedMotion ? 1.0 / 10 : 1.0 / 30)
    }

    func stop() {
        running = false
        cancelPointerInteraction()
        petExpression.cancel()
        onEffectsCleared?()
        timer?.invalidate()
        timer = nil
        interval = 0
    }

    func rest() {
        cancelPointerInteraction()
        petExpression.cancel()
        onEffectsCleared?()
        motion.sleep(now: now)
        tail.settle(now: now)
        needsDisplay = true
    }

    func wake() {
        motion.wake(now: now)
        needsDisplay = true
    }

    func setAutoNap(_ option: AutoNap) {
        motion.setAutoNap(option, now: now)
        needsDisplay = true
        schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
    }

    func pet(at screenPoint: NSPoint? = nil) {
        let time = now
        motion.click(now: time)
        tail.wag(now: time)
        if let window {
            let point = screenPoint ?? window.convertPoint(toScreen:
                convert(topbarHeight == nil ? DogTurnPresentation.pivot(in: canonicalSize).applying(dogTransform)
                    : NSPoint(x: bounds.midX, y: bounds.midY), to: nil))
            if onPet?(point) == true { heartAnimationUntil = time + ClickHeart.lifetime }
        }
        needsDisplay = true
        schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
    }

    func wag() {
        motion.wake(now: now)
        tail.wag(now: now)
        needsDisplay = true
        schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
    }

    private func strokePet(at screenPoint: NSPoint, now time: TimeInterval, fromHover: Bool = false) {
        if fromHover, motion.sleepStarted != nil {
            motion.sootheSleeping(now: time)
            needsDisplay = true
            schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
            return
        }
        let bounces = time - lastStrokeBounce >= 0.65
        motion.stroke(now: time, bounces: bounces)
        if bounces { lastStrokeBounce = time }
        petExpression.touch(now: time)
        tail.wag(now: time)
        if time - lastStrokeEffect >= 0.65 {
            lastStrokeEffect = time
            if onPet?(screenPoint) == true { heartAnimationUntil = time + ClickHeart.lifetime }
        }
        needsDisplay = true
        schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
    }

    func updateInteractionHelp() {
        if positionLocked {
            setAccessibilityHelp("位置已锁定。光标停留片刻后轻轻来回移动即可摸摸，也可按住来回摸摸；右键可解锁位置。")
        } else if topbarHeight != nil {
            setAccessibilityHelp("光标停留片刻后轻轻来回移动即可摸摸；按住左右拖动调整顶栏位置，向下拖出回到桌面。")
        } else {
            setAccessibilityHelp("光标停留片刻后轻轻来回移动即可摸摸；按住拖动可以移动。点击选中后按 R 旋转；右键可锁定位置。")
        }
    }

    /// Called by existing pointer routing, including its regular animation-frame
    /// refresh. Screen points stay stable while breathing changes the silhouette.
    func updateHover(at point: NSPoint, pressedButtons: Int, hoverTime: TimeInterval? = nil) {
        guard let window else { cancelHoverInteraction(); return }
        let allowed = allowsHoverInteraction && !hasPointerCapture && !motion.isDragging
            && turnPresentation == nil && pressedButtons == 0
        guard allowed else { cancelHoverInteraction(); return }
        let screenPoint = window.convertPoint(toScreen: convert(point, to: nil))
        if hover.update(screenPoint, now: hoverTime ?? now,
            inside: containsInteraction(point, includesBaseline: false), allowed: true) {
            strokePet(at: screenPoint, now: now, fromHover: true)
        }
    }

    func cancelHoverInteraction() { hover.cancel() }

    func cancelStroke() {
        cancelHoverInteraction()
        if pressIsStroke { cancelPointerInteraction() }
    }

    func cancelPointerInteraction() {
        cancelHoverInteraction()
        let captured = hasPointerCapture
        let wasDragging = didDrag
        pressPoint = nil
        originalWindowOrigin = nil
        didDrag = false
        pressIsStroke = false
        pressCanClick = false
        stroke.cancel()
        if wasDragging { motion.cancelDrag(now: now); onPositionChanged?() }
        if captured { onPointerRelease?(); onInteractionFrame?() }
    }

    @objc private func cancelPointerForWindow(_ notification: Notification) {
        cancelPointerInteraction()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        cancelPointerInteraction()
        return super.menu(for: event)
    }

    func keyboardPress() {
        inputActivity(wagsTail: true)
    }

    func pointerClick() {
        cancelHoverInteraction()
        inputActivity(wagsTail: false)
    }

    private func inputActivity(wagsTail: Bool) {
        guard window?.isVisible == true, !motion.isDragging else { return }
        motion.inputActivity(now: now)
        if wagsTail { tail.wag(now: now) }
        needsDisplay = true
        schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
    }

    private func schedule(interval newInterval: TimeInterval) {
        guard running else { return }
        guard newInterval != interval || timer == nil else { return }
        timer?.invalidate()
        interval = newInterval
        let timer = Timer(timeInterval: newInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = newInterval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard window?.isVisible == true, window?.isMiniaturized == false else { stop(); return }
        motion.advance(now: now)
        if motion.sleepStarted != nil { petExpression.cancel() }
        onInteractionFrame?()
        onEffectsFrame?()
        needsDisplay = true
        let quick = now < heartAnimationUntil || turnPresentation != nil || motion.isAnimatingQuickly(now: now)
            || (tail.isMoving(now: now) || petExpression.isMoving(now: now) || DogMotion.blink(now: now) > 0)
        let rate = reducedMotion ? 10.0 : (quick ? 60.0 : 30.0)
        schedule(interval: 1 / rate)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        cancelPointerInteraction()
        onSelection?()
        onPointerPress?()
        pressPoint = window.convertPoint(toScreen: event.locationInWindow)
        originalWindowOrigin = window.frame.origin
        didDrag = false
        // Single press always drags unless the user explicitly locked position.
        pressIsStroke = positionLocked
        pressCanClick = !positionLocked
            || containsInteraction(convert(event.locationInWindow, from: nil), includesBaseline: false)
        if pressIsStroke, let pressPoint {
            stroke.begin(pressPoint, now: now,
                inside: containsInteraction(convert(event.locationInWindow, from: nil), includesBaseline: false))
        }
        onInteractionFrame?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint, let origin = originalWindowOrigin, let window else { return }
        let current = window.convertPoint(toScreen: event.locationInWindow)
        if pressIsStroke {
            let time = now
            if stroke.move(current, now: time,
                inside: containsInteraction(convert(event.locationInWindow, from: nil), includesBaseline: false)) {
                strokePet(at: current, now: time)
            }
            return
        }
        let dx = current.x - pressPoint.x
        let dy = current.y - pressPoint.y
        guard didDrag || hypot(dx, dy) > 4 else { return }
        if !didDrag {
            // Already emitted hearts live in screen space and finish independently of the dog.
            didDrag = true
            motion.beginDrag(now: now)
            tail.settle(now: now)
        }
        if let onDragOffset {
            onDragOffset(NSPoint(x: dx, y: dy), current)
        } else if allowsWindowDragging {
            window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard pressPoint != nil else { return }
        if pressIsStroke {
            let point = window?.convertPoint(toScreen: event.locationInWindow)
            let clicks = point.map {
                stroke.finish($0, inside: containsInteraction(convert(event.locationInWindow, from: nil), includesBaseline: false))
            } ?? false
            cancelPointerInteraction()
            if clicks { pet(at: point) }
            needsDisplay = true
            return
        }
        // Capture the event's screen point before callbacks can move the window.
        let droppedAt = didDrag ? window?.convertPoint(toScreen: event.locationInWindow) : nil
        if didDrag {
            motion.endDrag(now: now)
            onPositionChanged?()
        } else if pressCanClick && (!positionLocked
            || containsInteraction(convert(event.locationInWindow, from: nil), includesBaseline: false)) {
            pet(at: window?.convertPoint(toScreen: event.locationInWindow))
        }
        pressPoint = nil
        originalWindowOrigin = nil
        didDrag = false
        pressCanClick = false
        if let droppedAt { onDragEnded?(droppedAt) }
        onPointerRelease?()
        onInteractionFrame?()
        needsDisplay = true
        schedule(interval: reducedMotion ? 1 / 10 : 1 / 60)
    }

    override func accessibilityPerformPress() -> Bool {
        onSelection?()
        pet()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            if let window { NotificationCenter.default.removeObserver(self, name: name, object: window) }
            if let newWindow { NotificationCenter.default.addObserver(self, selector: #selector(cancelPointerForWindow(_:)), name: name, object: newWindow) }
        }
        if newWindow == nil { stop() }
        super.viewWillMove(toWindow: newWindow)
    }
}
