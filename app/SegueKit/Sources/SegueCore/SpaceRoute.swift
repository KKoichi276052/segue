/// How to reach the Space a window is on with the "Move left/right a space" shortcuts.
///
/// On macOS 27, bringing a window on another Space to the front (SkyLight) no longer
/// switches to that Space: the app activates but the screen stays where it was. Segue
/// moves there first, one Space per shortcut press, in Mission Control's order.
public struct SpaceRoute: Equatable, Sendable {
    /// One display's Spaces, as the Window Server lists them.
    public struct Display: Equatable, Sendable {
        public var id: String
        public var current: UInt64
        /// In Mission Control's order, left to right, full-screen apps included.
        public var spaces: [UInt64]

        public init(id: String, current: UInt64, spaces: [UInt64]) {
            self.id = id
            self.current = current
            self.spaces = spaces
        }
    }

    public var display: String
    public var target: UInt64
    /// Negative moves left, positive right.
    public var steps: Int

    /// The route to the first of the window's Spaces, or nil when it is already showing on
    /// its display (or the Spaces aren't known).
    public static func compute(windowSpaces: [UInt64], displays: [Display]) -> SpaceRoute? {
        // A window on every Space, or one already showing, needs no move.
        if windowSpaces.contains(where: { space in displays.contains { $0.current == space } }) { return nil }
        for display in displays {
            for space in windowSpaces {
                guard let to = display.spaces.firstIndex(of: space), let from = display.spaces.firstIndex(of: display.current)
                else { continue }
                return SpaceRoute(display: display.id, target: space, steps: to - from)
            }
        }
        return nil
    }
}
