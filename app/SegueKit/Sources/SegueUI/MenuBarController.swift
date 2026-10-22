import AppKit
import SegueCore

/// The menu bar item: Segue's only permanent UI (it has no Dock icon).
public final class MenuBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    public override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Segue")
        item.menu = menu
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        menu.addItem(withTitle: "Segue \(SegueVersion.string)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Segue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}
