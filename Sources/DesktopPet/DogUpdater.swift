import AppKit
import Sparkle

struct DogUpdateConfiguration {
    let feedURL: URL
    let publicKey: Data

    init?(info: [String: Any]) {
        guard let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let encoded = info["SUPublicEDKey"] as? String,
              let key = Data(base64Encoded: encoded), key.count == 32,
              info["SUEnableAutomaticChecks"] as? Bool == false,
              info["SUAllowsAutomaticUpdates"] as? Bool == false,
              info["SUEnableSystemProfiling"] as? Bool == false,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SURequireSignedFeed"] as? Bool == true else { return nil }
        feedURL = url
        publicKey = key
    }
}

/// No updater object, scheduling or network work until an explicit menu action.
@MainActor
final class DogUpdater: NSObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    var onWillInstall: (() -> Void)?

    func checkForUpdates(_ sender: Any?) {
        guard DogUpdateConfiguration(info: Bundle.main.infoDictionary ?? [:]) != nil else {
            let alert = NSAlert()
            alert.messageText = "更新暂时不可用"
            alert.informativeText = "这个版本的更新配置不完整，小狗可以照常使用。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }
        if let controller {
            guard controller.updater.canCheckForUpdates else { return }
            controller.checkForUpdates(sender)
            return
        }
        let newController = SPUStandardUpdaterController(startingUpdater: false,
            updaterDelegate: self, userDriverDelegate: nil)
        controller = newController
        newController.updater.userAgentString = "DesktopPet-Updater"
        newController.startUpdater()
        DispatchQueue.main.async { newController.checkForUpdates(nil) }
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] { [] }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { onWillInstall?() }
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { onWillInstall?(); return true }
}
