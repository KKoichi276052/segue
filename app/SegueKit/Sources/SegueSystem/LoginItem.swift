import ServiceManagement

/// Launch at login through `SMAppService` (docs/SPEC.md §11 M1 step 10). Works best with
/// Segue in /Applications; macOS lists it in System Settings › General › Login Items.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            Log.app.error("launch at login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
