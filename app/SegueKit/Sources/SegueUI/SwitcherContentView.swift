import AppKit
import QuartzCore
import SegueCore

/// The switcher's content: a black shape that grows out of the notch, with the windows in it.
/// For now a plain list of titles (M1 step 6); the card grid replaces it in step 7.
public final class SwitcherContentView: NSView {
    var onChoose: ((Int) -> Void)?

    private let shape = CAShapeLayer()
    private var rowLayers: [CATextLayer] = []
    private let highlight = CALayer()
    private var rowFrames: [CGRect] = []
    private var model = SwitcherModel()

    private let rowHeight: CGFloat = 26
    private let width: CGFloat = 560
    private let maxRows = 16

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        shape.fillColor = CGColor(gray: 0, alpha: 1)
        layer?.addSublayer(shape)
        highlight.backgroundColor = CGColor(gray: 1, alpha: 0.16)
        highlight.cornerRadius = 6
        layer?.addSublayer(highlight)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Segue window switcher")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    /// Lays out for `model` and returns the panel frame in global coordinates.
    func layout(model: SwitcherModel, screen: CGRect, visible: CGRect, anchor: CGRect, virtualNotch: Bool, scale: CGFloat) -> CGRect {
        self.model = model
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let count = min(model.cards.count, maxRows)
        let first = max(0, min((model.selectedIndex ?? 0) - maxRows / 2, model.cards.count - count))
        let bodyHeight = CGFloat(max(count, 1)) * rowHeight + 24
        let size = CGSize(width: width, height: anchor.height + bodyHeight)
        frame = CGRect(origin: .zero, size: size)

        let path = CGMutablePath()
        let notch = CGRect(x: (width - anchor.width) / 2, y: 0, width: anchor.width, height: anchor.height + 12)
        path.addRoundedRect(in: notch, cornerWidth: 8, cornerHeight: 8)
        path.addRoundedRect(in: CGRect(x: 0, y: anchor.height, width: width, height: bodyHeight), cornerWidth: 22, cornerHeight: 22)
        shape.path = path

        while rowLayers.count < maxRows + 1 {
            let text = CATextLayer()
            text.fontSize = 13
            text.foregroundColor = CGColor(gray: 1, alpha: 1)
            text.truncationMode = .end
            text.isWrapped = false
            layer?.addSublayer(text)
            rowLayers.append(text)
        }
        rowFrames = []
        for (i, text) in rowLayers.enumerated() {
            text.contentsScale = scale
            guard i < count || (i == 0 && model.cards.isEmpty) else {
                text.isHidden = true
                continue
            }
            text.isHidden = false
            let y = anchor.height + 12 + CGFloat(i) * rowHeight
            text.frame = CGRect(x: 24, y: y + 5, width: width - 48, height: rowHeight - 6)
            if model.cards.isEmpty {
                text.string = model.isSearching ? "No matches" : "No windows"
                continue
            }
            let card = model.cards[first + i]
            text.string = "\(card.appName) — \(card.title.isEmpty ? "Untitled" : card.title)" + (card.kind == .onScreen ? "" : "  · \(card.kind.rawValue)")
            rowFrames.append(CGRect(x: 12, y: y, width: width - 24, height: rowHeight))
        }
        if let selected = model.selectedIndex, (first..<first + count).contains(selected) {
            highlight.isHidden = false
            highlight.frame = rowFrames[selected - first]
            if let card = model.selected {
                NSAccessibility.post(element: self, notification: .announcementRequested,
                                     userInfo: [.announcement: "\(card.appName), \(card.title)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
            }
        } else {
            highlight.isHidden = true
        }
        rowOffset = first
        return CGRect(x: anchor.midX - width / 2, y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    private var rowOffset = 0

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let i = rowFrames.firstIndex(where: { $0.contains(point) }) {
            onChoose?(rowOffset + i)
        }
    }
}
