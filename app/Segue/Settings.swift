import Foundation

/// User defaults. M1 has no settings window: change these with
/// `defaults write io.github.kkoichi276052.segue <key> <value>` and relaunch.
enum Settings {
    private static var defaults: UserDefaults { .standard }

    /// Set when the owner skips Screen Recording in the first-launch window.
    static var screenRecordingSkipped: Bool {
        get { defaults.bool(forKey: "ScreenRecordingSkipped") }
        set { defaults.set(newValue, forKey: "ScreenRecordingSkipped") }
    }
}
