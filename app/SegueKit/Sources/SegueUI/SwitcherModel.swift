import AppKit
import SegueCore

/// What the switcher view shows.
public struct SwitcherModel {
    public struct Card: Identifiable {
        public var id: WindowID
        public var title: String
        public var appName: String
        public var icon: NSImage?
        public var image: CGImage?
        public var kind: WindowInfo.Kind

        public init(id: WindowID, title: String, appName: String, icon: NSImage?, image: CGImage?, kind: WindowInfo.Kind) {
            self.id = id
            self.title = title
            self.appName = appName
            self.icon = icon
            self.image = image
            self.kind = kind
        }
    }

    public var cards: [Card] = []
    public var selectedIndex: Int?
    public var query = ""
    public var isSearching = false
    /// Whether the search bar shows, even while empty (a search was started).
    public var showsSearchBar = false
    /// Key hints along the bottom edge.
    public var hint = ""

    public init() {}

    public var selected: Card? { selectedIndex.flatMap { cards.indices.contains($0) ? cards[$0] : nil } }
}
