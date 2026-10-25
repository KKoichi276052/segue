import Foundation
import SegueCore

/// User defaults. M1 has no settings window: change these with
/// `defaults write io.github.kkoichi276052.segue <key> <value>` and relaunch.
///
/// - `TapHotkey` (string, default "option+space"): opens the switcher and keeps it open.
/// - `ShowDelayMs` (integer, default 100, 0–250): how long ⌥ Tab is held before the switcher shows.
/// - `KeepPanelOnScreen` (bool, default false): keep the panel on screen but transparent.
/// - `DebugKeyLog` (bool): log raw modifier and navigation keys (also in the Debug menu).
/// - `DebugDisableAXWindowID`, `DebugDisableSkyLight` (bool): pretend a private call is missing.
enum Settings {
    private static var defaults: UserDefaults { .standard }

    /// Set when the owner skips Screen Recording in the first-launch window.
    static var screenRecordingSkipped: Bool {
        get { defaults.bool(forKey: "ScreenRecordingSkipped") }
        set { defaults.set(newValue, forKey: "ScreenRecordingSkipped") }
    }

    static var tapHotkeyText: String { defaults.string(forKey: "TapHotkey") ?? "option+space" }

    static var tapHotkey: HotkeySpec? { HotkeySpec.parse(tapHotkeyText) }

    static var showDelayMs: Int {
        guard defaults.object(forKey: "ShowDelayMs") != nil else { return 100 }
        return min(250, max(0, defaults.integer(forKey: "ShowDelayMs")))
    }

    static var keepPanelOnScreen: Bool { defaults.bool(forKey: "KeepPanelOnScreen") }

    static var debugKeyLog: Bool {
        get { defaults.bool(forKey: "DebugKeyLog") }
        set { defaults.set(newValue, forKey: "DebugKeyLog") }
    }
}
