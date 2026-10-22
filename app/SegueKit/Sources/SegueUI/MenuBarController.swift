import AppKit
import SegueCore

/// What the menu bar item shows. The app fills it in from the services' state.
public struct MenuState: Equatable {
    public var warnings: [String] = []
    public var notes: [String] = []
    public var paused = false

    public init() {}
}

/// The menu bar item: Segue's only permanent UI (it has no Dock icon).
public final class MenuBarController: NSObject, NSMenuDelegate {
    public struct Item {
        public var title: String
        public var checked: Bool
        public var action: () -> Void

        public init(_ title: String, checked: Bool = false, action: @escaping () -> Void) {
            self.title = title
            self.checked = checked
            self.action = action
        }
    }

    /// Called just before the menu opens, so the app can refresh its state.
    public var willOpen: () -> Void = {}
    public var mainItems: () -> [Item] = { [] }
    public var debugItems: () -> [Item] = { [] }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var state = MenuState()
    private var actions: [() -> Void] = []

    public override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    public func update(_ state: MenuState) {
        guard state != self.state else { return }
        self.state = state
        updateIcon()
    }

    private func updateIcon() {
        let name = state.paused ? "pause.rectangle" : state.warnings.isEmpty ? "rectangle.on.rectangle" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Segue")
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        willOpen()
        menu.removeAllItems()
        actions.removeAll()
        menu.addItem(withTitle: "Segue \(SegueVersion.string)", action: nil, keyEquivalent: "")
        for line in state.warnings { menu.addItem(withTitle: "⚠︎ \(line)", action: nil, keyEquivalent: "") }
        for line in state.notes { menu.addItem(withTitle: line, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        for item in mainItems() { menu.addItem(menuItem(item)) }
        let debug = debugItems()
        if !debug.isEmpty {
            let sub = NSMenu()
            for item in debug { sub.addItem(menuItem(item)) }
            let parent = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
            parent.submenu = sub
            menu.addItem(parent)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Segue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func menuItem(_ item: Item) -> NSMenuItem {
        let menuItem = NSMenuItem(title: item.title, action: #selector(run(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.tag = actions.count
        menuItem.state = item.checked ? .on : .off
        actions.append(item.action)
        return menuItem
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}
