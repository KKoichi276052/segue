/// Plain-text tables of windows, for the Debug menu and `--dump-windows`.
public enum WindowReport {
    public static func table(_ windows: [WindowInfo], focusedID: WindowID? = nil) -> String {
        var lines = [columns([("#", 4), ("id", 8), ("pid", 7), ("kind", 12), ("app", 20), ("frame", 26), ("title", 0)])]
        for (i, w) in windows.enumerated() {
            let frame = "(\(Int(w.frame.minX)),\(Int(w.frame.minY)) \(Int(w.frame.width))×\(Int(w.frame.height)))"
            let mark = w.id == focusedID ? "*" : ""
            lines.append(columns([("\(i)\(mark)", 4), ("\(w.id)", 8), ("\(w.pid)", 7), (w.kind.rawValue, 12), (w.appName, 20),
                                  (frame, 26), (String(w.title.prefix(60)) + (w.hasAccessibilityElement ? "" : "  [no AX]"), 0)]))
        }
        let counts = Dictionary(grouping: windows, by: \.kind).map { "\($0.value.count) \($0.key.rawValue)" }.sorted()
        lines.append("\(windows.count) windows: \(counts.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    /// Joins columns, padding each to its width. A width of 0 leaves the cell as is.
    public static func columns(_ cells: [(String, Int)]) -> String {
        cells.map { text, width in
            width == 0 ? text : text.count >= width ? String(text.prefix(width - 1)) + " " : text + String(repeating: " ", count: width - text.count)
        }.joined()
    }
}
