import AppKit
import SegueCore

/// Moves to the Space a window is on before it's focused (see `SpaceRoute`), by pressing
/// Mission Control's "Move left/right a space" shortcuts (Control-arrow by default) once
/// per Space, then waiting until the Window Server reports the target Space as current.
///
/// Known limit: the shortcuts act on the display Mission Control considers active, so a
/// window on a hidden Space of the other display may not be reached.
@MainActor
public enum SpaceSwitcher {
    public enum Result: Sendable, CustomStringConvertible {
        case notNeeded
        case arrived(steps: Int, ms: Double)
        case timedOut(steps: Int)
        case unavailable(String)

        public var description: String {
            switch self {
            case .notNeeded: "no Space move needed"
            case .arrived(let steps, let ms): "moved \(steps) Space\(abs(steps) == 1 ? "" : "s") in \(fmt(ms)) ms"
            case .timedOut(let steps): "pressed the shortcut \(abs(steps))×, Space didn't change within 2 s (are Move left/right a space on in Keyboard Shortcuts › Mission Control?)"
            case .unavailable(let why): "can't move Space: \(why)"
            }
        }
    }

    /// Moves if needed, then calls `completion` on the main thread.
    public static func moveToSpace(of windowID: CGWindowID, timeout: TimeInterval = 2, completion: @escaping @MainActor (Result) -> Void) {
        guard let displays = PrivateAPI.displaySpaces(), let windowSpaces = PrivateAPI.spaces(ofWindow: windowID) else {
            return completion(.unavailable("Space calls missing"))
        }
        guard let route = SpaceRoute.compute(windowSpaces: windowSpaces, displays: displays), route.steps != 0 else {
            return completion(.notNeeded)
        }
        guard let key = shortcut(right: route.steps > 0) else {
            return completion(.unavailable("the Move \(route.steps > 0 ? "right" : "left") a space shortcut is off"))
        }
        let start = ContinuousClock.now
        for _ in 0..<abs(route.steps) { press(key) }
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            let current = PrivateAPI.displaySpaces()?.first { $0.id == route.display }?.current
            if current == route.target {
                return completion(.arrived(steps: route.steps, ms: (ContinuousClock.now - start).milliseconds))
            }
            guard Date() < deadline else { return completion(.timedOut(steps: route.steps)) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { MainActor.assumeIsolated { poll() } }
        }
        poll()
    }

    private struct Shortcut {
        var keyCode: CGKeyCode
        var flags: CGEventFlags
    }

    /// The shortcut from System Settings › Keyboard › Keyboard Shortcuts › Mission Control,
    /// or the default (Control-arrow) when it was never changed. Nil when it's turned off.
    private static func shortcut(right: Bool) -> Shortcut? {
        // Symbolic hot keys 79 and 81: Move left a space, Move right a space.
        let key = right ? "81" : "79"
        let fallback = Shortcut(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = all[key] as? [String: Any]
        else { return fallback }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        guard let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], parameters.count >= 3
        else { return fallback }
        return Shortcut(keyCode: CGKeyCode(parameters[1].intValue), flags: CGEventFlags(rawValue: parameters[2].uint64Value))
    }

    private static func press(_ key: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key.keyCode, keyDown: down) else { continue }
            event.flags = key.flags
            event.post(tap: .cghidEventTap)
        }
    }
}
