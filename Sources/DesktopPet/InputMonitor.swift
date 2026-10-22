import AppKit
import CoreGraphics

enum KeyPressPolicy {
    static func accepts(_ type: CGEventType, repeating: Bool) -> Bool {
        type == .keyDown && !repeating
    }
}

enum PointerClickPolicy {
    static func accepts(_ type: CGEventType) -> Bool {
        type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
    }
}

/// This boundary reads only event type and autorepeat. No key code, text, flags,
/// pointer position, target app, source process, event timestamp or event object escapes.
private func countInputDown(_ proxy: CGEventTapProxy, _ type: CGEventType,
                          _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let repeating = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let monitor = Unmanaged<InputMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // The tap source is installed exclusively on the main run loop.
    MainActor.assumeIsolated { monitor.receive(type: type, repeating: repeating) }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class InputMonitor {
    enum Status: Equatable {
        case off, running, needsPermission, unavailable, interrupted, sleeping

        var label: String {
            switch self {
            case .off: return "未启用 / 已暂停"
            case .running: return "计数中"
            case .needsPermission: return "等待输入监控授权"
            case .unavailable: return "监听未启动，请重新检查"
            case .interrupted: return "系统已中断，请重新检查"
            case .sleeping: return "系统休眠，计数已暂停"
            }
        }
    }

    private let defaults: UserDefaults
    private let permissionCheck: () -> Bool
    private let permissionRequest: () -> Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var suspended = false
    private var interrupted = false
    private(set) var desired: Bool
    private(set) var status = Status.off {
        didSet { if oldValue != status { onStatusChange?() } }
    }
    var onPress: (() -> Void)?
    var onClick: (() -> Void)?
    var onStatusChange: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         permissionCheck: @escaping () -> Bool = CGPreflightListenEventAccess,
         permissionRequest: @escaping () -> Bool = CGRequestListenEventAccess) {
        self.defaults = defaults
        self.permissionCheck = permissionCheck
        self.permissionRequest = permissionRequest
        desired = defaults.bool(forKey: "keyboard.countingEnabled")
    }

    var hasPermission: Bool { permissionCheck() }

    func setEnabled(_ enabled: Bool) {
        desired = enabled
        defaults.set(enabled, forKey: "keyboard.countingEnabled")
        interrupted = false
        if enabled, !hasPermission { _ = permissionRequest() }
        refresh()
    }

    /// Checking permission never prompts. Only the explicit enable action requests it.
    func refresh(retry: Bool = false) {
        if retry { interrupted = false }
        guard desired else { stop(); status = .off; return }
        guard !suspended else { stop(); status = .sleeping; return }
        guard hasPermission else { stop(); status = .needsPermission; return }
        guard !interrupted else { status = .interrupted; return }
        if let tap, CGEvent.tapIsEnabled(tap: tap) { status = .running; return }
        stop()
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: countInputDown,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status = hasPermission ? .unavailable : .needsPermission
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            status = .unavailable
            return
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = CGEvent.tapIsEnabled(tap: tap) ? .running : .unavailable
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
    }

    func suspend() { suspended = true; stop(); status = desired ? .sleeping : .off }
    func resume() { suspended = false; refresh() }

    func receive(type: CGEventType, repeating: Bool) {
        if type == .tapDisabledByTimeout {
            guard desired, !suspended, hasPermission, let tap else { refresh(); return }
            CGEvent.tapEnable(tap: tap, enable: true)
            status = CGEvent.tapIsEnabled(tap: tap) ? .running : .unavailable
        } else if type == .tapDisabledByUserInput {
            interrupted = true
            status = .interrupted
        } else if desired, !suspended, status == .running {
            if KeyPressPolicy.accepts(type, repeating: repeating) { onPress?() }
            else if PointerClickPolicy.accepts(type) { onClick?() }
        }
    }
}
