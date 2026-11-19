import AppKit
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// The user's login item is the source of truth, including changes in System Settings.
@MainActor
final class LoginAtStartup: NSObject, NSMenuDelegate {
    private let service: any LoginItemService
    private static let title = "登录时自动启动"

    lazy var item: NSMenuItem = {
        let item = NSMenuItem(title: Self.title, action: #selector(selectItem), keyEquivalent: "")
        item.target = self
        return item
    }()

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    private func refresh() {
        let status = service.status
        switch status {
        case .enabled, .notRegistered:
            item.title = Self.title
            item.state = status == .enabled ? .on : .off
        case .requiresApproval:
            item.title = "登录时自动启动（待系统允许）…"
            item.state = .mixed
        default:
            item.title = "登录时自动启动（暂不可用）…"
            item.state = .off
        }
    }

    /// Apply the visible menu choice even if the system setting changed while the menu was open.
    func setEnabled(_ enabled: Bool) throws -> SMAppService.Status {
        let before = service.status
        do {
            if enabled && before == .notRegistered {
                try service.register()
            } else if !enabled && (before == .enabled || before == .requiresApproval) {
                try service.unregister()
            } else {
                return before
            }
        } catch {
            // A user decision or a concurrent system change can race the service call.
            let after = service.status
            if enabled && (after == .enabled || after == .requiresApproval) { return after }
            if !enabled && after == .notRegistered { return after }
            throw error
        }
        return service.status
    }

    @objc private func selectItem() {
        let enable = item.state != .on
        defer { refresh() }
        do {
            let after = try setEnabled(enable)
            if after == .requiresApproval {
                showApprovalChoices()
            } else if enable ? after != .enabled : after != .notRegistered {
                showFailure("请将小狗放到“应用程序”文件夹，从那里打开后再试。")
            }
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    private func showApprovalChoices() {
        let alert = NSAlert()
        alert.messageText = "登录时自动启动需要系统允许"
        alert.informativeText = "打开系统设置，在“登录项”中允许小狗，就能在下次登录时见到它。"
        alert.addButton(withTitle: "打开登录项设置")
        alert.addButton(withTitle: "稍后")
        alert.addButton(withTitle: "取消自动启动")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            SMAppService.openSystemSettingsLoginItems()
        case .alertThirdButtonReturn:
            do {
                if try setEnabled(false) != .notRegistered { showFailure("请在系统设置的“登录项”中移除小狗。") }
            } catch {
                showFailure(error.localizedDescription)
            }
        default:
            break
        }
    }

    private func showFailure(_ detail: String) {
        let alert = NSAlert()
        alert.messageText = "无法更改登录时自动启动"
        alert.informativeText = detail
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
