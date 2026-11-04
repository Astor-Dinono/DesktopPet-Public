import AppKit

@main
struct DesktopPetApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-interaction-effects" {
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for effect in InteractionEffect.allCases {
                    for (name, age) in [("pop", 0.13), ("rising", 0.55), ("fading", 1.5), ("gone", 2.0)] {
                        try ClickHeartOverlay.renderPreview(age: age,
                            to: directory.appendingPathComponent("\(effect.rawValue)-\(name).png"), effect: effect)
                    }
                }
            } catch { fputs("Interaction effect preview failed: \(error)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-app-icon" {
            do { try DogRenderer.renderAppIcon(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
            catch { fputs("App icon rendering failed: \(error)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-click-heart-previews" {
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for (name, age) in [("born", 0.12), ("rising", 0.55), ("fading", 1.15), ("gone", 2.0)] {
                    try ClickHeartOverlay.renderPreview(age: age, to: directory.appendingPathComponent("\(name).png"))
                }
                print("Rendered four click-heart previews to \(directory.path)")
            } catch { fputs("Click-heart preview failed: \(error)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-tail-loop" {
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var motion = DogMotion()
                motion.wag(now: 0)
                for index in 0..<60 {
                    let pose = motion.pose(now: Double(index) / 24)
                    try DogRenderer.renderPNG(angle: pose.angle, bend: pose.bend,
                        to: directory.appendingPathComponent(String(format: "%03d.png", index)), background: .white)
                }
                print("Rendered 60 flexible tail frames to \(directory.path)")
            } catch { fputs("Tail preview failed: \(error)\n", stderr); exit(1) }
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-dog-previews" {
            do {
                let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let previews: [(String, PetPose, Double, Double)] = [
                    ("rest", PetPose(), 0, 0),
                    ("breath-in", PetPose(breath: 1), 0, 0),
                    ("breath-out", PetPose(breath: -1), 0, 0),
                    ("wag-left", PetPose(), -0.26, 0),
                    ("wag-right", PetPose(), 0.26, 0),
                    ("blink", PetPose(), 0, 1),
                    ("sleep-drowsy", Self.restPreview(at: 0.65), 0, 0),
                    ("sleep-bubble", Self.restPreview(at: 1.3), 0, 0),
                    ("sleeping", Self.restPreview(at: 3), 0, 0),
                    ("waking-bubble", Self.wakePreview(at: 0.22), 0, 0),
                    ("waking-eyes", Self.wakePreview(at: 0.6), 0, 0),
                    ("waking-settled", Self.wakePreview(at: 1.2), 0, 0),
                    ("click-start", Self.affectionPreview(at: 0.18), 0.12, 0),
                    ("affection", Self.affectionPreview(at: 0.65), -0.18, 0),
                    ("click-fade", Self.affectionPreview(at: 1.45), 0, 0),
                    ("landing", PetPose(squash: PetMotion.landing(at: 0.065)), 0, 0),
                    ("duang-click-down", Self.affectionPreview(at: 0.065), 0, 0),
                    ("duang-click-up", Self.affectionPreview(at: 0.23), 0, 0)
                ]
                for (name, pose, angle, blink) in previews {
                    try DogRenderer.renderPNG(angle: angle, pose: pose, blink: blink,
                        to: directory.appendingPathComponent("\(name).png"), background: NSColor(calibratedWhite: 0.96, alpha: 1))
                }
                try DogRenderer.renderPNG(angle: 0, to: directory.appendingPathComponent("dark.png"), background: NSColor(calibratedWhite: 0.09, alpha: 1))
                try DogRenderer.renderPNG(to: directory.appendingPathComponent("transparent.png"))
                print("Rendered \(previews.count + 2) dog interaction previews to \(directory.path)")
            } catch {
                fputs("Dog preview failed: \(error)\n", stderr)
                exit(1)
            }
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    private static func affectionPreview(at age: TimeInterval) -> PetPose {
        var motion = PetMotion(now: 0)
        motion.click(now: 0)
        return motion.pose(now: age)
    }

    private static func restPreview(at age: TimeInterval) -> PetPose {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 0)
        return motion.pose(now: age)
    }

    private static func wakePreview(at age: TimeInterval) -> PetPose {
        var motion = PetMotion(now: 0)
        motion.sleep(now: 0)
        motion.wake(now: 3)
        return motion.pose(now: 3 + age)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: PetPanel!
    private var pet: PetView!
    private var companion: DogCompanionView!
    private var alwaysCountItem: NSMenuItem!
    private var statusItem: NSStatusItem!
    private var visibilityItem: NSMenuItem!
    private var sleepItem: NSMenuItem!
    private var autoNapItem: NSMenuItem!
    private var autoNap = AutoNap(storedValue: UserDefaults.standard.object(forKey: AutoNap.preferenceKey) as? Int)
    private var scale = DogRenderer.defaultScale
    private var orientation = DogOrientation(rawValue: UserDefaults.standard.integer(forKey: DogOrientation.preferenceKey)) ?? .bottom
    private var edgeItem: NSMenuItem!
    private var directionItems: [NSMenuItem] = []
    private var effectChoices: InteractionEffectMenuView?
    private var tailSize = DogTailSize(storedValue: UserDefaults.standard.object(forKey: DogTailSize.preferenceKey) as? Int)
    private var positionLockItem: NSMenuItem!
    private var topbarEnabled = false
    private var topbarHidden = false
    private var topbarItem: NSMenuItem!
    private var topbarResetItem: NSMenuItem!
    private var topbarPosition = DogTopbarPosition.load(from: .standard)
    private var topbarDragCenterX: CGFloat?
    private var topbarDragPressY: CGFloat?
    private var dragStartedInTopbar = false
    private struct DesktopPlacement { let frame: NSRect; let anchor: NSPoint }
    private var desktopPlacementBeforeDrag: DesktopPlacement?
    private var sizeMenuItem: NSMenuItem!
    private var orientationMenuItem: NSMenuItem!
    private var previousDragOffset = NSPoint.zero
    private struct TurnState {
        var motion: DogTurnMotion
        let screen: NSScreen
        var targetAnchor: NSPoint
        var pausedPose: DogTurnPose?
    }
    private var turning: TurnState?
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var suspended = false
    private var dogPreview: DogPreviewController?
    private let clickHearts = ClickHeartOverlay()
    private let interactionHint = DogInteractionHint()
    private var openHintMenus = Set<ObjectIdentifier>()
    private let keyCounts = KeyCountStore()
    private let keyboard = InputMonitor()
    private let updater = DogUpdater()
    private var countMenuItem: NSMenuItem!
    private var todayCountItem: NSMenuItem!
    private var totalCountItem: NSMenuItem!
    private var countStatusItem: NSMenuItem!
    private var countToggleItem: NSMenuItem!
    private var countRetryItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stored = UserDefaults.standard.double(forKey: "dog.scale")
        scale = DogSize.matching(stored)?.scale ?? DogRenderer.defaultScale
        let size = DogCompanionView.size(scale: scale, orientation: orientation)
        panel = PetPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "小狗"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // Keep the companion in place when Mission Control reveals the desktop.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        pet = PetView(frame: NSRect(origin: .zero, size: size))
        pet.setAutoNap(autoNap)
        pet.tailSize = tailSize
        pet.positionLocked = UserDefaults.standard.object(forKey: PetView.positionLockKey) as? Bool ?? true
        pet.onDragEnded = { [weak self] in self?.finishDesktopDrag(at: $0) }
        companion = DogCompanionView(pet: pet, scale: scale)
        companion.orientation = orientation
        companion.alwaysShowCount = UserDefaults.standard.bool(forKey: "dog.alwaysShowCount")
        companion.updateCount(keyCounts.counts.total)
        panel.contentView = companion
        pet.onRotationRequest = { [weak self] in
            guard let self else { return }
            self.setOrientation(DogOrientation(rawValue: (self.orientation.rawValue + 90) % 360) ?? .bottom)
        }
        pet.onSelection = { [weak self] in
            guard let self else { return }
            guard !self.topbarEnabled else { return }
            self.panel.selectForRotation(self.pet)
        }
        pet.onCancelSelection = { [weak self] in self?.panel.clearRotationSelection() }
        pet.onDragOffset = { [weak self] offset, point in self?.dragDesktop(to: offset, pointer: point) }
        pet.updateInteractionHelp()
        pet.onInteractionFrame = { [weak self] in
            self?.advanceTurn()
            self?.panel.refreshPointerRouting()
            self?.updateInteractionHint()
        }
        pet.onPointerPress = { [weak self] in
            guard let self else { return }
            self.interactionHint.hide()
            self.previousDragOffset = .zero
            self.dragStartedInTopbar = self.topbarEnabled
            self.desktopPlacementBeforeDrag = self.topbarEnabled ? nil : self.currentDesktopPlacement
            self.topbarDragCenterX = self.topbarEnabled ? self.panel.petFrame.midX : nil
            self.topbarDragPressY = nil
            self.pauseTurn()
        }
        pet.onPointerRelease = { [weak self] in
            self?.topbarDragCenterX = nil
            self?.topbarDragPressY = nil
            self?.desktopPlacementBeforeDrag = nil
            self?.dragStartedInTopbar = false
            self?.resumeTurn()
        }
        pet.onPet = { [weak self] in self?.clickHearts.emit(at: $0) ?? false }
        pet.onEffectsFrame = { [weak self] in self?.clickHearts.advance() }
        pet.onEffectsCleared = { [weak self] in self?.clickHearts.clear() }
        restorePosition()
        updater.onWillInstall = { [weak self] in self?.keyCounts.flush(); self?.savePosition() }
        companion.onCounterWidthChanged = { [weak self] in self?.keepOnScreen(); self?.savePosition() }
        createMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(topbarSlotChanged(_:)), name: NSWindow.didMoveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(topbarSlotChanged(_:)), name: NSWindow.didResizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(topbarSlotChanged(_:)), name: NSWindow.didChangeScreenNotification, object: nil)
        panel.orderFrontRegardless()
        panel.startPointerRouting()
        pet.start()

        if UserDefaults.standard.bool(forKey: "dog.topbarEnabled") {
            DispatchQueue.main.async { [weak self] in self?.setTopbarEnabled(true) }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.alignDesktopDogToTop(at: self.dogAnchor)
            }
        }
        keyCounts.onChange = { [weak self] in self?.updateCountMenu() }
        keyboard.onStatusChange = { [weak self] in self?.updateCountMenu() }
        keyboard.onPress = { [weak self] in
            guard let self else { return }
            self.keyCounts.recordPress()
            self.pet.keyboardPress()
            self.dogPreview?.keyboardPress()
        }
        keyboard.onClick = { [weak self] in
            guard let self else { return }
            self.keyCounts.recordPress()
            self.pet.pointerClick()
            self.dogPreview?.pointerClick()
        }
        keyboard.refresh()
        updateCountMenu()

        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Defer once so restored topbar/desktop placement is settled first.
        interactionHint.requestAutomatically()
        DispatchQueue.main.async { [weak self] in self?.updateInteractionHint() }
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "小狗菜单")
        statusItem.button?.toolTip = "小狗 · 安静陪你待着"
        let menu = NSMenu()
        menu.delegate = self
        let interactions = NSMenu()
        interactions.delegate = self
        sleepItem = item("打个盹", action: #selector(toggleSleep))
        interactions.addItem(item("摸摸它", action: #selector(petDog)))
        interactions.addItem(sleepItem)
        interactions.addItem(item("摇摇尾巴", action: #selector(wag)))
        let effects = NSMenu()
        effects.autoenablesItems = false
        let choices = InteractionEffectMenuView(
            selection: { [weak self] in self?.clickHearts.selection ?? InteractionEffectSelection() },
            onToggle: { [weak self] in self?.clickHearts.toggle($0) })
        effectChoices = choices
        let choiceItem = NSMenuItem()
        choiceItem.view = choices
        effects.addItem(choiceItem)
        let effectsItem = NSMenuItem(title: "互动特效", action: nil, keyEquivalent: "")
        effectsItem.submenu = effects
        interactions.addItem(.separator())
        interactions.addItem(effectsItem)
        let interactionItem = NSMenuItem(title: "互动", action: nil, keyEquivalent: "")
        interactionItem.submenu = interactions
        menu.addItem(interactionItem)
        visibilityItem = item("收起小狗", action: #selector(toggleVisibility))
        menu.addItem(visibilityItem)
        menu.addItem(.separator())

        let naps = NSMenu()
        for option in AutoNap.allCases {
            let entry = item(option.title, action: #selector(changeAutoNap(_:)))
            entry.tag = option.rawValue
            entry.state = option == autoNap ? .on : .off
            naps.addItem(entry)
        }
        autoNapItem = NSMenuItem(title: "自动打盹 · \(autoNap.title)", action: nil, keyEquivalent: "")
        autoNapItem.submenu = naps

        let appearance = NSMenu()
        positionLockItem = item("锁定位置", action: #selector(togglePositionLock))
        positionLockItem.state = pet.positionLocked ? .on : .off
        positionLockItem.toolTip = "按住摸摸；双击并按住第二下可临时拖动，松手自动恢复"
        appearance.addItem(positionLockItem)
        appearance.addItem(.separator())
        let sizes = NSMenu()
        for option in DogSize.allCases {
            let entry = item(option.title, action: #selector(changeSize(_:)))
            entry.tag = option.rawValue
            entry.state = abs(option.scale - scale) < 0.000001 ? .on : .off
            sizes.addItem(entry)
        }
        let size = NSMenuItem(title: "大小", action: nil, keyEquivalent: "")
        size.submenu = sizes
        appearance.addItem(size)
        sizeMenuItem = size
        let tails = NSMenu()
        for option in DogTailSize.allCases {
            let entry = item(option.title, action: #selector(changeTailSize(_:)))
            entry.tag = option.rawValue
            entry.state = option == tailSize ? .on : .off
            tails.addItem(entry)
        }
        let tail = NSMenuItem(title: "尾巴大小", action: nil, keyEquivalent: "")
        tail.submenu = tails
        appearance.addItem(tail)
        appearance.addItem(.separator())
        topbarItem = item("放进顶栏", action: #selector(toggleTopbar))
        appearance.addItem(topbarItem)
        topbarResetItem = item("重置顶栏位置", action: #selector(resetTopbarPosition))
        topbarResetItem.isHidden = true
        appearance.addItem(topbarResetItem)
        let directions = NSMenu()
        for direction in DogOrientation.allCases {
            let entry = item(direction.title, action: #selector(changeOrientation(_:)))
            entry.tag = direction.rawValue
            entry.state = direction == orientation ? .on : .off
            directions.addItem(entry)
            directionItems.append(entry)
        }
        let orientationItem = NSMenuItem(title: "朝向", action: nil, keyEquivalent: "")
        orientationItem.submenu = directions
        appearance.addItem(orientationItem)
        orientationMenuItem = orientationItem
        appearance.addItem(.separator())
        edgeItem = item(orientation.edgeTitle, action: #selector(resetPosition))
        appearance.addItem(edgeItem)
        let appearanceItem = NSMenuItem(title: "外观与摆放", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearance
        menu.addItem(appearanceItem)
        menu.addItem(autoNapItem)

        let countsMenu = NSMenu()
        countsMenu.delegate = self
        todayCountItem = NSMenuItem(title: "今日：0 次", action: nil, keyEquivalent: "")
        totalCountItem = NSMenuItem(title: "累计：0 次", action: nil, keyEquivalent: "")
        countStatusItem = NSMenuItem(title: "状态：未启用", action: nil, keyEquivalent: "")
        for entry in [todayCountItem!, totalCountItem!, countStatusItem!] {
            entry.isEnabled = false
            countsMenu.addItem(entry)
        }
        countsMenu.addItem(.separator())
        countToggleItem = item("启用点击次数…", action: #selector(toggleCounting))
        countsMenu.addItem(countToggleItem)
        alwaysCountItem = item("始终显示数字", action: #selector(toggleAlwaysCount))
        alwaysCountItem.state = companion.alwaysShowCount ? .on : .off
        countsMenu.addItem(alwaysCountItem)
        countsMenu.addItem(.separator())
        countRetryItem = item("重新检查权限并继续", action: #selector(retryCounting))
        countsMenu.addItem(countRetryItem)
        countsMenu.addItem(item("打开输入监控设置…", action: #selector(openInputSettings)))
        countMenuItem = NSMenuItem(title: "点击次数", action: nil, keyEquivalent: "")
        countMenuItem.submenu = countsMenu
        menu.addItem(countMenuItem)
        menu.addItem(.separator())

        let more = NSMenu()
        more.addItem(item("检查更新…", action: #selector(checkForUpdates(_:))))
        more.addItem(.separator())
        more.addItem(item("互动预览…", action: #selector(showDogPreview)))
        more.addItem(item("操作提示…", action: #selector(showInteractionHint)))
        more.addItem(item("隐私说明…", action: #selector(showPrivacy)))
        let moreItem = NSMenuItem(title: "更多", action: nil, keyEquivalent: "")
        moreItem.submenu = more
        menu.addItem(moreItem)
        menu.addItem(item("退出小狗", action: #selector(quit), key: "q"))
        statusItem.menu = menu
        pet.menu = menu
        companion.menu = menu
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleVisibility() {
        interactionHint.hide()
        defer { updateInteractionHint() }
        finishTurn()
        if topbarEnabled {
            topbarHidden.toggle()
            if topbarHidden {
                panel.stopPointerRouting(); panel.orderOut(nil); pet.stop()
                statusItem.length = NSStatusItem.squareLength
                statusItem.button?.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "小狗菜单")
            } else {
                reserveTopbarSlot()
                DispatchQueue.main.async { [weak self] in self?.placeTopbarDog() }
            }
            visibilityItem.title = topbarHidden ? "显示小狗" : "收起小狗"
            return
        }
        if panel.isVisible {
            panel.stopPointerRouting()
            panel.orderOut(nil)
            pet.stop()
            visibilityItem.title = "显示小狗"
        } else {
            panel.orderFrontRegardless()
            if !suspended { panel.startPointerRouting(); pet.start() }
            visibilityItem.title = "收起小狗"
        }
    }

    @objc private func toggleTopbar() { setTopbarEnabled(!topbarEnabled) }

    private func reserveTopbarSlot() {
        let free = topbarPosition != nil
        let length = free ? NSStatusItem.squareLength : DogTopbarRenderer.drawingSize(scale: scale, bandHeight: 22).width
        if statusItem.length != length { statusItem.length = length }
        statusItem.button?.image = free ? NSImage(systemSymbolName: "pawprint", accessibilityDescription: "小狗菜单") : nil
        statusItem.button?.setAccessibilityLabel(free ? "小狗菜单" : "小狗顶栏菜单")
    }

    @objc private func resetTopbarPosition() {
        interactionHint.hide()
        guard topbarEnabled else { return }
        topbarPosition = nil
        DogTopbarPosition.clear(from: .standard)
        guard !topbarHidden else { return }
        panel.stopPointerRouting(); panel.orderOut(nil); pet.stop()
        reserveTopbarSlot()
        DispatchQueue.main.async { [weak self] in self?.placeTopbarDog() }
    }

    private func setTopbarEnabled(_ enabled: Bool, restoringDesktop placement: DesktopPlacement? = nil) {
        guard enabled != topbarEnabled else { return }
        interactionHint.hide()
        finishTurn()
        if let placement { saveDesktopPlacement(placement) } else { savePosition() }
        panel.clearRotationSelection()
        topbarEnabled = enabled
        topbarHidden = false
        UserDefaults.standard.set(enabled, forKey: "dog.topbarEnabled")
        clickHearts.setTopbarMode(enabled)
        topbarItem.state = enabled ? .on : .off
        topbarItem.title = enabled ? "回到桌面" : "放进顶栏"
        topbarResetItem.isHidden = !enabled
        sizeMenuItem.isHidden = false
        orientationMenuItem.isHidden = enabled
        edgeItem.isHidden = enabled
        visibilityItem.title = "收起小狗"
        if enabled {
            reserveTopbarSlot()
            // Wait for AppKit to allocate this item's own slot; no free-space polling.
            panel.stopPointerRouting(); panel.orderOut(nil); pet.stop()
            DispatchQueue.main.async { [weak self] in self?.placeTopbarDog() }
        } else {
            companion.topbarHeight = nil
            companion.orientation = orientation
            companion.scale = scale
            panel.level = .floating
            statusItem.length = NSStatusItem.squareLength
            statusItem.button?.image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "小狗菜单")
            statusItem.button?.setAccessibilityLabel("小狗菜单")
            restorePosition()
            panel.orderFrontRegardless()
            if !suspended { panel.startPointerRouting(); pet.start() }
        }
    }

    @objc private func topbarSlotChanged(_ notification: Notification) {
        guard topbarEnabled, let window = notification.object as? NSWindow,
              window === statusItem?.button?.window else { return }
        placeTopbarDog()
    }

    private func placeTopbarDog() {
        guard topbarEnabled, !topbarHidden, !suspended else { return }
        let frame: CGRect?
        var bandHeight: CGFloat = 22
        if let position = topbarPosition,
           let screen = NSScreen.screens.first(where: { displayID(of: $0) == position.displayID })
                ?? statusItem.button?.window?.screen ?? NSScreen.screens.first {
            bandHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            frame = DogTopbarPlacement.freeFrame(
                centerX: screen.frame.minX + position.fraction * screen.frame.width,
                screen: screen.frame, topInset: screen.safeAreaInsets.top,
                menuHeight: NSStatusBar.system.thickness,
                left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                drawingSize: topbarDrawingSize(on: screen), attachmentY: screen.visibleFrame.maxY)
        } else if let button = statusItem.button, let window = button.window, let screen = window.screen {
            bandHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let slot = window.convertToScreen(button.convert(button.bounds, to: nil))
            frame = DogTopbarPlacement.frame(slot: slot, screen: screen.frame,
                topInset: screen.safeAreaInsets.top, menuHeight: NSStatusBar.system.thickness,
                left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                drawingSize: topbarDrawingSize(on: screen), attachmentY: screen.visibleFrame.maxY)
        } else { frame = nil }
        guard let frame else {
            interactionHint.hide()
            panel.stopPointerRouting(); panel.orderOut(nil); pet.stop()
            return
        }
        companion.scale = scale
        companion.topbarHeight = bandHeight
        companion.orientation = .bottom
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.setPetFrame(frame)
        companion.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        panel.startPointerRouting()
        if !pet.hasPointerCapture { pet.start() }
    }

    private func topbarDrawingSize(on screen: NSScreen) -> NSSize {
        let menuHeight = max(22, screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness)
        return DogTopbarRenderer.drawingSize(scale: scale,
            bandHeight: max(menuHeight, screen.frame.maxY - screen.visibleFrame.maxY))
    }

    private func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    @objc private func toggleSleep() {
        if pet.motion.sleepStarted == nil { pet.rest() } else { pet.wake() }
    }

    @objc private func wag() { pet.wag() }
    @objc private func petDog() {
        if !panel.isVisible { toggleVisibility() }
        pet.pet()
    }

    @objc private func togglePositionLock() {
        pet.positionLocked.toggle()
        positionLockItem.state = pet.positionLocked ? .on : .off
        UserDefaults.standard.set(pet.positionLocked, forKey: PetView.positionLockKey)
        dogPreview?.setPositionLocked(pet.positionLocked)
        panel.refreshPointerRouting()
    }

    @objc private func checkForUpdates(_ sender: Any?) { updater.checkForUpdates(sender) }

    @objc private func changeAutoNap(_ sender: NSMenuItem) {
        guard let option = AutoNap(rawValue: sender.tag) else { return }
        autoNap = option
        UserDefaults.standard.set(option.rawValue, forKey: AutoNap.preferenceKey)
        pet.setAutoNap(option)
        dogPreview?.setAutoNap(option)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        autoNapItem.title = "自动打盹 · \(option.title)"
    }

    func menuWillOpen(_ menu: NSMenu) {
        openHintMenus.insert(ObjectIdentifier(menu))
        interactionHint.hide()
        pet.cancelPointerInteraction()
        effectChoices?.refresh()
        sleepItem.title = pet.motion.sleepStarted == nil ? "打个盹" : "醒醒"
        keyCounts.refreshDay()
        keyboard.refresh()
        updateCountMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        openHintMenus.remove(ObjectIdentifier(menu))
        DispatchQueue.main.async { [weak self] in self?.updateInteractionHint() }
    }

    @objc private func showInteractionHint() {
        interactionHint.showManually()
        if !panel.isVisible { toggleVisibility() }
        updateInteractionHint()
    }

    private func updateInteractionHint() {
        guard interactionHint.isRequested, let panel, let pet, let companion else { return }
        guard !suspended, openHintMenus.isEmpty, panel.isVisible, !panel.isMiniaturized,
              !pet.hasPointerCapture, turning == nil else { interactionHint.hide(); return }
        guard let screen = dogScreen ?? panel.screen ?? NSScreen.main,
              let fullAnchor = pet.interactionHintFrame else { interactionHint.hide(); return }
        let anchor = fullAnchor.intersection(screen.frame)
        guard !anchor.isNull, !anchor.isEmpty else { interactionHint.hide(); return }
        // Reserve the counter's potential area even while its hover fade is hidden,
        // so the hint never jumps or covers it when the pointer approaches.
        let obstacle = topbarEnabled ? nil : panel.convertToScreen(companion.convert(companion.badgeFrame, to: nil))
        interactionHint.update(anchor: anchor, obstacle: obstacle, screen: screen.visibleFrame,
            visible: true, level: panel.level, positionLocked: pet.positionLocked, owner: panel)
    }

    private func updateCountMenu() {
        guard countMenuItem != nil else { return }
        let today = keyCounts.counts.today.formatted()
        let total = keyCounts.counts.total.formatted()
        todayCountItem.title = "今日：\(today) 次"
        totalCountItem.title = "累计：\(total) 次"
        companion.updateCount(keyCounts.counts.total)
        countStatusItem.title = "状态：\(keyboard.status.label)"
        countToggleItem.title = keyboard.desired ? "暂停点击次数" : "启用点击次数…"
        countRetryItem.isHidden = !keyboard.desired || keyboard.status == .running
        countMenuItem.title = "点击次数"
        statusItem.button?.toolTip = "小狗 · 点击次数 \(total) · \(keyboard.status.label)"
    }

    @objc private func toggleAlwaysCount() {
        companion.alwaysShowCount.toggle()
        alwaysCountItem.state = companion.alwaysShowCount ? .on : .off
        UserDefaults.standard.set(companion.alwaysShowCount, forKey: "dog.alwaysShowCount")
    }

    @objc private func toggleCounting() {
        keyboard.setEnabled(!keyboard.desired)
        if !keyboard.desired { keyCounts.flush() }
        updateCountMenu()
    }

    @objc private func retryCounting() { keyboard.refresh(retry: true); updateCountMenu() }

    @objc private func openInputSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        keyboard.refresh()
        keyCounts.refreshDay()
    }

    private func pinDesktopDog() {
        if topbarEnabled { setTopbarEnabled(false) }
        resetPosition()
        if !panel.isVisible { toggleVisibility() }
    }

    private func hideDesktopDog() {
        if panel.isVisible { toggleVisibility() }
    }

    private var dogAnchor: NSPoint {
        let canonical = orientation.rotatedSize(pet.bounds.size)
        let point = NSPoint(x: canonical.width / 2, y: 1 + DogRenderer.baselineY * scale)
            .applying(orientation.transform(size: canonical))
        return panel.convertPoint(toScreen: pet.convert(point, to: nil))
    }

    private var dogScreen: NSScreen? {
        // Transparent canvas may overlap another display. Prefer the actual
        // baseline anchor before comparing complete window rectangles.
        let anchor = turning?.targetAnchor ?? dogAnchor
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) { return screen }
        return NSScreen.screens.max { a, b in
            let first = a.frame.intersection(panel.frame)
            let second = b.frame.intersection(panel.frame)
            return (first.isNull ? 0 : first.width * first.height) < (second.isNull ? 0 : second.width * second.height)
        }
    }

    private func desktopArea(on screen: NSScreen) -> NSRect {
        var area = screen.visibleFrame
        // Preserve Dock clearance, but make the menu-bar height available too.
        area.size.height = screen.frame.maxY - area.minY
        return area
    }

    private func placeDog(anchor: NSPoint, on screen: NSScreen) {
        guard !topbarEnabled else { placeTopbarDog(); return }
        let placement = DogWindowPlacement(anchor: anchor, scale: scale, orientation: orientation,
                                          badgeWidth: companion.counterWidth, visibleFrame: desktopArea(on: screen),
                                          allowsPartialVisibility: true)
        companion.scale = scale
        companion.orientation = orientation
        companion.counterAboveDog = placement.counterAboveDog
        panel.setPetFrame(placement.frame)
        companion.layoutSubtreeIfNeeded()
        refreshDesktopLevel()
        panel.refreshPointerRouting()
    }

    private func refreshDesktopLevel() {
        guard !topbarEnabled else { return }
        let bands = NSScreen.screens.map { screen in
            let height = max(22, screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness)
            return NSRect(x: screen.frame.minX, y: screen.frame.maxY - height,
                          width: screen.frame.width, height: height)
        }
        clickHearts.setTopbarMode(panel.updateDesktopLevel(menuBands: bands))
    }

    @objc private func changeSize(_ sender: NSMenuItem) {
        guard let option = DogSize(rawValue: sender.tag) else { return }
        finishTurn()
        if topbarEnabled {
            scale = option.scale
            UserDefaults.standard.set(scale, forKey: "dog.scale")
            sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
            if !topbarHidden {
                reserveTopbarSlot()
                DispatchQueue.main.async { [weak self] in self?.placeTopbarDog() }
            }
            return
        }
        guard let screen = dogScreen else { return }
        let oldAnchor = dogAnchor
        scale = option.scale
        placeDog(anchor: oldAnchor, on: screen)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        UserDefaults.standard.set(scale, forKey: "dog.scale")
        savePosition()
    }

    @objc private func changeOrientation(_ sender: NSMenuItem) {
        guard let direction = DogOrientation(rawValue: sender.tag) else { return }
        setOrientation(direction)
    }

    @objc private func changeTailSize(_ sender: NSMenuItem) {
        guard let option = DogTailSize(rawValue: sender.tag) else { return }
        tailSize = option
        pet.tailSize = option
        dogPreview?.setTailSize(option)
        UserDefaults.standard.set(option.rawValue, forKey: DogTailSize.preferenceKey)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        panel.refreshPointerRouting()
    }

    private func setOrientation(_ direction: DogOrientation) {
        guard !topbarEnabled else { return }
        guard let screen = dogScreen else { return }
        guard direction != orientation else { return }
        let time = now
        let canonical = NSSize(width: DogRenderer.canvas.width * scale, height: DogRenderer.canvas.height * scale)
        let oldPivot = DogTurnPresentation.pivot(in: canonical).applying(orientation.transform(size: canonical))
        let from = turning.map { $0.pausedPose ?? $0.motion.pose(now: time) } ?? DogTurnPose(
            angle: Double(orientation.rawValue),
            center: panel.convertPoint(toScreen: pet.convert(oldPivot, to: nil)),
            badgeCenter: panel.convertPoint(toScreen: companion.convert(NSPoint(x: companion.badgeFrame.midX, y: companion.badgeFrame.midY), to: nil)))
        let velocity = turning.flatMap { $0.pausedPose == nil ? $0.motion.velocity(now: time) : nil }
        orientation = direction
        let pivot = DogTurnPresentation.pivot(in: canonical).applying(orientation.transform(size: canonical))
        let edge = NSPoint(x: canonical.width / 2, y: 1 + DogRenderer.baselineY * scale)
            .applying(orientation.transform(size: canonical))
        let anchor = NSPoint(x: from.center.x - pivot.x + edge.x,
                             y: from.center.y - pivot.y + edge.y)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !panel.isVisible || suspended {
            turning = nil
            companion.turnFrames = nil
            pet.setTurnPresentation(nil)
            placeDog(anchor: anchor, on: screen)
        } else {
            startTurn(from: from, velocity: velocity, anchor: anchor, on: screen)
        }
        directionItems.forEach { $0.state = $0.tag == direction.rawValue ? .on : .off }
        edgeItem.title = orientation.edgeTitle
        UserDefaults.standard.set(orientation.rawValue, forKey: DogOrientation.preferenceKey)
        savePosition()
    }

    @objc private func resetPosition() {
        if topbarEnabled { setTopbarEnabled(false) }
        finishTurn()
        guard let screen = dogScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame
        let halfLength = DogRenderer.canvas.width * scale / 2
        let anchor: NSPoint
        switch orientation {
        case .bottom: anchor = NSPoint(x: area.maxX - halfLength - 28, y: area.minY)
        case .top: anchor = NSPoint(x: area.maxX - halfLength - 28, y: area.maxY)
        case .left: anchor = NSPoint(x: area.minX, y: area.midY)
        case .right: anchor = NSPoint(x: area.maxX, y: area.midY)
        }
        placeDog(anchor: anchor, on: screen)
        savePosition()
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "dog.x") != nil else { resetPosition(); return }
        panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "dog.x"), y: defaults.double(forKey: "dog.y")))
        guard let screen = dogScreen else { return }
        if defaults.object(forKey: "dog.anchorX") != nil, defaults.object(forKey: "dog.anchorY") != nil {
            placeDog(anchor: NSPoint(x: defaults.double(forKey: "dog.anchorX"), y: defaults.double(forKey: "dog.anchorY")), on: screen)
            return
        }
        let baseline: CGFloat
        if defaults.object(forKey: "dog.baselineY") != nil {
            baseline = defaults.double(forKey: "dog.baselineY")
        } else if panel.frame.minY <= screen.visibleFrame.minY + 1 {
            // Older builds put the footer on the edge and lifted the dog by 24 points.
            baseline = screen.visibleFrame.minY
        } else { baseline = panel.frame.minY + DogCompanionView.footerHeight + 1 + DogRenderer.baselineY * scale }
        placeDog(anchor: NSPoint(x: panel.frame.minX + DogRenderer.canvas.width * scale / 2, y: baseline), on: screen)
        savePosition()
    }

    private func savePosition() {
        if topbarEnabled { topbarPosition?.save(to: .standard); return }
        saveDesktopPlacement(currentDesktopPlacement)
    }

    private var currentDesktopPlacement: DesktopPlacement {
        let anchor = turning?.targetAnchor ?? dogAnchor
        let frame = turning.map {
            DogWindowPlacement(anchor: $0.targetAnchor, scale: scale, orientation: orientation,
                               badgeWidth: companion.counterWidth, visibleFrame: desktopArea(on: $0.screen),
                               allowsPartialVisibility: true).frame
        } ?? panel.frame
        return DesktopPlacement(frame: frame, anchor: anchor)
    }

    private func saveDesktopPlacement(_ placement: DesktopPlacement) {
        let frame = placement.frame, anchor = placement.anchor
        UserDefaults.standard.set(frame.minX, forKey: "dog.x")
        UserDefaults.standard.set(frame.minY, forKey: "dog.y")
        UserDefaults.standard.set(anchor.x, forKey: "dog.anchorX")
        UserDefaults.standard.set(anchor.y, forKey: "dog.anchorY")
        if orientation == .bottom { UserDefaults.standard.set(anchor.y, forKey: "dog.baselineY") }
    }

    private func keepOnScreen() {
        if topbarEnabled { placeTopbarDog(); return }
        guard turning == nil else { return }
        guard let screen = dogScreen else { return }
        placeDog(anchor: dogAnchor, on: screen)
    }

    @objc private func screenChanged() { finishTurn(); keepOnScreen(); savePosition() }
    @objc private func willSleep() {
        suspended = true
        interactionHint.hide()
        finishTurn()
        panel.stopPointerRouting()
        pet.stop()
        keyboard.suspend()
        keyCounts.flush()
    }
    @objc private func didWake() {
        suspended = false
        if topbarEnabled { placeTopbarDog() }
        else if panel.isVisible { panel.startPointerRouting(); pet.start() }
        keyCounts.refreshDay()
        keyboard.resume()
    }

    private func startTurn(from: DogTurnPose, velocity: DogTurnPose?, anchor: NSPoint, on screen: NSScreen) {
        let placement = DogWindowPlacement(anchor: anchor, scale: scale, orientation: orientation,
            badgeWidth: companion.counterWidth, visibleFrame: desktopArea(on: screen),
            allowsPartialVisibility: true)
        let layout = DogLayout(scale: scale, orientation: orientation,
            counterInside: placement.counterAboveDog, badgeWidth: companion.counterWidth)
        let canonical = NSSize(width: DogRenderer.canvas.width * scale, height: DogRenderer.canvas.height * scale)
        let pivot = DogTurnPresentation.pivot(in: canonical).applying(orientation.transform(size: canonical))
        let center = NSPoint(x: placement.frame.minX + layout.petFrame.minX + pivot.x,
                             y: placement.frame.minY + layout.petFrame.minY + pivot.y)
        let badge = NSPoint(x: placement.frame.minX + layout.badgeFrame.midX,
                            y: placement.frame.minY + layout.badgeFrame.midY)
        let remaining = (Double(orientation.rawValue) - from.angle).truncatingRemainder(dividingBy: 360)
        let motion = DogTurnMotion(now: now, from: from, targetAngle: Double(orientation.rawValue),
            center: center, badgeCenter: badge, velocity: velocity,
            duration: abs(remaining) < 0.00001 ? 0.18 : nil)
        let side = DogTurnPresentation.enclosingSide(for: canonical)
        var envelope = NSRect.null
        // Include the full sweep and retargeting momentum; no clipping at the intermediate angles.
        for index in 0...24 {
            let pose = motion.pose(now: motion.started + motion.duration * Double(index) / 24)
            envelope = envelope.union(NSRect(x: pose.center.x - side / 2, y: pose.center.y - side / 2,
                                             width: side, height: side))
            envelope = envelope.union(NSRect(x: pose.badgeCenter.x - companion.counterWidth / 2 - 4,
                y: pose.badgeCenter.y - 13, width: companion.counterWidth + 8, height: 26))
        }
        envelope = envelope.union(NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
        companion.orientation = orientation
        pet.setTurnPresentation(DogTurnPresentation(canonicalSize: NSSize(width: DogRenderer.canvas.width * scale,
            height: DogRenderer.canvas.height * scale), angle: from.angle))
        panel.setPetFrame(envelope.integral)
        refreshDesktopLevel()
        turning = TurnState(motion: motion, screen: screen,
            targetAnchor: NSPoint(x: placement.frame.minX + layout.baselineAnchor.x,
                                  y: placement.frame.minY + layout.baselineAnchor.y))
        advanceTurn()
    }

    private func advanceTurn() {
        guard let state = turning, state.pausedPose == nil else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { finishTurn(); return }
        let time = now
        if state.motion.isFinished(now: time) { finishTurn(); return }
        let pose = state.motion.pose(now: time)
        let center = companion.convert(panel.convertPoint(fromScreen: pose.center), from: nil)
        let badge = companion.convert(panel.convertPoint(fromScreen: pose.badgeCenter), from: nil)
        let canonical = NSSize(width: DogRenderer.canvas.width * scale, height: DogRenderer.canvas.height * scale)
        let side = DogTurnPresentation.enclosingSide(for: canonical)
        companion.turnFrames = (NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side),
            NSRect(x: badge.x - companion.counterWidth / 2, y: badge.y - 9, width: companion.counterWidth, height: 18))
        companion.layoutSubtreeIfNeeded()
        pet.setTurnPresentation(DogTurnPresentation(canonicalSize: canonical, angle: pose.angle))
    }

    private func finishTurn() {
        guard let state = turning else { return }
        turning = nil
        companion.turnFrames = nil
        pet.setTurnPresentation(nil)
        placeDog(anchor: state.targetAnchor, on: state.screen)
        savePosition()
    }

    private func pauseTurn() {
        advanceTurn()
        guard var state = turning else { return }
        state.pausedPose = state.motion.pose(now: now)
        turning = state
    }

    private func dragDesktop(to offset: NSPoint, pointer cursor: NSPoint) {
        if topbarEnabled {
            // Only our own drag reaches here. Use that event's screen point so
            // a later global cursor sample cannot detach a horizontal drag.
            let pressedY = topbarDragPressY ?? (cursor.y - offset.y)
            topbarDragPressY = pressedY
            let menuScreen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? panel.screen
            guard let menuScreen else { return }
            let bandHeight = max(22, menuScreen.safeAreaInsets.top > 0 ? menuScreen.safeAreaInsets.top : NSStatusBar.system.thickness)
            let band = CGRect(x: menuScreen.frame.minX, y: menuScreen.frame.maxY - bandHeight,
                              width: menuScreen.frame.width, height: bandHeight)
            if !DogTopbarPlacement.shouldDetach(pointerY: cursor.y, frame: band, pressedY: pressedY),
               let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? panel.screen,
               let frame = DogTopbarPlacement.freeFrame(
                    centerX: (topbarDragCenterX ?? panel.petFrame.midX) + offset.x,
                    screen: screen.frame, topInset: screen.safeAreaInsets.top,
                    menuHeight: NSStatusBar.system.thickness,
                    left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                    drawingSize: topbarDrawingSize(on: screen), attachmentY: screen.visibleFrame.maxY) {
                // Use the original press origin, not the clamped frame. Otherwise
                // dragging through the notch would get stuck at its first edge.
                topbarPosition = DogTopbarPosition(
                    fraction: (frame.midX - screen.frame.minX) / screen.frame.width,
                    displayID: displayID(of: screen))
                reserveTopbarSlot()
                placeTopbarDog()
                previousDragOffset = offset
                return
            }
            setTopbarEnabled(false)
            let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) }) ?? dogScreen
            if let screen {
                let anchor = NSPoint(x: cursor.x + (130 - 108) * scale,
                    y: cursor.y - (42 - DogRenderer.baselineY) * scale)
                placeDog(anchor: anchor, on: screen)
            }
            previousDragOffset = offset
            return
        }
        let delta = NSPoint(x: offset.x - previousDragOffset.x, y: offset.y - previousDragOffset.y)
        previousDragOffset = offset
        panel.setPetFrame(panel.petFrame.offsetBy(dx: delta.x, dy: delta.y))
        refreshDesktopLevel()
        guard var state = turning else { return }
        state.motion = state.motion.translated(by: delta)
        state.targetAnchor.x += delta.x; state.targetAnchor.y += delta.y
        if var pose = state.pausedPose {
            pose.center.x += delta.x; pose.center.y += delta.y
            pose.badgeCenter.x += delta.x; pose.badgeCenter.y += delta.y
            state.pausedPose = pose
        }
        turning = state
        advanceTurn()
    }

    private func finishDesktopDrag(at point: NSPoint) {
        if alignDesktopDogToTop(at: point) { return }
        keepOnScreen()
        savePosition()
    }

    @discardableResult
    private func alignDesktopDogToTop(at point: NSPoint) -> Bool {
        if !topbarEnabled {
            let screens = NSScreen.screens
            let ordered = screens.filter { $0.frame.contains(point) } + screens.filter { !$0.frame.contains(point) }
            let head = pet.desktopDockingFrame
            for screen in ordered {
                guard let frame = DogTopbarPlacement.dropFrame(pointer: point, startedInTopbar: dragStartedInTopbar,
                screen: screen.frame, topInset: screen.safeAreaInsets.top,
                menuHeight: NSStatusBar.system.thickness,
                left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                drawingSize: topbarDrawingSize(on: screen),
                dogFrame: head, centerX: dogAnchor.x, attachmentY: screen.visibleFrame.maxY) else { continue }
                topbarPosition = DogTopbarPosition(
                    fraction: (frame.midX - screen.frame.minX) / screen.frame.width,
                    displayID: displayID(of: screen))
                setTopbarEnabled(true, restoringDesktop: desktopPlacementBeforeDrag)
                savePosition()
                return true
            }
        }
        return false
    }

    private func resumeTurn() {
        guard let state = turning else { return }
        let time = now
        let pose = state.pausedPose ?? state.motion.pose(now: time)
        let velocity = state.pausedPose == nil ? state.motion.velocity(now: time) : nil
        startTurn(from: pose, velocity: velocity, anchor: state.targetAnchor, on: dogScreen ?? state.screen)
        savePosition()
    }

    @objc private func showPrivacy() {
        let alert = NSAlert()
        alert.messageText = "小狗只关心你有没有摸摸它"
        alert.informativeText = "点击次数默认关闭，启用时 macOS 会要求“输入监控”授权。系统权限范围较广，计数只提取按下事件类型与长按重复标志，不解析字符、键位或鼠标位置。\n\n键盘、鼠标和触控板合并为同一个“点击次数”，只保存本地今日次数、累计次数、当前日期，另保存小狗位置、大小、朝向、启用、数字显示、自动打盹和互动特效搭配偏好。不保存输入内容、事件顺序、应用、网址、剪贴板或截图。日常陪伴和计数在本地完成；只有主动选择“检查更新”和确认下载时才访问官网，不上传计数或输入内容，没有后台检查。更新服务器会收到普通网络连接信息（例如 IP 地址）。\n\n透明区点击穿透仅临时判断当前光标是否在小狗或数字框上，不保存坐标或轨迹，不需要新增权限。点击位置仅用于当前互动特效动画，约两秒后清除，不与计数关联。\n\n普通按键每次按下计一次，长按重复不计，单独修饰键不计。鼠标与触控板的左、右及其他按钮按下计一，双击计二；抬起、移动、滚动与拖动过程不计。隐藏小狗后仍计数，可从“点击次数”菜单随时暂停；系统休眠时停止监听。系统保护期间可能漏计。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func showDogPreview() {
        if dogPreview == nil {
            dogPreview = DogPreviewController(desktopDog: pet, autoNap: autoNap,
                onPet: { [weak self] in self?.clickHearts.emit(at: $0) ?? false },
                onEffectsFrame: { [weak self] in self?.clickHearts.advance() },
                onEffectsCleared: { [weak self] in self?.clickHearts.clear() },
                onPinDesktop: { [weak self] in self?.pinDesktopDog() },
                onHideDesktop: { [weak self] in self?.hideDesktopDog() })
        }
        dogPreview?.present()
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        suspended = true
        interactionHint.hide()
        keyboard.stop()
        clickHearts.clear()
        panel?.stopPointerRouting()
        keyCounts.flush()
        pet?.stop()
        dogPreview?.stop()
    }
}
