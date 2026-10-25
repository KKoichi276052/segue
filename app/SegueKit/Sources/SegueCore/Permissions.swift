/// Which permissions Segue has (docs/SPEC.md §6.13).
public struct PermissionStatus: Equatable, Sendable {
    /// Accessibility; shown as Device Control and Data Access on macOS 27. Required: listing,
    /// focusing and the hold-mode event tap.
    public var accessibility: Bool
    /// Input Monitoring. On macOS 27 it came with Device Control and Data Access in S6; on
    /// macOS 26 it may be separate. Recorded, not required.
    public var inputMonitoring: Bool
    /// Screen Recording: window images and the titles of windows on other Spaces. Optional.
    public var screenRecording: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.screenRecording = screenRecording
    }

    public var canSwitch: Bool { accessibility }
}

public enum PermissionKind: Sendable, CaseIterable {
    case control
    case screenRecording

    /// The System Settings pane's name on the given macOS major version.
    public func paneName(macOSMajor: Int) -> String {
        switch self {
        case .control: macOSMajor >= 27 ? "Device Control and Data Access" : "Accessibility"
        case .screenRecording: "Screen Recording"
        }
    }

    public var purpose: String {
        switch self {
        case .control:
            "Lets Segue list your windows, bring the one you pick to the front, and notice when you hold ⌥ and press Tab."
        case .screenRecording:
            "Lets Segue show a picture of each window, and the titles of windows on other Spaces. Images stay in memory and never leave your Mac. Without it, windows show as their app icon and title."
        }
    }
}

/// The first-launch flow: control first, then optionally Screen Recording.
public enum PermissionsFlow {
    public enum Step: Equatable, Sendable {
        case control
        case screenRecording
        case done
    }

    public static func step(for status: PermissionStatus, screenRecordingSkipped: Bool) -> Step {
        if !status.accessibility { return .control }
        if !status.screenRecording && !screenRecordingSkipped { return .screenRecording }
        return .done
    }

    /// Lines for the menu bar item describing what's missing; empty when nothing is.
    public static func warnings(for status: PermissionStatus, macOSMajor: Int) -> [String] {
        var lines: [String] = []
        if !status.accessibility {
            lines.append("Needs \(PermissionKind.control.paneName(macOSMajor: macOSMajor)) to switch windows")
        }
        if !status.screenRecording {
            lines.append("No Screen Recording: previews show icons and titles")
        }
        return lines
    }
}
