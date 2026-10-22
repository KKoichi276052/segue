import AppKit
import SegueCore
import SegueSystem
import SegueUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarController()
    private var permissionsWindow: PermissionsWindowController?
    private var permissions = PermissionsCoordinator.current()
    private let privateAPI = PrivateAPI.availability
    private lazy var report = ReportWindow()
    private let inventory = WindowInventory()
    private lazy var switcher = SwitcherCoordinator(inventory: inventory)
    /// `--no-input` runs without the hotkey and the event tap, for idle measurements.
    private let inputEnabled = !CommandLine.arguments.contains("--no-input")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("Segue \(SegueVersion.string, privacy: .public) launched; \(PermissionsCoordinator.describe(self.permissions), privacy: .public)")
        menuBar.willOpen = { [weak self] in self?.refreshPermissions() }
        menuBar.mainItems = { [weak self] in self?.mainMenuItems() ?? [] }
        menuBar.debugItems = { [weak self] in self?.debugMenuItems() ?? [] }
        for check in PrivateAPI.selfCheck() {
            Log.app.info("self-check \(check.ok ? "ok" : "MISSING", privacy: .public) \(check.name, privacy: .public): \(check.detail, privacy: .public)")
        }
        refreshMenu()
        inventory.start()
        switcher.start(inputEnabled: inputEnabled)
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
            inventory.permissionsChanged()
            if inputEnabled { switcher.installTapIfPossible() }
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
        state.notes = privateAPI.fallbackNotes
        state.paused = switcher.paused
        switch switcher.hotkey.status {
        case .registered(let spec): state.notes.append("\(spec.description) opens the switcher · hold ⌥ Tab to switch")
        case .failed(let spec, _): state.warnings.append("\(spec.description) is taken by another app. Set TapHotkey with defaults write.")
        case .notRegistered: if inputEnabled && !switcher.paused { state.warnings.append("TapHotkey “\(Settings.tapHotkeyText)” isn't a valid hotkey") }
        }
        if inputEnabled && permissions.accessibility && !switcher.holdMonitor.isInstalled {
            state.warnings.append("Hold mode is off: the event tap couldn't be created")
        }
        menuBar.update(state)
    }

    private func mainMenuItems() -> [MenuBarController.Item] {
        var items: [MenuBarController.Item] = [
            .init("Pause Segue", checked: switcher.paused) { [weak self] in
                guard let self else { return }
                switcher.paused.toggle()
                refreshMenu()
            },
        ]
        if PermissionsFlow.step(for: permissions, screenRecordingSkipped: false) != .done {
            items.append(.init("Permissions…") { [weak self] in self?.showPermissions() })
        }
        return items
    }

    private func debugMenuItems() -> [MenuBarController.Item] {
        [
            .init("Dump windows") { [weak self] in
                guard let self else { return }
                let snapshot = inventory.snapshot
                let text = WindowReport.table(snapshot.windows, focusedID: snapshot.focusedID)
                    + "\nlast refresh \(fmt(snapshot.refreshMs, 2)) ms; \(snapshot.refreshCount) refreshes since launch"
                report.show(title: "Windows", text: text)
            },
            .init("Timing summary") { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    let previews = await self.switcher.previewSummary()
                    self.report.show(title: "Timing summary", text: self.switcher.timings.summary()
                        + "\n\n" + previews
                        + "\n\nevent tap: \(self.switcher.holdMonitor.isInstalled ? "installed" : "not installed"), disabled by macOS \(self.switcher.holdMonitor.disabledCount) times"
                        + "\nresident memory \(residentMemory() / 1_048_576) MB")
                }
            },
            .init("Log raw key events", checked: switcher.keyLogEnabled) { [weak self] in
                self?.switcher.keyLogEnabled.toggle()
            },
            .init("Private API self-check") { [weak self] in
                let text = PrivateAPI.selfCheck().map { "[\($0.ok ? "ok" : "MISSING")] \($0.name): \($0.detail)" }.joined(separator: "\n")
                self?.report.show(title: "Private API self-check", text: text)
            },
        ]
    }
}
