import ApplicationServices
import CoreGraphics

public enum Permissions {
    /// Checks Accessibility and, if `prompt` is set, asks macOS to show its prompt.
    @discardableResult
    public static func accessibility(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    @discardableResult
    public static func screenRecording(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return prompt ? CGRequestScreenCaptureAccess() : false
    }

    public static var inputMonitoring: Bool { CGPreflightListenEventAccess() }

    public static func describe() -> String {
        "Accessibility \(accessibility(prompt: false) ? "granted" : "missing") · "
            + "Screen Recording \(CGPreflightScreenCaptureAccess() ? "granted" : "missing") · "
            + "Input Monitoring \(CGPreflightListenEventAccess() ? "granted" : "missing")"
    }

    /// Permissions belong to the app that launched the process (the terminal), not this binary.
    public static let hint = "Grant it to the terminal app you run the spikes from (System Settings › Privacy & Security), then restart that terminal."
}
