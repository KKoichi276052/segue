import AppKit
import ApplicationServices
import Darwin

// The private calls Segue accepts (docs/SPEC.md §9 "Private APIs"), adapted from
// spikes/Sources/SpikeKit/Windows.swift and Focus.swift. Every symbol is resolved at run
// time, so a macOS update that removes one degrades Segue instead of crashing it at launch.
// The remote-token lookup (`_AXUIElementCreateWithRemoteToken`) is deliberately not used.

public enum PrivateAPI {
    /// Which private calls are usable. The debug defaults `DebugDisableAXWindowID` and
    /// `DebugDisableSkyLight` pretend one is missing, to exercise the fallbacks.
    public struct Availability: Equatable, Sendable {
        public var axWindowID: Bool
        public var skyLightFocus: Bool

        public var allAvailable: Bool { axWindowID && skyLightFocus }

        public var fallbackNotes: [String] {
            var notes: [String] = []
            if !axWindowID { notes.append("Window matching uses app, title and frame (private call unavailable)") }
            if !skyLightFocus { notes.append("Windows on other Spaces open their app only (private call unavailable)") }
            return notes
        }
    }

    public static var availability: Availability {
        Availability(axWindowID: getWindow != nil, skyLightFocus: setFrontProcess != nil && postEventRecord != nil && getProcessForPID != nil)
    }

    // MARK: _AXUIElementGetWindow

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindow? = disabled("DebugDisableAXWindowID")
        ? nil : symbol(defaultHandle, "_AXUIElementGetWindow", as: GetWindow.self)

    /// The window ID of an Accessibility window, or nil if it has none or the call is unavailable.
    public static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }

    // MARK: SkyLight focus

    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    /// SkyLight is in the dyld shared cache, so it's loaded at run time instead of linked.
    nonisolated(unsafe) private static let skyLight = disabled("DebugDisableSkyLight")
        ? nil : dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let setFrontProcess = symbol(skyLight, "_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    private static let postEventRecord = symbol(skyLight, "SLPSPostEventRecordTo", as: PostEventRecord.self)
    private static let getProcessForPID = symbol(defaultHandle, "GetProcessForPID", as: GetProcessForPID.self)

    /// Brings the window's app to the front with that window, switching Space if needed, then
    /// makes the window key. Returns false if the calls are unavailable or fail.
    public static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFrontProcess, let postEventRecord, let getProcessForPID else { return false }
        var psn = ProcessSerialNumber()
        guard getProcessForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        // Synthetic "make key window" event records, as AltTab sends them.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecord(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecord(&psn, &bytes)
        return true
    }

    // MARK: Self-check

    /// Resolves every call and, where it can without side effects, tries it. Focus isn't
    /// tried, because it would change the frontmost window.
    public static func selfCheck() -> [(name: String, ok: Bool, detail: String)] {
        var results: [(String, Bool, String)] = []
        let id = getWindow != nil
        var idDetail = id ? "resolved" : (disabled("DebugDisableAXWindowID") ? "disabled by DebugDisableAXWindowID" : "symbol missing")
        if id, AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            if let window: AXUIElement = AX.attribute(element, kAXFocusedWindowAttribute) {
                if let wid = windowID(of: window) {
                    idDetail += "; frontmost window of \(app.localizedName ?? "?") is \(wid)"
                } else {
                    idDetail += "; returned no ID for the frontmost window of \(app.localizedName ?? "?")"
                }
            }
        }
        results.append(("_AXUIElementGetWindow", id, idDetail))
        let skyDisabled = disabled("DebugDisableSkyLight")
        results.append(("SkyLight framework", skyLight != nil, skyDisabled ? "disabled by DebugDisableSkyLight" : skyLight != nil ? "loaded" : "dlopen failed"))
        results.append(("_SLPSSetFrontProcessWithOptions", setFrontProcess != nil, setFrontProcess != nil ? "resolved" : "missing"))
        results.append(("SLPSPostEventRecordTo", postEventRecord != nil, postEventRecord != nil ? "resolved" : "missing"))
        results.append(("GetProcessForPID", getProcessForPID != nil, getProcessForPID != nil ? "resolved" : "missing"))
        return results
    }

    // MARK: Loading

    nonisolated(unsafe) private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static func disabled(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}
