import AppKit
import SegueCore

/// The search bar under the notch (docs/SPEC.md §6.5). A real text field, so input methods
/// such as Japanese work. Navigation keys go to the switcher, except while an input method is
/// composing, when they belong to it (choosing a conversion, confirming with return).
final class SearchField: NSTextField, NSTextFieldDelegate {
    var onTextChange: ((String) -> Void)?
    var onCommand: ((KeyInput) -> Void)?

    private let background = NSView()

    init() {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 16)
        textColor = .white
        placeholderAttributedString = NSAttributedString(string: "Search windows", attributes: [
            .foregroundColor: NSColor(white: 1, alpha: 0.35), .font: NSFont.systemFont(ofSize: 16),
        ])
        cell?.usesSingleLineMode = true
        cell?.lineBreakMode = .byTruncatingTail
        delegate = self
        setAccessibilityLabel("Search windows")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func controlTextDidChange(_ obj: Notification) {
        onTextChange?(currentText)
    }

    /// The text including any part still being composed by an input method.
    var currentText: String {
        (currentEditor() as? NSTextView)?.string ?? stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        let input: KeyInput? = switch selector {
        case #selector(NSResponder.moveLeft(_:)): .arrow(.left)
        case #selector(NSResponder.moveRight(_:)): .arrow(.right)
        case #selector(NSResponder.moveUp(_:)): .arrow(.up)
        case #selector(NSResponder.moveDown(_:)): .arrow(.down)
        case #selector(NSResponder.insertTab(_:)): .tab(backward: false)
        case #selector(NSResponder.insertBacktab(_:)): .tab(backward: true)
        case #selector(NSResponder.cancelOperation(_:)): .escape
        case #selector(NSResponder.insertNewline(_:)): .enter
        default: nil
        }
        guard let input else { return false }
        onCommand?(input)
        return true
    }

    /// Sets the text and puts the cursor at the end.
    func setText(_ text: String) {
        stringValue = text
        if let editor = currentEditor() {
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
    }
}
