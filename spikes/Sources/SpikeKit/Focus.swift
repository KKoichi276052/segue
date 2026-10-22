import AppKit
import ApplicationServices

// Private calls for reaching and focusing windows on other Spaces, as AltTab does.
// Accessibility's `AXWindows` only returns the current Space's windows, so these are the
// only known ways to focus a window elsewhere without the user switching Spaces first.

/// Builds an Accessibility element from a remote token (pid, 0, 'coco', element ID).
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

@_silgen_name("GetProcessForPID")
func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

/// SkyLight is in the dyld shared cache, so it's loaded at run time instead of linked.
private enum SkyLight {
    typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    nonisolated(unsafe) static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    static let setFrontProcess = symbol("_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    static let postEventRecord = symbol("SLPSPostEventRecordTo", as: PostEventRecord.self)
}

public enum OffSpace {
    /// Finds a window's Accessibility element even when it's on another Space, by trying
    /// element IDs through remote tokens. Returns the element and how many IDs were tried.
    public static func element(pid: pid_t, windowID: CGWindowID, maxElementID: UInt64 = 2000) -> (AXUIElement?, tried: UInt64) {
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: Int32(pid), toByteOffset: 0, as: Int32.self)
            raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            raw.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
        }
        for id in 0..<maxElementID {
            token.withUnsafeMutableBytes { $0.storeBytes(of: id, toByteOffset: 12, as: UInt64.self) }
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            let role: String? = AX.attribute(element, kAXRoleAttribute)
            if role == kAXWindowRole, AX.windowID(element) == windowID { return (element, id + 1) }
        }
        return (nil, maxElementID)
    }

    /// Brings the window's app to the front with that window, switching Space if needed,
    /// then makes the window key. Returns false if the private calls aren't available.
    public static func focus(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let setFront = SkyLight.setFrontProcess, let post = SkyLight.postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard _GetProcessForPID(pid, &psn) == noErr else { return false }
        let userGenerated: UInt32 = 0x200
        guard setFront(&psn, windowID, userGenerated) == .success else { return false }
        // Synthetic "make key window" event records, as AltTab sends them.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = post(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = post(&psn, &bytes)
        return true
    }
}
