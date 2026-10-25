import AppKit
import ApplicationServices
import SegueCore

/// Focuses a specific window (docs/SPEC.md §9 `WindowController`, focus part), adapted from
/// the spike's focus routine (spikes/Sources/s1-windows/main.swift).
///
/// With SkyLight available, every window goes through it, as in AltTab: it brings the app
/// forward with that window, switching Space if needed, without depending on the
/// cooperative activation rules that can refuse `activate()` from a background app. The
/// window is then raised through Accessibility when it has an element. Without SkyLight,
/// windows on the current Space use Accessibility and others only activate their app.
///
/// All Accessibility calls run on the inventory's thread; unminimizing blocks there for
/// about 270 ms (the animation) but never on the main thread.
public final class WindowFocuser: Sendable {
    public enum Method: String, Sendable {
        case skyLight = "SkyLight"
        case accessibility = "Accessibility"
        case activateApp = "activate app only"
        case failed
    }

    public struct Outcome: Sendable {
        public var method: Method
        public var requestMs: Double
    }

    private let inventory: WindowInventory

    public init(inventory: WindowInventory) {
        self.inventory = inventory
    }

    public func focus(_ window: WindowInfo, completion: (@MainActor @Sendable (Outcome) -> Void)? = nil) {
        let id = window.id
        let pid = window.pid
        let wasHidden = window.isAppHidden
        let signpost = Log.signposter.beginInterval("focus", id: Log.signposter.makeSignpostID())
        inventory.withElement(id) { [inventory] element in
            let start = ContinuousClock.now
            if wasHidden {
                DispatchQueue.main.sync { _ = NSRunningApplication(processIdentifier: pid)?.unhide() }
            }
            if let element, AX.attribute(element, kAXMinimizedAttribute) == true {
                AX.setBool(element, kAXMinimizedAttribute, false)
            }
            var method: Method
            if PrivateAPI.focus(pid: pid, windowID: id) {
                method = .skyLight
                if let element { AX.perform(element, kAXRaiseAction) }
            } else if let element {
                method = .accessibility
                AX.setBool(element, kAXMainAttribute, true)
                AX.perform(element, kAXRaiseAction)
                DispatchQueue.main.async { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
            } else if let app = NSRunningApplication(processIdentifier: pid) {
                method = .activateApp
                DispatchQueue.main.async { _ = app.activate() }
            } else {
                method = .failed
            }
            let ms = (ContinuousClock.now - start).milliseconds
            Log.signposter.endInterval("focus", signpost)
            Log.focus.info("focus \(id) via \(method.rawValue, privacy: .public) in \(fmt(ms, 1), privacy: .public) ms")
            if method != .failed { inventory.touch(id) }
            let outcome = Outcome(method: method, requestMs: ms)
            if let completion {
                DispatchQueue.main.async { MainActor.assumeIsolated { completion(outcome) } }
            }
        }
    }

    /// Waits until the window is the focused window of the frontmost app, or the timeout
    /// passes. Returns the time from now until it was confirmed. For checks, not normal use.
    public func confirmFocus(_ window: WindowInfo, timeout: TimeInterval = 1.5) -> Double? {
        let start = ContinuousClock.now
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid else { continue }
            let app = AXUIElementCreateApplication(window.pid)
            if let focused: AXUIElement = AX.attribute(app, kAXFocusedWindowAttribute), PrivateAPI.windowID(of: focused) == window.id {
                return (ContinuousClock.now - start).milliseconds
            }
        }
        return nil
    }
}
