import AppKit
import CoreGraphics
import SegueCore

// Adapted from spikes/Sources/SpikeKit/Windows.swift.
public enum WindowServer {
    /// Every window, front to back, including off-screen ones (minimized, hidden apps,
    /// other Spaces). Titles of other apps' windows need Screen Recording.
    public static func list() -> [ServerWindow] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return ServerWindow(
                id: id, pid: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "?",
                title: entry[kCGWindowName as String] as? String,
                bounds: bounds,
                isOnScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false,
                layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1
            )
        }
    }
}

extension AppRecord {
    /// Running apps that can own user windows. Call on the main thread.
    @MainActor
    public static func running() -> [AppRecord] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map { AppRecord(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "?",
                             bundleID: $0.bundleIdentifier, isHidden: $0.isHidden) }
    }
}
