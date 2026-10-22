import AppKit
import QuartzCore
import SegueCore

/// The switcher's content (docs/SPEC.md §11 M1 view, Proposed): a black shape that grows out
/// of the notch, holding a grid of window cards, most recently used first. Each card shows
/// the window's picture, or its app icon when there's no picture yet or no Screen Recording,
/// with the title and app name underneath.
public final class SwitcherContentView: NSView {
    var onChoose: ((Int) -> Void)?

    /// Space for the search bar, under the notch. The field itself is added in `searchField`.
    static let searchBarHeight: CGFloat = 40
    private let padding: CGFloat = 20
    private let topGap: CGFloat = 14
    private let footerHeight: CGFloat = 30

    private let shape = CAShapeLayer()
    private let gridLayer = CALayer()
    private let footer = CATextLayer()
    private var cards: [WindowID: CardLayer] = [:]
    private var visibleFrames: [(index: Int, frame: CGRect)] = []
    private var model = SwitcherModel()
    private var announcedID: WindowID?
    private(set) var searchBarFrame: CGRect = .zero
    let searchField = SearchField()
    private let searchBackground = CALayer()
    private let searchIcon = CATextLayer()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        shape.fillColor = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(shape)
        layer?.addSublayer(gridLayer)
        footer.fontSize = 11
        footer.foregroundColor = CGColor(gray: 1, alpha: 0.5)
        footer.alignmentMode = .center
        footer.truncationMode = .end
        layer?.addSublayer(footer)
        searchBackground.backgroundColor = CGColor(gray: 0.16, alpha: 1)
        searchBackground.cornerRadius = 12
        searchBackground.isHidden = true
        layer?.addSublayer(searchBackground)
        searchIcon.string = "⌕"
        searchIcon.fontSize = 18
        searchIcon.foregroundColor = CGColor(gray: 1, alpha: 0.5)
        searchBackground.addSublayer(searchIcon)
        // The field stays in the view, transparent, while the bar is hidden,
        // so it can already have the keyboard when typing starts.
        addSubview(searchField)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Segue window switcher")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    /// Lays out for `model` and returns the panel frame in global coordinates.
    public func layout(model: SwitcherModel, screen: CGRect, visible: CGRect, anchor: CGRect, virtualNotch: Bool, scale: CGFloat) -> CGRect {
        self.model = model
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let searchHeight = model.showsSearchBar ? Self.searchBarHeight + 10 : 0
        let chrome = anchor.height + topGap + searchHeight + footerHeight
        let grid = Self.grid(count: model.cards.count, screen: screen, visible: visible, anchor: anchor, showsSearchBar: model.showsSearchBar)
        let firstRow = grid.firstVisibleRow(selected: model.selectedIndex)

        let width = max(grid.size.width + 2 * padding, anchor.width + 160, 420)
        let gridHeight = model.cards.isEmpty ? 60 : grid.size.height
        let height = chrome + gridHeight
        frame = CGRect(x: 0, y: 0, width: width, height: height)

        // The black shape: the notch (real or virtual) joined to the body by its own width.
        let path = CGMutablePath()
        let notchWidth = anchor.width
        path.addRoundedRect(in: CGRect(x: (width - notchWidth) / 2, y: -1, width: notchWidth, height: anchor.height + 20),
                            cornerWidth: virtualNotch ? 10 : 8, cornerHeight: virtualNotch ? 10 : 8)
        path.addRoundedRect(in: CGRect(x: 0, y: anchor.height, width: width, height: height - anchor.height), cornerWidth: 24, cornerHeight: 24)
        shape.path = path

        searchBarFrame = CGRect(x: padding, y: anchor.height + topGap - 4, width: width - 2 * padding, height: model.showsSearchBar ? Self.searchBarHeight : 0)
        searchBackground.isHidden = !model.showsSearchBar
        searchBackground.frame = searchBarFrame.insetBy(dx: 0, dy: 3)
        searchIcon.contentsScale = scale
        searchIcon.frame = CGRect(x: 12, y: (searchBackground.frame.height - 22) / 2, width: 20, height: 22)
        searchField.alphaValue = model.showsSearchBar ? 1 : 0
        searchField.frame = model.showsSearchBar
            ? CGRect(x: searchBarFrame.minX + 38, y: searchBarFrame.midY - 11, width: searchBarFrame.width - 50, height: 22)
            : CGRect(x: padding, y: anchor.height, width: 200, height: 22)
        let gridOrigin = CGPoint(x: (width - grid.size.width) / 2, y: anchor.height + topGap + searchHeight)
        gridLayer.frame = CGRect(origin: gridOrigin, size: grid.size)

        // Cards: reuse layers by window, hide the ones not in view.
        var used = Set<WindowID>()
        visibleFrames = []
        for (index, card) in model.cards.enumerated() {
            guard let cardFrame = grid.frame(of: index, firstRow: firstRow) else { continue }
            let layer = cards[card.id] ?? {
                let layer = CardLayer()
                cards[card.id] = layer
                gridLayer.addSublayer(layer)
                return layer
            }()
            layer.isHidden = false
            layer.update(card: card, frame: cardFrame, selected: index == model.selectedIndex, scale: scale)
            used.insert(card.id)
            visibleFrames.append((index, cardFrame.offsetBy(dx: gridOrigin.x, dy: gridOrigin.y)))
        }
        for (id, layer) in cards where !used.contains(id) {
            layer.removeFromSuperlayer()
            cards[id] = nil
        }

        var hint = model.hint
        if model.cards.isEmpty { hint = model.isSearching ? "No matching windows" : "No windows" }
        if grid.isPaged {
            let shown = min(model.cards.count, grid.visibleRows * grid.columns)
            hint += "  ·  \(shown) of \(model.cards.count) shown"
        }
        footer.contentsScale = scale
        if footer.string as? String != hint { footer.string = hint }
        footer.frame = model.cards.isEmpty
            ? CGRect(x: padding, y: gridOrigin.y + 20, width: width - 2 * padding, height: 18)
            : CGRect(x: padding, y: height - footerHeight + 7, width: width - 2 * padding, height: 16)

        announceSelection()
        let x = min(max(anchor.midX - width / 2, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }

    /// The grid for `count` cards. The panel hangs from the top of the screen down to just
    /// above the Dock.
    static func grid(count: Int, screen: CGRect, visible: CGRect, anchor: CGRect, showsSearchBar: Bool) -> GridLayout {
        let padding: CGFloat = 20, topGap: CGFloat = 14, footerHeight: CGFloat = 30
        let chrome = anchor.height + topGap + (showsSearchBar ? searchBarHeight + 10 : 0) + footerHeight
        let available = CGSize(width: visible.width - 2 * padding - 80, height: screen.maxY - visible.minY - chrome - 24)
        return GridLayout.compute(count: count, available: CGSize(width: max(available.width, 200), height: max(available.height, 120)))
    }

    private func announceSelection() {
        guard let card = model.selected, card.id != announcedID else { return }
        announcedID = card.id
        let text = "\(card.title.isEmpty ? "Untitled" : card.title), \(card.appName)"
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = visibleFrames.first(where: { $0.frame.contains(point) }) {
            onChoose?(hit.index)
        }
    }
}

/// One window card.
nonisolated private final class CardLayer: CALayer {
    private let selection = CALayer()
    private let picture = CALayer()
    private let bigIcon = CALayer()
    private let smallIcon = CALayer()
    private let title = CATextLayer()
    private let subtitle = CATextLayer()
    private var current: (title: String, subtitle: String, image: CGImage?, icon: NSImage?, selected: Bool, size: CGSize)?

    override init() {
        super.init()
        selection.backgroundColor = CGColor(gray: 1, alpha: 0.14)
        selection.cornerRadius = 12
        selection.isHidden = true
        addSublayer(selection)
        picture.backgroundColor = CGColor(gray: 0.13, alpha: 1)
        picture.cornerRadius = 8
        picture.masksToBounds = true
        picture.contentsGravity = .resizeAspect
        picture.borderColor = CGColor(gray: 1, alpha: 1)
        addSublayer(picture)
        bigIcon.contentsGravity = .resizeAspect
        picture.addSublayer(bigIcon)
        smallIcon.contentsGravity = .resizeAspect
        addSublayer(smallIcon)
        for (text, size, alpha) in [(title, CGFloat(12), CGFloat(1)), (subtitle, CGFloat(10.5), CGFloat(0.55))] {
            text.fontSize = size
            text.font = NSFont.systemFont(ofSize: size, weight: text === title ? .medium : .regular)
            text.foregroundColor = CGColor(gray: 1, alpha: alpha)
            text.truncationMode = .end
            text.isWrapped = false
            addSublayer(text)
        }
    }

    override init(layer: Any) { super.init(layer: layer) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(card: SwitcherModel.Card, frame: CGRect, selected: Bool, scale: CGFloat) {
        self.frame = frame
        let titleText = card.title.isEmpty ? "Untitled" : card.title
        let subtitleText = card.kind == .onScreen ? card.appName : "\(card.appName) · \(card.kind.rawValue)"
        let changed = current.map {
            $0.title != titleText || $0.subtitle != subtitleText || $0.image !== card.image || $0.icon !== card.icon
                || $0.selected != selected || $0.size != frame.size
        } ?? true
        guard changed else { return }
        current = (titleText, subtitleText, card.image, card.icon, selected, frame.size)

        let labelHeight: CGFloat = 38
        let pictureFrame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height - labelHeight)
        selection.frame = bounds.insetBy(dx: -6, dy: -6)
        selection.isHidden = !selected
        picture.frame = pictureFrame
        picture.borderWidth = selected ? 2.5 : 0
        picture.contents = card.image
        picture.backgroundColor = card.image == nil ? CGColor(gray: 0.13, alpha: 1) : CGColor(gray: 0, alpha: 1)
        let iconSide = min(64, pictureFrame.height * 0.45)
        bigIcon.frame = CGRect(x: (pictureFrame.width - iconSide) / 2, y: (pictureFrame.height - iconSide) / 2, width: iconSide, height: iconSide)
        bigIcon.isHidden = card.image != nil
        bigIcon.contents = card.icon
        smallIcon.frame = CGRect(x: 0, y: pictureFrame.maxY + 7, width: 16, height: 16)
        smallIcon.contents = card.icon
        for text in [title, subtitle] { text.contentsScale = scale }
        title.string = titleText
        title.frame = CGRect(x: 21, y: pictureFrame.maxY + 6, width: frame.width - 21, height: 16)
        subtitle.string = subtitleText
        subtitle.frame = CGRect(x: 21, y: pictureFrame.maxY + 22, width: frame.width - 21, height: 14)
    }
}
