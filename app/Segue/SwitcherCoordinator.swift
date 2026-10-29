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
    private var searchIndex = SearchIndex(windows: [])
    /// Orders preview requests, which travel in separate tasks.
    private var previewGeneration = 0
    /// When Segue last focused a window: its activation and Space change arrive later and
    /// mustn't close a switcher opened right after.
    private var lastFocusAt: CFTimeInterval = 0
    /// How many cards to refresh on show; the rest keep their cached image.
    private let refreshLimit = 30

    /// Called on each show, so the app can re-check permissions (a revoked permission
    /// shows in the menu at the next show).
    var onWillShow: (() -> Void)?

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
        window.onSearchTextChange = { [weak self] text in
            guard let self else { return }
            apply(state.queryChanged(text))
        }
        window.onSearchCommand = { [weak self] input in
            guard let self else { return }
            if case .arrow = input { syncColumns() }
            apply(state.handle(input, optionDown: false, from: .panel).effects)
            syncKeyNeeds()
        }
        window.onClickOutside = { [weak self] in
            guard let self else { return }
            apply(state.dismiss())
        }
        holdMonitor.tapHotkey = Settings.tapHotkey
        hotkey.onPress = { [weak self] time in
            guard let self, !paused else { return }
            pendingShow = (.tap, time)
            apply(state.toggleTap())
        }
        holdMonitor.onKey = { [weak self] input, optionDown in
            guard let self else { return false }
            let wasHidden = state.phase == .hidden
            if case .arrow = input { syncColumns() }
            let (swallow, effects) = state.handle(input, optionDown: optionDown, from: .eventTap)
            if !effects.isEmpty {
                if wasHidden { inventory.refreshSoon(reason: "hold") }
                pendingShow = (.hold, CACurrentMediaTime())
                apply(effects)
            }
            syncKeyNeeds()
            return swallow
        }
        holdMonitor.onOptionReleased = { [weak self] in
            guard let self else { return }
            apply(state.optionReleased())
            syncKeyNeeds()
        }
        holdMonitor.logsRawEvents = Settings.debugKeyLog
        inventory.onChange = { [weak self] snapshot in
            guard let self else { return }
            searchIndex = SearchIndex(windows: snapshot.windows)
            apply(state.updateWindows(snapshot.windows.map(\.id), focusedID: snapshot.focusedID))
            previews.retain(Set(snapshot.windows.map(\.id)))
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        // Another app coming forward (Cmd-Tab, the Dock) or another Space closes the switcher.
        // Segue's own switches hide it first, so they never get here while it's open.
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.state.isVisible, CACurrentMediaTime() - self.lastFocusAt > 1 else { return }
                    self.apply(self.state.dismiss())
                    self.syncKeyNeeds()
                }
            }
        }
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdMonitor.ensureEnabled()
                self.nextShowIsFirst = true
                self.prewarm()
            }
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
                    // A safety net: if ⌥ is already up, the release was missed. Switch, don't show.
                    if !HoldMonitor.optionIsDown {
                        apply(state.optionReleased())
                        syncKeyNeeds()
                        return
                    }
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
                previewGeneration += 1
                let generation = previewGeneration
                Task { await snapshots.cancelAll(generation: generation) }
            case .focus(let id):
                guard let info = inventory.snapshot.windows.first(where: { $0.id == id }) else { break }
                let left = inventory.snapshot.focusedID.flatMap { leftID in inventory.snapshot.windows.first { $0.id == leftID } }
                lastFocusAt = CACurrentMediaTime()
                // Focus once the panel is gone, so the keyboard handed back to the previous
                // app when a key panel orders out can't land after the switch. On macOS 27
                // SkyLight no longer switches Space, so move to the window's Space first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    guard let self else { return }
                    let focus: @MainActor @Sendable (SpaceSwitcher.Result) -> Void = { [weak self] space in
                        guard let self else { return }
                        focuser.focus(info)
                        reportFocus(info, space: space)
                    }
                    if info.kind == .otherSpace {
                        SpaceSwitcher.moveToSpace(of: info.id, completion: focus)
                    } else {
                        focus(.notNeeded)
                    }
                }
                if let left, left.id != id { captureAfterSwitch(left) }
            case .selectionChanged:
                window.update(model())
            case .takeKeyboard:
                // After the show is committed: becoming key takes a window-server round trip
                // that would otherwise delay the first frame.
                DispatchQueue.main.async { [weak self] in
                    self?.window.noteStep("start take keyboard")
                    self?.window.takeKeyboard()
                    self?.window.noteStep("take keyboard")
                }
            case .beginSearch(let text):
                window.takeKeyboard(text: text)
            case .appendSearch(let text):
                window.appendSearchText(text)
            case .search(let query):
                apply(state.setResults(searchIndex.search(query)))
            case .clearSearch:
                window.clearSearchText()
            }
        }
        syncKeyNeeds()
    }

    private func show() {
        let event = pendingShow ?? (.tap, CACurrentMediaTime())
        pendingShow = nil
        guard let screen = targetScreen() else { return }
        window.show(model(), on: screen, kind: event.kind, eventTime: event.eventTime,
                    reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        // After the panel is committed, and off the event tap's callback, so these never
        // delay the first frame or a keystroke.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.noteStep("start tap check")
            holdMonitor.ensureEnabled()
            window.noteStep("tap check")
            onWillShow?()
            window.noteStep("permissions and menu")
        }
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
        previewGeneration += 1
        let generation = previewGeneration
        Task { await snapshots.request(ids, sizes: sizes, generation: generation) }
    }

    /// Logs what ended up in front shortly after a switch, to diagnose switches that land
    /// somewhere else (for example on another Space).
    private func reportFocus(_ target: WindowInfo, space: SpaceSwitcher.Result) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let front = NSWorkspace.shared.frontmostApplication
            let focused = inventory.snapshot.focusedID
            let showing = SpaceRoute.compute(windowSpaces: PrivateAPI.spaces(ofWindow: target.id) ?? [],
                                             displays: PrivateAPI.displaySpaces() ?? []) == nil
            let ok = front?.processIdentifier == target.pid && focused == target.id && showing
            Log.focus.notice("""
                after switch to \(target.id) (\(target.appName, privacy: .public), \(target.kind.rawValue, privacy: .public)): \
                \(space.description, privacy: .public); front is \(front?.localizedName ?? "none", privacy: .public), \
                focused window \(focused.map(String.init) ?? "none", privacy: .public), \
                its Space \(showing ? "showing" : "not showing", privacy: .public) [\(ok ? "ok" : "MISSED", privacy: .public)]
                """)
        }
    }

    /// The window just left is what the owner last saw; capture it once it's behind.
    private func captureAfterSwitch(_ window: WindowInfo) {
        guard SnapshotService.isAllowed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !state.isVisible else { return }
            previewGeneration += 1
            let generation = previewGeneration
            Task { await self.snapshots.requestOne(window.id, size: window.frame.size, generation: generation) }
        }
    }

    private func received(_ image: CGImage, for id: WindowID) {
        previews.insert(image, for: id, cost: image.bytesPerRow * image.height, at: CACurrentMediaTime())
        if window.isShowing, state.items.contains(id) {
            window.noteStep("start preview \(id)")
            window.update(model())
            window.noteStep("preview \(id)")
        }
    }

    func previewSummary() async -> String {
        let ms = await snapshots.captureMs
        let blank = await snapshots.blankCount
        let captures = Stats(ms).map { "captures: \($0.summary)" } ?? "captures: none yet"
        return "\(captures); \(blank) blank\ncache: \(previews.count) images, \(previews.totalCost / 1_048_576) MB of \(previews.capacity / 1_048_576) MB"
            + (SnapshotService.isAllowed ? "" : "\nScreen Recording is off: cards show icons and titles")
    }

    /// The display with the focused window (§6.10), else the one with the pointer.
    private func targetScreen() -> NSScreen? {
        let snapshot = inventory.snapshot
        if let id = snapshot.focusedID, let w = snapshot.windows.first(where: { $0.id == id }), w.isOnScreen,
           let screen = NotchGeometry.screen(containingAXRect: w.frame) {
            return screen
        }
        return NotchGeometry.screenWithPointer() ?? NSScreen.screens.first
    }

    /// Keeps ▲ ▼ moving by a row of the grid the owner sees.
    private func syncColumns() {
        guard let screen = targetScreen() else { return }
        state.columns = window.columns(forCount: state.items.count, showsSearchBar: state.isSearching, on: screen)
    }

    /// Tells the tap what the switcher needs: all keys during a hold, characters whenever it
    /// isn't hidden.
    private func syncKeyNeeds() {
        holdMonitor.holding = state.phase == .holdPending || state.phase == .holding
        holdMonitor.wantsCharacters = state.phase != .hidden
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
        model.showsSearchBar = state.isSearching
        switch state.phase {
        case .open where state.isSearching: model.hint = "◀ ▶ to choose  ·  return to switch  ·  esc to clear"
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
        // One screen at a time: the panel's backing store depends on the screen's scale.
        for (i, screen) in NSScreen.screens.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(i)) { [weak self] in
                self?.window.prewarm(on: screen, sample: sample)
            }
        }
    }
}
