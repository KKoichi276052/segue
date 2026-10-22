import AppKit
import ApplicationServices

/// Private call (used by AltTab and others) that maps an Accessibility window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// One window as seen by the Window Server (`CGWindowListCopyWindowInfo`).
public struct CGWindow {
    public let id: CGWindowID
    public let pid: pid_t
    public let owner: String
    public let title: String?
    public let bounds: CGRect
    public let isOnScreen: Bool
}

/// One window as seen through Accessibility.
public struct AXWindow {
    public let element: AXUIElement
    public let pid: pid_t
    public let app: String
    public let windowID: CGWindowID?
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool
    public let subrole: String?
}

public enum WindowList {
    /// Normal-layer windows from the Window Server, including off-screen ones
    /// (minimized, hidden apps, other Spaces).
    public static func cgWindows() -> [CGWindow] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            // Drop tiny helper windows (tooltips, offscreen buffers).
            guard bounds.width >= 50, bounds.height >= 50 else { return nil }
            return CGWindow(
                id: id,
                pid: pid,
                owner: entry[kCGWindowOwnerName as String] as? String ?? "?",
                title: entry[kCGWindowName as String] as? String,
                bounds: bounds,
                isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false
            )
        }
    }

    /// Apps that can own user windows.
    public static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
    }

    /// Accessibility windows for every regular app. Each app gets `timeout` seconds
    /// so one frozen app cannot stall the listing (spec §8 Reliability).
    public static func axWindows(timeout: Float = 0.25) -> [AXWindow] {
        regularApps().flatMap { axWindows(of: $0, timeout: timeout) }
    }

    public static func axWindows(of app: NSRunningApplication, timeout: Float = 0.25) -> [AXWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, timeout)
        let windows: [AXUIElement] = AX.attribute(appElement, kAXWindowsAttribute) ?? []
        return windows.map { window in
            return AXWindow(
                element: window,
                pid: app.processIdentifier,
                app: app.localizedName ?? app.bundleIdentifier ?? "?",
                windowID: AX.windowID(window),
                title: AX.attribute(window, kAXTitleAttribute) ?? "",
                frame: AX.frame(window) ?? .zero,
                isMinimized: AX.attribute(window, kAXMinimizedAttribute) ?? false,
                subrole: AX.attribute(window, kAXSubroleAttribute)
            )
        }
    }
}

public enum AX {
    public static func windowID(_ window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    public static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    public static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> AXError {
        var p = point
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    }

    @discardableResult
    public static func setSize(_ element: AXUIElement, _ size: CGSize) -> AXError {
        var s = size
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    }

    @discardableResult
    public static func setBool(_ element: AXUIElement, _ name: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value as CFBoolean)
    }
}

extension NSScreen {
    /// The visible frame (below the menu bar, beside the Dock) in Accessibility
    /// coordinates: origin at the top left of the primary display, y pointing down.
    public var visibleFrameInAXCoordinates: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let v = visibleFrame
        return CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
    }
}

extension CGRect {
    public var short: String {
        "(\(Int(minX)),\(Int(minY)) \(Int(width))×\(Int(height)))"
    }

    public func isClose(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
