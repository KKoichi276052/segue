import CoreGraphics

/// Sizes the switcher's grid of window cards (docs/SPEC.md §11 M1 view, Proposed): all
/// windows at once when they fit, cards as large as possible within limits, and otherwise
/// a window of rows that keeps the selection visible.
public struct GridLayout: Equatable, Sendable {
    public struct Metrics: Equatable, Sendable {
        public var minCardWidth: CGFloat = 150
        public var maxCardWidth: CGFloat = 300
        /// Width over height of the picture part of a card.
        public var imageAspect: CGFloat = 16.0 / 10.0
        /// Height of the title and app name under the picture.
        public var labelHeight: CGFloat = 38
        public var spacing: CGFloat = 14

        public init() {}

        public func cardHeight(forWidth width: CGFloat) -> CGFloat {
            (width / imageAspect).rounded() + labelHeight
        }
    }

    public var columns: Int
    public var cardSize: CGSize
    /// Rows that fit; fewer than `totalRows` when the grid pages.
    public var visibleRows: Int
    public var totalRows: Int
    public var spacing: CGFloat

    public var isPaged: Bool { visibleRows < totalRows }

    /// The size of the visible grid.
    public var size: CGSize {
        let rows = max(1, min(visibleRows, totalRows))
        return CGSize(width: CGFloat(columns) * cardSize.width + CGFloat(columns - 1) * spacing,
                      height: CGFloat(rows) * cardSize.height + CGFloat(rows - 1) * spacing)
    }

    public static func compute(count: Int, available: CGSize, metrics: Metrics = Metrics()) -> GridLayout {
        let n = max(count, 1)
        var best: GridLayout?
        for columns in 1...n {
            let rows = (n + columns - 1) / columns
            let width = min(metrics.maxCardWidth, ((available.width - CGFloat(columns - 1) * metrics.spacing) / CGFloat(columns)).rounded(.down))
            guard width >= metrics.minCardWidth else { break }
            let height = metrics.cardHeight(forWidth: width)
            let total = CGFloat(rows) * height + CGFloat(rows - 1) * metrics.spacing
            guard total <= available.height else { continue }
            let candidate = GridLayout(columns: columns, cardSize: CGSize(width: width, height: height), visibleRows: rows,
                                       totalRows: rows, spacing: metrics.spacing)
            // Prefer bigger cards; at equal size, fewer rows, which suits a landscape screen.
            if best == nil || width >= best!.cardSize.width { best = candidate }
        }
        if let best { return best }

        // Doesn't fit: smallest cards, as many columns as fit, and page by rows.
        let width = metrics.minCardWidth
        let height = metrics.cardHeight(forWidth: width)
        let columns = max(1, min(n, Int((available.width + metrics.spacing) / (width + metrics.spacing))))
        let rows = (n + columns - 1) / columns
        let visible = max(1, Int((available.height + metrics.spacing) / (height + metrics.spacing)))
        return GridLayout(columns: columns, cardSize: CGSize(width: width, height: height), visibleRows: min(visible, rows),
                          totalRows: rows, spacing: metrics.spacing)
    }

    /// The first visible row, so that the selected index is in view, roughly centered.
    public func firstVisibleRow(selected: Int?) -> Int {
        guard isPaged, let selected else { return 0 }
        let row = selected / columns
        return max(0, min(totalRows - visibleRows, row - visibleRows / 2))
    }

    /// The card's frame within the grid's visible area (top-left origin), or nil if it's
    /// outside the visible rows.
    public func frame(of index: Int, firstRow: Int) -> CGRect? {
        let row = index / columns - firstRow
        guard row >= 0, row < visibleRows else { return nil }
        let column = index % columns
        return CGRect(x: CGFloat(column) * (cardSize.width + spacing), y: CGFloat(row) * (cardSize.height + spacing),
                      width: cardSize.width, height: cardSize.height)
    }
}
