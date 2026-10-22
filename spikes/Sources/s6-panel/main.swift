import AppKit
import Carbon.HIToolbox
import QuartzCore
import SpikeKit

// S6 Panel and keys (docs/SPEC.md §10).
// Pass when: first frame within 16 ms of the hotkey; works over full-screen apps.
// Also detects ⌥ held and released with an event tap, and records which permission it needs.
//
// Runs until ctrl-C (or --seconds <n>), then prints a summary. While it runs:
//   ⌥ Space          show the panel (tap mode); ⌥ Space again or esc hides it
//   hold ⌥, Tab      hold mode; letting go of ⌥ hides it ("would switch")
//   Try both over a full-screen app, and on each display.
//
// Options:
//   --seconds <n>      stop after n seconds
//   --show-delay <ms>  hold-mode show delay (default 100, spec §6.1)
//   --listen-only      create a listen-only tap instead of an active one (to compare permissions)

let args = Arguments()
let report = Report("S6 Panel and keys")

@MainActor
final class Spike: NSObject {
    static let shared = Spike()

    let panel: NSPanel
    let showDelay = Double(args.int("show-delay") ?? 100) / 1000

    private var escHotKey: EventHotKeyRef?
    private var link: CADisplayLink?
    private var pending: (source: String, eventTime: CFTimeInterval, handled: CFTimeInterval, committed: CFTimeInterval)?

    // Results.
    var frameSamples: [Double] = []
    var handlerSamples: [Double] = []
    var commitSamples: [Double] = []
    var fullScreenShows: [(visible: Bool, app: String)] = []
    var shows = 0
    var tapCreated: String?
    var holdCycles = 0
    var quickSwitches = 0

    // Hold mode state.
    private var holding = false
    private var holdStart: CFTimeInterval = 0
    private var tabCount = 0
    private var holdShowWork: DispatchWorkItem?

    override init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        super.init()
        // Above the menu bar (level 24) and on every Space, including full-screen ones.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
    }

    // MARK: Notch and panel

    func describeScreens() {
        for (i, screen) in NSScreen.screens.enumerated() {
            let notch = notchRect(screen)
            print("display \(i) \(screen.localizedName): frame \(screen.frame.short), safe-area top \(screen.safeAreaInsets.top), "
                  + "left area \(screen.auxiliaryTopLeftArea?.short ?? "none"), right area \(screen.auxiliaryTopRightArea?.short ?? "none") → "
                  + (notch.map { "notch \(Int($0.width))×\(Int($0.height)) pt" } ?? "no notch (virtual notch)"))
        }
    }

    /// The notch in global coordinates, from the unobscured areas either side of it.
    func notchRect(_ screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        let height = screen.safeAreaInsets.top
        return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// Lays the panel out at the top center of `screen`: a black shape filling the notch
    /// (or a virtual notch) with an island hanging below it.
    func layout(on screen: NSScreen) {
        let notch = notchRect(screen) ?? CGRect(x: screen.frame.midX - 100, y: screen.frame.maxY - 32, width: 200, height: 32)
        let size = CGSize(width: max(notch.width + 160, 420), height: notch.height + 90)
        panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: false)

        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        let black = CGColor(gray: 0, alpha: 1)
        let notchLayer = CALayer()
        notchLayer.frame = CGRect(x: (size.width - notch.width) / 2, y: size.height - notch.height, width: notch.width, height: notch.height)
        notchLayer.backgroundColor = black
        notchLayer.cornerRadius = 10
        notchLayer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let island = CALayer()
        island.frame = CGRect(x: (size.width - 360) / 2, y: 6, width: 360, height: 76)
        island.backgroundColor = black
        island.cornerRadius = 38
        let label = CATextLayer()
        label.string = "Segue S6 · esc or ⌥ Space hides"
        label.fontSize = 13
        label.foregroundColor = CGColor(gray: 1, alpha: 1)
        label.alignmentMode = .center
        label.contentsScale = screen.backingScaleFactor
        label.frame = CGRect(x: 0, y: 28, width: 360, height: 20)
        island.addSublayer(label)
        view.layer?.addSublayer(notchLayer)
        view.layer?.addSublayer(island)
        panel.contentView = view
    }

    /// The display the panel should use. The product will use the focused window's display;
    /// the spike uses the one under the pointer.
    func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens[0]
    }

    // MARK: Showing

    func show(source: String, eventTime: CFTimeInterval) {
        let handled = CACurrentMediaTime()
        guard !panel.isVisible else { return }
        let screen = targetScreen()
        if panel.screen != screen || panel.contentView == nil { layout(on: screen) }
        panel.orderFrontRegardless()
        CATransaction.flush()
        pending = (source, eventTime, handled, CACurrentMediaTime())
        // The first display-link callback after the commit tells us which frame shows it.
        link = panel.contentView?.displayLink(target: self, selector: #selector(frame(_:)))
        link?.add(to: .main, forMode: .common)
        registerEscape()
        shows += 1

        let frontmost = NSWorkspace.shared.frontmostApplication
        let fullScreen = frontmostIsFullScreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            let visible = panel.isVisible && panel.occlusionState.contains(.visible) && panel.isOnActiveSpace
            if fullScreen == true { fullScreenShows.append((visible, frontmost?.localizedName ?? "?")) }
            print("  shown via \(source) on \(screen.localizedName); visible \(visible ? "yes" : "NO")"
                  + "; frontmost \(frontmost?.localizedName ?? "?") full screen: \(fullScreen.map { $0 ? "yes" : "no" } ?? "unknown (needs Accessibility)")")
        }
    }

    @objc func frame(_ link: CADisplayLink) {
        link.invalidate()
        self.link = nil
        guard let p = pending else { return }
        pending = nil
        let toFrame = (link.targetTimestamp - p.eventTime) * 1000
        let toHandler = (p.handled - p.eventTime) * 1000
        let toCommit = (p.committed - p.eventTime) * 1000
        // Hold mode shows after a deliberate delay; time it from when the delay ended.
        if p.source == "⌥ Space" {
            frameSamples.append(toFrame)
            handlerSamples.append(toHandler)
            commitSamples.append(toCommit)
        }
        print("  \(p.source): event→handler \(fmt(toHandler)) · →committed \(fmt(toCommit)) · →frame on screen \(fmt(toFrame)) ms")
    }

    func hide() {
        panel.orderOut(nil)
        unregisterEscape()
    }

    func frontmostIsFullScreen() -> Bool? {
        guard Permissions.accessibility(prompt: false), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let window: AXUIElement = AX.attribute(app, kAXFocusedWindowAttribute) else { return false }
        return AX.attribute(window, "AXFullScreen") ?? false
    }

    // MARK: Hotkeys (Carbon RegisterEventHotKey)

    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            let eventTime = GetEventTime(event)
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            MainActor.assumeIsolated { Spike.shared.hotKey(id.id, eventTime: eventTime) }
            return noErr
        }, 1, &spec, nil, nil)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), EventHotKeyID(signature: 0x5347_5545, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        print(status == noErr ? "⌥ Space registered" : "⌥ Space registration FAILED (\(status)); another app may own it (spec Q6)")
    }

    func hotKey(_ id: UInt32, eventTime: CFTimeInterval) {
        switch id {
        case 1: panel.isVisible ? hide() : show(source: "⌥ Space", eventTime: eventTime)
        case 2: hide()
        default: break
        }
    }

    /// esc only while the panel shows, so the spike never takes esc from other apps.
    func registerEscape() {
        guard escHotKey == nil else { return }
        RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x5347_5545, id: 2), GetApplicationEventTarget(), 0, &escHotKey)
    }

    func unregisterEscape() {
        if let escHotKey { UnregisterEventHotKey(escHotKey) }
        escHotKey = nil
    }

    // MARK: Hold mode (event tap)

    func installEventTap() {
        print("Before creating the tap: \(Permissions.describe())")
        let listenOnly = args.flag("listen-only")
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let swallow = MainActor.assumeIsolated { Spike.shared.handle(type: type, keyCode: keyCode, flags: flags) }
                return swallow ? nil : Unmanaged.passUnretained(event)
            }, userInfo: nil)
        else {
            tapCreated = nil
            print("Event tap (\(listenOnly ? "listen-only" : "active")) could NOT be created. Asking macOS for Input Monitoring…")
            CGRequestListenEventAccess()
            Permissions.accessibility(prompt: true)
            return
        }
        tapCreated = listenOnly ? "listen-only" : "active"
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Spike.tap = tap
        print("Event tap (\(tapCreated!)) created")
    }

    nonisolated(unsafe) static var tap: CFMachPort?

    /// Returns true to swallow the event.
    func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = Spike.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            print("  tap was disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")); re-enabled")
            return false
        }
        let option = flags.contains(.maskAlternate)
        if type == .keyDown, option, keyCode == Int64(kVK_Tab) {
            if !holding {
                holding = true
                tabCount = 0
                holdStart = CACurrentMediaTime()
                let work = DispatchWorkItem { [self] in
                    // Measure from when the delay ends, so the number compares with ⌥ Space.
                    show(source: "hold", eventTime: CACurrentMediaTime())
                }
                holdShowWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
            }
            tabCount += flags.contains(.maskShift) ? -1 : 1
            // An active tap swallows the Tab so the frontmost app doesn't get it.
            return tapCreated == "active"
        }
        if type == .flagsChanged, holding, !option {
            holding = false
            holdCycles += 1
            let heldMs = (CACurrentMediaTime() - holdStart) * 1000
            if panel.isVisible {
                hide()
                print("  ⌥ released after \(fmt(heldMs, 0)) ms: would switch to recent window #\(tabCount)")
            } else {
                holdShowWork?.cancel()
                quickSwitches += 1
                print("  ⌥ released after \(fmt(heldMs, 0)) ms, before the \(fmt(showDelay * 1000, 0)) ms delay: quick switch to the previous window, no flash")
            }
        }
        return false
    }

    // MARK: Summary

    func finish() {
        report.section("Results")
        if let f = Stats(frameSamples), let h = Stats(handlerSamples), let c = Stats(commitSamples) {
            print("event→handler: \(h.summary)")
            print("event→committed: \(c.summary)")
            report.check("Hotkey to first frame", passed: f.median <= 16, "⌥ Space \(f.summary)")
        } else {
            report.check("Hotkey to first frame", passed: nil, "⌥ Space was never pressed")
        }
        if fullScreenShows.isEmpty {
            report.check("Over full-screen apps", passed: nil,
                         Permissions.accessibility(prompt: false) ? "never shown over a full-screen app" : "needs Accessibility to detect full screen")
        } else {
            let ok = fullScreenShows.filter(\.visible).count
            report.check("Over full-screen apps", passed: ok == fullScreenShows.count,
                         "\(ok)/\(fullScreenShows.count) visible over \(Set(fullScreenShows.map(\.app)).sorted().joined(separator: ", "))")
        }
        if let tapCreated {
            report.check("⌥ hold and release", passed: holdCycles > 0 ? true : nil,
                         "\(tapCreated) tap; \(holdCycles) hold cycles, \(quickSwitches) quick switches")
        } else {
            report.check("⌥ hold and release", passed: false, "event tap could not be created")
        }
        print("Permissions at exit: \(Permissions.describe())")
        report.finish()
        exit(0)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    let spike = Spike.shared
    print("Permissions at start: \(Permissions.describe())")
    report.section("Displays")
    spike.describeScreens()
    report.section("Setup")
    spike.layout(on: spike.targetScreen())
    spike.registerHotKeys()
    spike.installEventTap()
    print("\nPress ⌥ Space, or hold ⌥ and press Tab. Try over a full-screen app. ctrl-C to finish.\n")
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { MainActor.assumeIsolated { Spike.shared.finish() } }
sigint.resume()
if let seconds = args.int("seconds") {
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { MainActor.assumeIsolated { Spike.shared.finish() } }
}
app.run()
