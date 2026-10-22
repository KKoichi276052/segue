import AppKit
import ApplicationServices
import CoreGraphics
import SegueCore

// Adapted from spikes/Sources/SpikeKit/Permissions.swift.

/// Reads and requests Segue's permissions (docs/SPEC.md §6.13).
public enum PermissionsCoordinator {
    public static var macOSMajor: Int { ProcessInfo.processInfo.operatingSystemVersion.majorVersion }

    public static func current() -> PermissionStatus {
        PermissionStatus(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    /// Asks macOS to show its prompt, which also adds Segue to the pane's list.
    public static func request(_ kind: PermissionKind) {
        Log.permissions.info("requesting \(String(describing: kind), privacy: .public)")
        switch kind {
        case .control:
            let key = "AXTrustedCheckOptionPrompt" as CFString
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
    }

    public static func openSettings(_ kind: PermissionKind) {
        let anchor = kind == .control ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func describe(_ status: PermissionStatus) -> String {
        "\(PermissionKind.control.paneName(macOSMajor: macOSMajor)) \(status.accessibility ? "granted" : "missing") · "
            + "Input Monitoring \(status.inputMonitoring ? "granted" : "missing") · "
            + "Screen Recording \(status.screenRecording ? "granted" : "missing")"
    }

    /// Quits and opens Segue again, for permissions macOS applies only at launch.
    @MainActor
    public static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
