import AppKit
import QuartzCore
import SegueCore
import SegueSystem
import SegueUI

/// Wires the switcher together: keys from the event tap and the hotkey go into
/// `SwitcherState`, and its effects drive the panel, the focuser and the timers.
@MainActor
final class SwitcherCoordinator {
    private let inventory: WindowInventory
    private let focuser: WindowFocuser
    let hotkey = HotkeyService()
    let holdMonitor = HoldMonitor()
    private let window = SwitcherWindowController()
    private var state = SwitcherState(showDelayMs: Settings.showDelayMs)
    private var showWork: DispatchWorkItem?
    private(set) var timings = ShowTimings()
    private var nextShowIsFirst = true
    private var pendingShow: (kind: SwitcherWindowController.ShowKind, eventTime: CFTimeInterval)?
    private var icons: [Int32: NSImage] = [:]
    /// Window images (docs/SPEC.md §15: cache and refresh). In memory only.
    private var previews = ByteLRU<WindowID, CGImage>(capacity: 60 * 1_048_576)
    private lazy var snapshots = SnapshotService { [weak self] id, image, _ in self?.received(image, for: id) }
    /// How many cards to refresh on show; the rest keep their cached image.
    private let refreshLimit = 30

    var paused = false {
        didSet {
            holdMonitor.paused = paused
            if paused {
                apply(state.dismiss())
                hotkey.unregister()
            } else {
                registerHotkey()
            }
        }
    }

    init(inventory: WindowInventory) {
        self.inventory = inventory
        focuser = WindowFocuser(inventory: inventory)
        window.keepsPanelOnScreen = Settings.keepPanelOnScreen
        window.onFirstFrame = { [weak self] kind, ms in self?.recordFirstFrame(kind, ms) }
        window.onChoose = { [weak self] index in
            guard let self, state.items.indices.contains(index) else { return }
            apply(state.choose(state.items[index]))
        }
        window.onClickOutside = { [weak self] in
            guard let self else { return }
            apply(state.dismiss())
        }
        hotkey.onPress = { [weak self] time in
            guard let self, !paused else { return }
            pendingShow = (.tap, time)
            apply(state.toggleTap())
        }
        holdMonitor.onKey = { [weak self] input, optionDown in
            guard let self else { return false }
            let wasHidden = state.phase == .hidden
            let (swallow, effects) = state.handle(input, optionDown: optionDown, from: .eventTap)
            if !effects.isEmpty {
                if wasHidden { inventory.refreshSoon(reason: "hold") }
                pendingShow = (.hold, CACurrentMediaTime())
                apply(effects)
            }
            holdMonitor.holding = state.phase == .holdPending || state.phase == .holding
            return swallow
        }
        holdMonitor.onOptionReleased = { [weak self] in
            guard let self else { return }
            apply(state.optionReleased())
            holdMonitor.holding = false
        }
        holdMonitor.logsRawEvents = Settings.debugKeyLog
        inventory.onChange = { [weak self] snapshot in
            guard let self else { return }
            apply(state.updateWindows(snapshot.windows.map(\.id), focusedID: snapshot.focusedID))
            previews.retain(Set(snapshot.windows.map(\.id)))
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    /// Registers the hotkey, installs the tap (if permitted) and pre-warms the panel.
    func start(inputEnabled: Bool) {
        if inputEnabled {
            registerHotkey()
            installTapIfPossible()
        }
        prewarm()
    }

    func installTapIfPossible() {
        guard !holdMonitor.isInstalled, AXIsProcessTrusted() else { return }
        holdMonitor.install()
    }

    private func registerHotkey() {
        guard let spec = Settings.tapHotkey else {
            Log.keys.error("TapHotkey “\(Settings.tapHotkeyText, privacy: .public)” isn't a valid hotkey")
            return
        }
        hotkey.register(spec)
    }

    var keyLogEnabled: Bool {
        get { holdMonitor.logsRawEvents }
        set {
            holdMonitor.logsRawEvents = newValue
            Settings.debugKeyLog = newValue
        }
    }

    // MARK: Effects

    private func apply(_ effects: [SwitcherEffect]) {
        for effect in effects {
            switch effect {
            case .scheduleShow(let ms):
                showWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    pendingShow = (.hold, CACurrentMediaTime())
                    apply(state.showDelayElapsed())
                }
                showWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: work)
            case .cancelScheduledShow:
                showWork?.cancel()
                showWork = nil
            case .show:
                show()
            case .hide:
                window.hide()
                Task { await snapshots.cancelAll() }
            case .focus(let id):
                guard let info = inventory.snapshot.windows.first(where: { $0.id == id }) else { break }
                let left = inventory.snapshot.focusedID.flatMap { leftID in inventory.snapshot.windows.first { $0.id == leftID } }
                focuser.focus(info)
                if let left, left.id != id { captureAfterSwitch(left) }
            case .selectionChanged:
                window.update(model())
            case .beginSearch, .appendSearch, .search, .clearSearch:
                break // M1 step 9
            }
        }
    }

    private func show() {
        let event = pendingShow ?? (.tap, CACurrentMediaTime())
        pendingShow = nil
        let screen = targetScreen()
        window.show(model(), on: screen, kind: event.kind, eventTime: event.eventTime,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        inventory.refreshSoon(reason: "show")
        refreshPreviews()
    }

    // MARK: Previews

    private func refreshPreviews() {
        guard SnapshotService.isAllowed else { return }
        let now = CACurrentMediaTime()
        let ids = PreviewRefresh.order(visible: Array(state.items.prefix(refreshLimit)), selected: state.selectedID,
                                       storedAt: { [previews] in previews.storedAt($0) }, now: now)
        let sizes = Dictionary(inventory.snapshot.windows.map { ($0.id, $0.frame.size) }, uniquingKeysWith: { a, _ in a })
        Task { await snapshots.request(ids, sizes: sizes) }
    }

    /// The window just left is what the owner last saw; capture it once it's behind.
    private func captureAfterSwitch(_ window: WindowInfo) {
        guard SnapshotService.isAllowed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [snapshots] in
            Task { await snapshots.requestOne(window.id, size: window.frame.size) }
        }
    }

    private func received(_ image: CGImage, for id: WindowID) {
        previews.insert(image, for: id, cost: image.bytesPerRow * image.height, at: CACurrentMediaTime())
        if window.isShowing, state.items.contains(id) { window.update(model()) }
    }

    func previewSummary() async -> String {
        let ms = await snapshots.captureMs
        let blank = await snapshots.blankCount
        let captures = Stats(ms).map { "captures: \($0.summary)" } ?? "captures: none yet"
        return "\(captures); \(blank) blank\ncache: \(previews.count) images, \(previews.totalCost / 1_048_576) MB of \(previews.capacity / 1_048_576) MB"
            + (SnapshotService.isAllowed ? "" : "\nScreen Recording is off: cards show icons and titles")
    }

    /// The display with the focused window (§6.10), else the one with the pointer.
    private func targetScreen() -> NSScreen {
        let snapshot = inventory.snapshot
        if let id = snapshot.focusedID, let w = snapshot.windows.first(where: { $0.id == id }), w.isOnScreen,
           let screen = NotchGeometry.screen(containingAXRect: w.frame) {
            return screen
        }
        return NotchGeometry.screenWithPointer() ?? NSScreen.screens[0]
    }

    private func model() -> SwitcherModel {
        let byID = Dictionary(inventory.snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var model = SwitcherModel()
        model.cards = state.items.compactMap { id in
            guard let w = byID[id] else { return nil }
            return .init(id: id, title: w.title, appName: w.appName, icon: icon(for: w.pid), image: previews.value(for: id), kind: w.kind)
        }
        model.selectedIndex = state.selectedIndex
        model.query = state.query
        model.isSearching = state.isSearching
        switch state.phase {
        case .open: model.hint = "return to switch  ·  esc to close  ·  type to search"
        default: model.hint = "release ⌥ to switch  ·  esc to cancel  ·  type to search"
        }
        return model
    }

    private func icon(for pid: Int32) -> NSImage? {
        if let icon = icons[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        icons[pid] = icon
        return icon
    }

    // MARK: Timing and displays

    private func recordFirstFrame(_ kind: SwitcherWindowController.ShowKind, _ ms: Double) {
        let first = nextShowIsFirst
        nextShowIsFirst = false
        timings.record(kind == .tap ? .tap : .hold, ms: ms, first: first)
        Log.app.info("show (\(kind == .tap ? "tap" : "hold", privacy: .public))\(first ? " first" : "", privacy: .public): event → first frame \(fmt(ms), privacy: .public) ms")
    }

    private func screensChanged() {
        apply(state.dismiss())
        nextShowIsFirst = true
        prewarm()
    }

    private func prewarm() {
        var sample = SwitcherModel()
        sample.cards = [.init(id: 0, title: "Segue", appName: "Segue", icon: NSApp.applicationIconImage, image: nil, kind: .onScreen)]
        sample.selectedIndex = 0
        for screen in NSScreen.screens { window.prewarm(on: screen, sample: sample) }
    }
}
