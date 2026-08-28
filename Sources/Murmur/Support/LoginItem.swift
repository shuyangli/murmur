import Foundation
import ServiceManagement

/// Registers Murmur to start when the user logs in.
///
/// `SMAppService` only works for a signed app bundle launched from its final
/// location, so this quietly reports failure when running the raw executable
/// out of the build directory.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS has the registration on file but the user switched it
    /// off in System Settings, which the app cannot override.
    static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            Log.app.error("Could not change the login item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
