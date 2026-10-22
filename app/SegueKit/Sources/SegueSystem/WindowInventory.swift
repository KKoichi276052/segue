import AppKit
import ApplicationServices
import SegueCore

/// Keeps the list of windows current (docs/SPEC.md §9 `WindowInventory`). The list is built
/// at launch and updated from notifications, never built when the hotkey is pressed:
/// reading `snapshot` costs nothing.
///
/// Threading: Accessibility calls, observers and all mutable state below live on one
/// `AXThread`. Results are published to the main thread.
public final class WindowInventory: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        /// Most recently used first.
        public var windows: [WindowInfo] = []
        /// The focused window of the frontmost app, when known.
        public var focusedID: WindowID?
        /// How long the last refresh took.
        public var refreshMs: Double = 0
        public var refreshCount = 0

        public init() {}
    }

    /// Called on the main thread when the snapshot changes.
    @MainActor public var onChange: ((Snapshot) -> Void)?
    @MainActor public private(set) var snapshot = Snapshot()

    private let thread = AXThread()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    // AX-thread state.
    private var apps: [AppRecord] = []
    private var axWindows: [Int32: [(record: AXWindowRecord, element: AXUIElement)]] = [:]
    private var axReadPIDs: Set<Int32> = []
    private var dirty: Set<Int32> = []
    private var observers: [Int32: AXObserver] = [:]
    private var observedWindows: [Int32: Set<WindowID>] = [:]
    private var serverSignature: [Int32: [WindowID: Bool]] = [:]
    private var titles: [WindowID: String] = [:]
    private var elements: [WindowID: AXUIElement] = [:]
    private var recency = RecencyList()
    private var focusedID: WindowID?
    private var refreshScheduled = false
    private var trusted = false
    private var published = Snapshot()

    private var workspaceTokens: [NSObjectProtocol] = []

    public init() {}

    // MARK: Lifecycle

    /// Builds the first list and starts watching. Call once, on the main thread.
    @MainActor
    public func start() {
        AX.setGlobalTimeout(0.25)
        let apps = AppRecord.running()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        thread.perform { [self] in
            self.apps = apps
            self.trusted = AXIsProcessTrusted()
            dirty = Set(apps.map(\.pid))
            for app in apps { observe(app.pid) }
            refresh(reason: "start")
            if let frontmost { noteFocus(in: frontmost) }
        }
        let center = NSWorkspace.shared.notificationCenter
        let appNotifications: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in appNotifications {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { self?.appsChanged(pid: pid, name: name) }
            })
        }
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            self?.thread.perform { self?.noteFocus(in: pid) }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thread.perform {
                guard let self else { return }
                self.dirty.formUnion(self.apps.map(\.pid))
                self.scheduleRefresh(reason: "wake")
            }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.thread.perform {
                guard let self else { return }
                self.dirty.formUnion(self.apps.map(\.pid))
                self.scheduleRefresh(reason: "space changed")
            }
        })
    }

    /// Asks for a refresh soon, for example when the switcher opens. Cheap when nothing changed:
    /// only apps whose windows changed in the Window Server list are re-read.
    public func refreshSoon(reason: String) {
        thread.perform { [self] in scheduleRefresh(reason: reason) }
    }

    /// Re-reads permissions, for example after Device Control and Data Access is granted.
    public func permissionsChanged() {
        thread.perform { [self] in
            let now = AXIsProcessTrusted()
            guard now != trusted else { return }
            trusted = now
            dirty.formUnion(apps.map(\.pid))
            for app in apps { observe(app.pid) }
            scheduleRefresh(reason: "permissions changed")
        }
    }

    /// Runs `body` on the Accessibility thread with the window's element, if it has one.
    func withElement(_ id: WindowID, _ body: @escaping (AXUIElement?) -> Void) {
        thread.perform { [self] in body(elements[id]) }
    }

    /// Marks a window as used now (Segue just focused it).
    public func touch(_ id: WindowID) {
        thread.perform { [self] in
            recency.touch(id)
            focusedID = id
            publish()
        }
    }

    // MARK: Building once (for --dump-windows)

    /// Builds the list once, synchronously, without observers.
    @MainActor
    public static func buildOnce() -> (windows: [WindowInfo], ms: Double, accessibility: Bool) {
        let apps = AppRecord.running()
        let trusted = AXIsProcessTrusted()
        AX.setGlobalTimeout(0.25)
        let (windows, ms) = measure { () -> [WindowInfo] in
            let server = WindowServer.list()
            var records: [AXWindowRecord] = []
            var read: Set<Int32> = []
            if trusted {
                for app in apps {
                    if let windows = readWindows(pid: app.pid) {
                        read.insert(app.pid)
                        records += windows.map(\.record)
                    }
                }
            }
            return WindowMerger.merge(server: server, ax: records, apps: apps, axReadPIDs: read,
                                      ownPID: ProcessInfo.processInfo.processIdentifier).windows
        }
        return (windows, ms, trusted)
    }

    // MARK: Apps

    @MainActor
    private func appsChanged(pid: Int32?, name: Notification.Name) {
        let apps = AppRecord.running()
        thread.perform { [self] in
            self.apps = apps
            if let pid {
                if name == NSWorkspace.didTerminateApplicationNotification {
                    forget(pid)
                } else {
                    observe(pid)
                    dirty.insert(pid)
                }
            }
            scheduleRefresh(reason: name.rawValue)
        }
    }

    private func forget(_ pid: Int32) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(thread.runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observedWindows[pid] = nil
        axWindows[pid] = nil
        axReadPIDs.remove(pid)
        dirty.remove(pid)
    }

    // MARK: Observers

    private static let appNotifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
        kAXApplicationHiddenNotification, kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification, kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    private func observe(_ pid: Int32) {
        guard trusted, observers[pid] == nil, pid != ownPID else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let inventory = Unmanaged<WindowInventory>.fromOpaque(refcon).takeUnretainedValue()
            inventory.received(notification as String, element: element)
        }, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(thread.runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func observeWindow(_ element: AXUIElement, id: WindowID, pid: Int32) {
        guard let observer = observers[pid], observedWindows[pid, default: []].insert(id).inserted else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.windowNotifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
    }

    private func received(_ notification: String, element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if notification == kAXFocusedWindowChangedNotification || notification == kAXMainWindowChangedNotification {
            noteFocus(in: pid)
        }
        if notification == kAXUIElementDestroyedNotification, pid != 0 {
            observedWindows[pid] = nil
        }
        if pid != 0 { dirty.insert(pid) }
        scheduleRefresh(reason: notification)
    }

    // MARK: Focus

    private func noteFocus(in pid: Int32) {
        guard trusted else { return }
        let app = AXUIElementCreateApplication(pid)
        guard let window: AXUIElement = AX.attribute(app, kAXFocusedWindowAttribute),
              let id = PrivateAPI.windowID(of: window)
        else { return }
        if focusedID != id || recency.order.first != id {
            recency.touch(id)
            focusedID = id
            publish()
        }
    }

    // MARK: Refreshing

    private func scheduleRefresh(reason: String) {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        // Coalesce bursts (an app opening several windows, a Space switch).
        thread.perform(after: 0.03) { [self] in
            refreshScheduled = false
            refresh(reason: reason)
        }
    }

    private func refresh(reason: String) {
        let start = ContinuousClock.now
        let server = WindowServer.list()

        // Re-read apps whose windows changed in the Window Server list, plus any marked dirty.
        var signature: [Int32: [WindowID: Bool]] = [:]
        for s in server where s.layer == 0 { signature[s.pid, default: [:]][s.id] = s.isOnScreen }
        for (pid, windows) in signature where serverSignature[pid] != windows { dirty.insert(pid) }
        serverSignature = signature

        let pids = Set(apps.map(\.pid))
        if trusted {
            for pid in dirty where pids.contains(pid) {
                if let windows = Self.readWindows(pid: pid) {
                    axWindows[pid] = windows
                    axReadPIDs.insert(pid)
                    for w in windows {
                        if let id = w.record.windowID {
                            observeWindow(w.element, id: id, pid: pid)
                            if let title = w.record.title, !title.isEmpty { titles[id] = title }
                        }
                    }
                } else {
                    axReadPIDs.remove(pid)
                }
            }
        }
        dirty.removeAll()

        let entries = apps.flatMap { axWindows[$0.pid] ?? [] }
        let result = WindowMerger.merge(server: server, ax: entries.map(\.record), apps: apps, axReadPIDs: axReadPIDs,
                                        rememberedTitles: titles, ownPID: ownPID)
        elements = result.axIndex.mapValues { entries[$0].element }
        let ids = Set(result.windows.map(\.id))
        titles = titles.filter { ids.contains($0.key) }
        recency.sync(result.windows.map(\.id))
        current = result.windows
        lastRefreshMs = (ContinuousClock.now - start).milliseconds
        refreshCount += 1
        Log.inventory.debug("refresh (\(reason, privacy: .public)): \(result.windows.count) windows in \(fmt(self.lastRefreshMs, 2), privacy: .public) ms")
        publish()
    }

    private var current: [WindowInfo] = []
    private var lastRefreshMs: Double = 0
    private var refreshCount = 0

    private func publish() {
        var next = Snapshot()
        next.windows = recency.sorted(current)
        next.focusedID = focusedID
        next.refreshMs = lastRefreshMs
        next.refreshCount = refreshCount
        guard next.windows != published.windows || next.focusedID != published.focusedID else { return }
        published = next
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                snapshot = next
                onChange?(next)
            }
        }
    }

    // MARK: Reading Accessibility

    nonisolated(unsafe) private static let attributes = [kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXMinimizedAttribute,
                                     kAXRoleAttribute, kAXSubroleAttribute] as [CFString]

    /// The app's Accessibility windows (current Space only), or nil if they couldn't be read.
    static func readWindows(pid: Int32) -> [(record: AXWindowRecord, element: AXUIElement)]? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if error == .noValue { return [] }
        guard error == .success, let windows = value as? [AXUIElement] else { return nil }
        return windows.map { element in
            var values: CFArray?
            AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, AXCopyMultipleAttributeOptions(), &values)
            let list = values as? [Any] ?? []
            func item(_ i: Int) -> Any? { i < list.count ? list[i] : nil }
            var frame: CGRect?
            if let p = item(1), let s = item(2), CFGetTypeID(p as CFTypeRef) == AXValueGetTypeID(),
               CFGetTypeID(s as CFTypeRef) == AXValueGetTypeID() {
                var origin = CGPoint.zero
                var size = CGSize.zero
                if AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) {
                    frame = CGRect(origin: origin, size: size)
                }
            }
            let record = AXWindowRecord(
                windowID: PrivateAPI.windowID(of: element), pid: pid, title: item(0) as? String, frame: frame,
                isMinimized: (item(3) as? Bool) ?? false, role: item(4) as? String, subrole: item(5) as? String)
            return (record, element)
        }
    }
}
