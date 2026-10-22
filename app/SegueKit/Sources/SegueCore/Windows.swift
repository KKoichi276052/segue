import CoreGraphics

public typealias WindowID = UInt32

/// One window as the Window Server reports it (`CGWindowListCopyWindowInfo`), front to back.
public struct ServerWindow: Equatable, Sendable {
    public var id: WindowID
    public var pid: Int32
    public var ownerName: String
    /// nil when the title isn't readable (other apps' titles need Screen Recording);
    /// "" when it's readable and empty.
    public var title: String?
    /// Top-left origin, y down: the same space as Accessibility frames.
    public var bounds: CGRect
    public var isOnScreen: Bool
    public var layer: Int
    public var alpha: Double

    public init(id: WindowID, pid: Int32, ownerName: String, title: String?, bounds: CGRect,
                isOnScreen: Bool, layer: Int = 0, alpha: Double = 1) {
        self.id = id
        self.pid = pid
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.isOnScreen = isOnScreen
        self.layer = layer
        self.alpha = alpha
    }
}

/// One window as Accessibility reports it. Only windows on the current Space appear.
public struct AXWindowRecord: Equatable, Sendable {
    public var windowID: WindowID?
    public var pid: Int32
    public var title: String?
    public var frame: CGRect?
    public var isMinimized: Bool
    public var role: String?
    public var subrole: String?

    public init(windowID: WindowID?, pid: Int32, title: String?, frame: CGRect?, isMinimized: Bool,
                role: String? = "AXWindow", subrole: String? = "AXStandardWindow") {
        self.windowID = windowID
        self.pid = pid
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.role = role
        self.subrole = subrole
    }
}

/// A running app that can own user windows.
public struct AppRecord: Equatable, Sendable {
    public var pid: Int32
    public var name: String
    public var bundleID: String?
    public var isHidden: Bool

    public init(pid: Int32, name: String, bundleID: String?, isHidden: Bool = false) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.isHidden = isHidden
    }
}

/// A user window as Segue shows it.
public struct WindowInfo: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case onScreen = "on screen"
        case minimized
        case appHidden = "app hidden"
        case otherSpace = "other Space"
    }

    public var id: WindowID
    public var pid: Int32
    public var appName: String
    public var bundleID: String?
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
    public var isOnScreen: Bool
    /// Whether Accessibility returned an element for it (the current Space).
    public var hasAccessibilityElement: Bool

    public init(id: WindowID, pid: Int32, appName: String, bundleID: String?, title: String, frame: CGRect,
                isMinimized: Bool, isAppHidden: Bool, isOnScreen: Bool, hasAccessibilityElement: Bool) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isAppHidden = isAppHidden
        self.isOnScreen = isOnScreen
        self.hasAccessibilityElement = hasAccessibilityElement
    }

    public var kind: Kind {
        if isMinimized { return .minimized }
        if isAppHidden { return .appHidden }
        if isOnScreen { return .onScreen }
        return .otherSpace
    }
}

/// Merges the Window Server list with Accessibility into the windows Segue shows.
public enum WindowMerger {
    /// Smaller windows are helpers (tooltips, offscreen buffers), not user windows.
    public static let minimumSide: CGFloat = 100
    /// Accessibility subroles that are user windows. Palettes, sheets and system dialogs aren't.
    public static let userSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

    public struct Result: Equatable, Sendable {
        /// In Window Server order (front to back).
        public var windows: [WindowInfo]
        /// For each window, the index of its Accessibility record in the input.
        public var axIndex: [WindowID: Int]
    }

    /// - Parameters:
    ///   - axReadPIDs: apps whose Accessibility windows were read successfully. An on-screen
    ///     window of such an app with no Accessibility match isn't a user window.
    ///   - rememberedTitles: titles seen earlier through Accessibility, for windows now on
    ///     other Spaces when the Window Server hides titles.
    public static func merge(server: [ServerWindow], ax: [AXWindowRecord], apps: [AppRecord], axReadPIDs: Set<Int32>,
                             rememberedTitles: [WindowID: String] = [:], ownPID: Int32) -> Result {
        let appsByPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var axByID: [WindowID: Int] = [:]
        var unidentified: [Int32: [Int]] = [:]
        for (i, record) in ax.enumerated() {
            if let id = record.windowID {
                axByID[id] = axByID[id] ?? i
            } else {
                unidentified[record.pid, default: []].append(i)
            }
        }

        var windows: [WindowInfo] = []
        var axIndex: [WindowID: Int] = [:]
        for s in server {
            guard s.pid != ownPID, let app = appsByPID[s.pid], s.layer == 0, s.alpha > 0,
                  s.bounds.width >= minimumSide, s.bounds.height >= minimumSide
            else { continue }

            var match = axByID[s.id].flatMap { ax[$0].pid == s.pid ? $0 : nil }
            if match == nil, var candidates = unidentified[s.pid], !candidates.isEmpty {
                // No window IDs from Accessibility: match by frame, preferring an equal title.
                let close = candidates.filter { ax[$0].frame.map { isClose($0, s.bounds) } ?? false }
                let pick = close.first { s.title != nil && ax[$0].title == s.title } ?? close.first
                if let pick {
                    match = pick
                    candidates.removeAll { $0 == pick }
                    unidentified[s.pid] = candidates
                }
            }

            let record = match.map { ax[$0] }
            if let record {
                if let role = record.role, role != "AXWindow" { continue }
                if let subrole = record.subrole, !userSubroles.contains(subrole) { continue }
            } else {
                if s.isOnScreen && axReadPIDs.contains(s.pid) && !app.isHidden { continue }
                // A readable, empty title and nothing remembered: an untitled helper window.
                if s.title == "" && rememberedTitles[s.id] == nil { continue }
            }

            let title = [record?.title, s.title, rememberedTitles[s.id]].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            windows.append(WindowInfo(
                id: s.id, pid: s.pid, appName: app.name, bundleID: app.bundleID, title: title, frame: s.bounds,
                isMinimized: record?.isMinimized ?? false, isAppHidden: app.isHidden, isOnScreen: s.isOnScreen,
                hasAccessibilityElement: record != nil
            ))
            if let match { axIndex[s.id] = match }
        }
        return Result(windows: windows, axIndex: axIndex)
    }

    private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}

/// Windows in the order they were last used, most recent first.
public struct RecencyList: Equatable, Sendable {
    public private(set) var order: [WindowID] = []

    public init(order: [WindowID] = []) {
        self.order = order
    }

    /// Drops windows that are gone and adds new ones after the known ones, in the given
    /// order (the Window Server's front-to-back order, which seeds the list at launch).
    public mutating func sync(_ current: [WindowID]) {
        let present = Set(current)
        order.removeAll { !present.contains($0) }
        let known = Set(order)
        order.append(contentsOf: current.filter { !known.contains($0) })
    }

    /// Marks a window as just used.
    public mutating func touch(_ id: WindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    public func sorted(_ windows: [WindowInfo]) -> [WindowInfo] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return windows.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max, rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
}
