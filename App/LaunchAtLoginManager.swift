import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    private static let defaultsKey = "startAtLoginEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func syncPreferenceAtLaunch() {
        _ = setEnabled(isEnabled)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let currentStatus = SMAppService.mainApp.status
        let alreadyEnabled = currentStatus == .enabled || currentStatus == .requiresApproval
        if alreadyEnabled == enabled {
            UserDefaults.standard.set(enabled, forKey: defaultsKey)
            return true
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            UserDefaults.standard.set(enabled, forKey: defaultsKey)
            return true
        } catch {
            NSLog("Failed to update start-at-login state: \(error.localizedDescription)")
            return false
        }
    }
}
