import AppKit
import SegueCore
import SegueSystem
import SegueUI
import UniformTypeIdentifiers

/// Arguments for checks that print and exit, so they can run from a terminal without
/// showing UI, installing an event tap or moving windows.
///
/// Run the binary directly (`Segue.app/Contents/MacOS/Segue --version`). Launched that way,
/// macOS applies the terminal's permissions, not Segue's.
enum CommandLineTools {
    @MainActor
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        let args = Array(arguments.dropFirst())
        if args.contains("--version") {
            print("Segue \(SegueVersion.string)")
            return 0
        }
        if args.contains("--permissions") {
            print(PermissionsCoordinator.describe(PermissionsCoordinator.current()))
            return 0
        }
        if args.contains("--self-check") {
            var allOK = true
            for check in PrivateAPI.selfCheck() {
                allOK = allOK && check.ok
                print("[\(check.ok ? "ok" : "MISSING")] \(check.name): \(check.detail)")
            }
            return allOK ? 0 : 1
        }
        if args.contains("--dump-windows") {
            _ = NSApplication.shared
            let (cold, coldMs, trusted) = WindowInventory.buildOnce()
            let (warm, warmMs, _) = WindowInventory.buildOnce()
            _ = cold
            print(WindowReport.table(warm))
            print("built in \(fmt(coldMs)) ms cold, \(fmt(warmMs)) ms warm" + (trusted ? "" : " (no Accessibility: Window Server only)"))
            return 0
        }
        if let i = args.firstIndex(of: "--watch-windows") {
            let seconds = i + 1 < args.count ? Double(args[i + 1]) ?? 30 : 30
            watchWindows(seconds: seconds)
            return 0
        }
        if let i = args.firstIndex(of: "--focus"), i + 1 < args.count, let id = WindowID(args[i + 1]) {
            return focus(id)
        }
        if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
            let sample = args.firstIndex(of: "--sample").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
            return renderPreview(to: args[i + 1], sample: sample)
        }
        if args.contains("--help") {
            print("""
            Segue \(SegueVersion.string)
              --version        print the version
              --permissions    print which permissions this process has
              --self-check     check the private calls Segue uses (no side effects)
              --dump-windows   print the window list once, with build times
              --watch-windows <s>  keep the live list for s seconds (default 30), print
                               each change, then the CPU time used
              --focus <id>     focus one window (ids from --dump-windows) and time it.
                               Moves focus and may switch Space.
              --render-preview <png> [--sample <n>]
                               draw the switcher offscreen into a PNG, with the real
                               window list or n made-up windows (no screen capture)
              --help           this help
            """)
            return 0
        }
        return nil
    }
}

extension CommandLineTools {
    /// Runs the live inventory without any UI and prints every change.
    @MainActor
    static func watchWindows(seconds: Double) {
        _ = NSApplication.shared
        let inventory = WindowInventory()
        var previous: [WindowInfo] = []
        let start = ContinuousClock.now
        inventory.onChange = { snapshot in
            let t = fmt((ContinuousClock.now - start).milliseconds / 1000, 2)
            let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let after = Dictionary(snapshot.windows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for w in snapshot.windows where before[w.id] == nil { print("\(t)s + \(w.id) \(w.appName) “\(w.title)” (\(w.kind.rawValue))") }
            for w in previous where after[w.id] == nil { print("\(t)s − \(w.id) \(w.appName) “\(w.title)”") }
            for w in snapshot.windows {
                guard let old = before[w.id] else { continue }
                if old.title != w.title { print("\(t)s ~ \(w.id) title “\(old.title)” → “\(w.title)”") }
                if old.kind != w.kind { print("\(t)s ~ \(w.id) \(old.kind.rawValue) → \(w.kind.rawValue)") }
            }
            if previous.map(\.id) != snapshot.windows.map(\.id), let first = snapshot.windows.first {
                print("\(t)s   most recent: \(first.id) \(first.appName) “\(first.title)” (refresh \(fmt(snapshot.refreshMs, 2)) ms)")
            }
            previous = snapshot.windows
        }
        inventory.start()
        print("Watching windows for \(Int(seconds)) s. Open, close, rename, minimize and switch windows.")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        print(WindowReport.table(inventory.snapshot.windows, focusedID: inventory.snapshot.focusedID))
        print("\(inventory.snapshot.refreshCount) refreshes; CPU \(fmt(cpu, 3)) s over \(Int(seconds)) s (\(fmt(cpu / seconds * 100, 3))%)")
    }
}

extension CommandLineTools {
    /// Focuses one window the way the switcher does and confirms it, as spike S1 did.
    @MainActor
    static func focus(_ id: WindowID) -> Int32 {
        _ = NSApplication.shared
        let inventory = WindowInventory()
        inventory.start()
        let deadline = Date().addingTimeInterval(3)
        while inventory.snapshot.windows.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        guard let window = inventory.snapshot.windows.first(where: { $0.id == id }) else {
            print("No window \(id). Run --dump-windows for ids.")
            return 1
        }
        let focuser = WindowFocuser(inventory: inventory)
        var outcome: WindowFocuser.Outcome?
        let start = ContinuousClock.now
        focuser.focus(window) { outcome = $0 }
        while outcome == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        let confirmed = focuser.confirmFocus(window)
        let total = (ContinuousClock.now - start).milliseconds
        let label = "\(window.appName) (\(window.kind.rawValue)) via \(outcome!.method.rawValue)"
        if confirmed != nil {
            print("[ok] \(id) \(label): request \(fmt(outcome!.requestMs)) ms, focus confirmed \(fmt(total)) ms after the request")
            return 0
        }
        print("[FAIL] \(id) \(label): not the focused window within 1.5 s (request \(fmt(outcome!.requestMs)) ms)")
        return 1
    }
}

extension CommandLineTools {
    @MainActor
    static func renderPreview(to path: String, sample: Int?) -> Int32 {
        _ = NSApplication.shared
        var model = SwitcherModel()
        if let sample {
            let apps = ["Safari", "Zed", "Ghostty", "Finder", "Xcode", "Notes", "Mail", "T3 Code"]
            let kinds: [WindowInfo.Kind] = [.onScreen, .onScreen, .otherSpace, .minimized, .appHidden]
            model.cards = (0..<sample).map { i in
                let app = apps[i % apps.count]
                let icon = NSWorkspace.shared.icon(for: .application)
                return .init(id: WindowID(i + 1), title: i % 7 == 3 ? "設計メモ — 日本語のタイトル \(i)" : "\(app) window \(i) with a fairly long title", appName: app,
                             icon: icon, image: nil, kind: kinds[i % kinds.count])
            }
        } else {
            let (windows, _, _) = WindowInventory.buildOnce()
            model.cards = windows.map { w in
                .init(id: w.id, title: w.title, appName: w.appName, icon: NSRunningApplication(processIdentifier: w.pid)?.icon,
                      image: nil, kind: w.kind)
            }
        }
        model.selectedIndex = model.cards.count > 1 ? 1 : 0
        model.hint = "release ⌥ to switch  ·  esc to cancel  ·  type to search"
        guard let screen = NSScreen.screens.first, let image = SwitcherWindowController().renderImage(model, on: screen),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return 1 }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return 1 }
        print("wrote \(path) (\(image.width)×\(image.height) px, \(model.cards.count) cards)")
        return 0
    }
}
