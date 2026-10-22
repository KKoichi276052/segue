import AppKit

/// A plain window of monospaced text, for the Debug menu's reports.
public final class ReportWindow: NSWindowController {
    private let textView = NSTextView()

    public init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        textView.frame = scroll.bounds
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView
        window.contentView = scroll
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func show(title: String, text: String) {
        window?.title = title
        textView.string = text
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
