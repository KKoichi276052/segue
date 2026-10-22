/// A least-recently-used cache with a byte budget (docs/SPEC.md §8: about 60 MB of window
/// images). Images stay in memory only.
public struct ByteLRU<Key: Hashable, Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var stamp: UInt64
        var storedAt: Double
    }

    public let capacity: Int
    public private(set) var totalCost = 0
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public var count: Int { entries.count }

    /// Returns the value and marks it as just used.
    public mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock += 1
        entry.stamp = clock
        entries[key] = entry
        return entry.value
    }

    /// When the value was stored, in the caller's time base.
    public func storedAt(_ key: Key) -> Double? { entries[key]?.storedAt }

    public func contains(_ key: Key) -> Bool { entries[key] != nil }

    /// Stores a value, then drops the least recently used entries until the total fits.
    /// A value larger than the whole budget isn't stored.
    public mutating func insert(_ value: Value, for key: Key, cost: Int, at time: Double) {
        remove(key)
        guard cost <= capacity else { return }
        clock += 1
        entries[key] = Entry(value: value, cost: cost, stamp: clock, storedAt: time)
        totalCost += cost
        while totalCost > capacity, let oldest = entries.min(by: { $0.value.stamp < $1.value.stamp })?.key {
            remove(oldest)
        }
    }

    public mutating func remove(_ key: Key) {
        if let entry = entries.removeValue(forKey: key) { totalCost -= entry.cost }
    }

    /// Drops every entry whose key isn't in `keys`, for example closed windows.
    public mutating func retain(_ keys: Set<Key>) {
        for key in entries.keys where !keys.contains(key) { remove(key) }
    }
}

/// Which window images to refresh when the switcher shows (docs/SPEC.md §15: show the
/// cached image at once and refresh it in the background).
public enum PreviewRefresh {
    /// The selected window first, then the others in display order, skipping images newer
    /// than `minAge` seconds, so showing and hiding quickly doesn't capture the same windows
    /// over and over.
    public static func order(visible: [WindowID], selected: WindowID?, storedAt: (WindowID) -> Double?,
                             now: Double, minAge: Double = 2) -> [WindowID] {
        var ids = visible
        if let selected, let i = ids.firstIndex(of: selected) {
            ids.remove(at: i)
            ids.insert(selected, at: 0)
        }
        return ids.filter { id in storedAt(id).map { now - $0 >= minAge } ?? true }
    }

    /// Pixel size for a capture: no wider than `maxPixelWidth` and no more than `maxScale`
    /// pixels per window point, keeping the window's shape.
    public static func pixelSize(windowSize: (width: Double, height: Double), maxPixelWidth: Double = 600,
                                 maxScale: Double = 0.7) -> (width: Int, height: Int) {
        guard windowSize.width > 0, windowSize.height > 0 else { return (1, 1) }
        let scale = min(maxScale, maxPixelWidth / windowSize.width)
        return (max(1, Int(windowSize.width * scale)), max(1, Int(windowSize.height * scale)))
    }
}
