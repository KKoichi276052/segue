import AppKit
import SegueCore
import SegueSystem
import SegueUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private var permissionsWindow: PermissionsWindowController?
    private var permissions = PermissionsCoordinator.current()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Segue \(SegueVersion.string, privacy: .public) launched; \(PermissionsCoordinator.describe(self.permissions), privacy: .public)")
        menuBar.willOpen = { [weak self] in self?.refreshPermissions() }
        menuBar.mainItems = { [weak self] in self?.mainMenuItems() ?? [] }
        refreshMenu()
        if PermissionsFlow.step(for: permissions, screenRecordingSkipped: Settings.screenRecordingSkipped) != .done {
            showPermissions()
        }
    }

    // MARK: Permissions

    private func refreshPermissions() {
        let status = PermissionsCoordinator.current()
        if status != permissions {
            Log.permissions.info("changed: \(PermissionsCoordinator.describe(status), privacy: .public)")
            permissions = status
        }
        refreshMenu()
    }

    private func showPermissions() {
        if permissionsWindow == nil {
            permissionsWindow = PermissionsWindowController(macOSMajor: PermissionsCoordinator.macOSMajor, actions: .init(
                status: { PermissionsCoordinator.current() },
                request: { PermissionsCoordinator.request($0) },
                openSettings: { PermissionsCoordinator.openSettings($0) },
                relaunch: { PermissionsCoordinator.relaunch() },
                skipScreenRecording: { Settings.screenRecordingSkipped = true },
                changed: { [weak self] _ in self?.refreshPermissions() }
            ))
        }
        permissionsWindow?.present()
    }

    // MARK: Menu

    private func refreshMenu() {
        var state = MenuState()
        state.warnings = PermissionsFlow.warnings(for: permissions, macOSMajor: PermissionsCoordinator.macOSMajor)
        menuBar.update(state)
    }

    private func mainMenuItems() -> [MenuBarController.Item] {
        var items: [MenuBarController.Item] = []
        if PermissionsFlow.step(for: permissions, screenRecordingSkipped: false) != .done {
            items.append(.init("Permissions…") { [weak self] in self?.showPermissions() })
        }
        return items
    }
}
