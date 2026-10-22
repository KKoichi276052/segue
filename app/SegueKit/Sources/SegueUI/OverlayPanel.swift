import AppKit
import QuartzCore
import SegueCore

/// The non-activating panel above the menu bar, on every Space and over full-screen apps
/// (docs/SPEC.md §9 `OverlayPanel`), set up as in spikes/Sources/s6-panel/main.swift.
public final class OverlayPanel: NSPanel {
    public init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false
        becomesKeyOnlyIfNeeded = true
    }

    /// The search field needs the keyboard; the panel takes it without activating Segue.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

/// Shows and hides the switcher, and times how long a show takes to reach the screen.
public final class SwitcherWindowController {
    public enum ShowKind {
        case tap, hold
    }

    /// Called with the time from the triggering event to the first display frame after the
    /// panel was committed, in milliseconds. That estimates when the panel is on screen.
    public var onFirstFrame: ((ShowKind, Double) -> Void)?
    public var onChoose: ((Int) -> Void)?
    public var onClickOutside: (() -> Void)?
    /// The search text changed (including text an input method is still composing).
    public var onSearchTextChange: ((String) -> Void)?
    /// A navigation key in the search field: arrows, Tab, esc, return.
    public var onSearchCommand: ((KeyInput) -> Void)?

    /// Keep the panel on screen while hidden, transparent and ignoring the mouse, so a show
    /// never pays for ordering it in (the fallback if pre-warming isn't enough, §15).
    public var keepsPanelOnScreen = false {
        didSet { if !isShowing { keepsPanelOnScreen ? park() : panel.orderOut(nil) } }
    }

    public let panel = OverlayPanel()
    public private(set) var isShowing = false
    private let content = SwitcherContentView()
    private var link: CADisplayLink?
    private var pending: (kind: ShowKind, eventTime: CFTimeInterval)?
    private var outsideMonitor: Any?
    private var currentScreen: NSScreen?

    public init() {
        panel.contentView = content
        content.onChoose = { [weak self] in self?.onChoose?($0) }
        content.searchField.onTextChange = { [weak self] in self?.onSearchTextChange?($0) }
        content.searchField.onCommand = { [weak self] in self?.onSearchCommand?($0) }
    }

    public var contentView: SwitcherContentView { content }

    /// Draws once, invisibly, on `screen`, so the first real show doesn't pay for creating
    /// the window's backing store and the first render (S6: 44–66 ms otherwise).
    public func prewarm(on screen: NSScreen, sample: SwitcherModel) {
        guard !isShowing else { return }
        layout(on: screen, model: sample)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
        CATransaction.flush()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            guard !isShowing else { return }
            keepsPanelOnScreen ? park() : panel.orderOut(nil)
        }
    }

    public func show(_ model: SwitcherModel, on screen: NSScreen, kind: ShowKind, eventTime: CFTimeInterval, reduceMotion: Bool) {
        let signpost = Log.signposter.beginInterval("show")
        defer { Log.signposter.endInterval("show", signpost) }
        if isShowing {
            update(model)
            return
        }
        isShowing = true
        layout(on: screen, model: model)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        // Fade in over about 100 ms, so a release just after the show delay doesn't read
        // as a flash (§6.1). Hiding is instant.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : 0.1
            panel.animator().alphaValue = 1
        }
        CATransaction.flush()
        pending = (kind, eventTime)
        link = content.displayLink(target: self, selector: #selector(frame(_:)))
        link?.add(to: .main, forMode: .common)
        installOutsideMonitor()
    }

    /// Gives the search field the keyboard without activating Segue: the app in front stays
    /// in front. Optionally starts it with some text.
    public func takeKeyboard(text: String? = nil) {
        guard isShowing else { return }
        panel.makeKey()
        if panel.firstResponder !== content.searchField.currentEditor() {
            panel.makeFirstResponder(content.searchField)
        }
        if let text { content.searchField.setText(text) }
    }

    /// Adds text typed while ⌥ is still held (the field doesn't see those keys).
    public func appendSearchText(_ text: String) {
        content.searchField.setText(content.searchField.currentText + text)
        onSearchTextChange?(content.searchField.currentText)
    }

    public func clearSearchText() {
        content.searchField.setText("")
    }

    public func update(_ model: SwitcherModel) {
        guard isShowing, let screen = currentScreen else { return }
        layout(on: screen, model: model)
    }

    public func hide() {
        guard isShowing else { return }
        isShowing = false
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        content.searchField.setText("")
        panel.makeFirstResponder(nil)
        if panel.isKeyWindow { panel.resignKey() }
        stopFade()
        keepsPanelOnScreen ? park() : panel.orderOut(nil)
    }

    /// Ends a fade-in still running, so it can't make a hidden or parked panel visible again.
    private func stopFade() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 0
        }
    }

    /// Renders the switcher's layers offscreen, for checking layout without showing the panel
    /// or capturing the screen.
    public func renderImage(_ model: SwitcherModel, on screen: NSScreen) -> CGImage? {
        let anchor = NotchGeometry.anchor(on: screen)
        let view = SwitcherContentView()
        let frame = view.layout(model: model, screen: screen.frame, visible: screen.visibleFrame, anchor: anchor.rect,
                                virtualNotch: anchor.isVirtual, scale: screen.backingScaleFactor)
        view.searchField.stringValue = model.query
        view.layoutSubtreeIfNeeded()
        view.display()
        guard let layer = view.layer else { return nil }
        let scale = screen.backingScaleFactor
        let width = Int(frame.width * scale), height = Int(frame.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The view is flipped: draw with the origin at the top left.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)
        return context.makeImage()
    }

    private func park() {
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
    }

    private func layout(on screen: NSScreen, model: SwitcherModel) {
        currentScreen = screen
        let anchor = NotchGeometry.anchor(on: screen)
        let frame = content.layout(model: model, screen: screen.frame, visible: screen.visibleFrame, anchor: anchor.rect,
                                   virtualNotch: anchor.isVirtual, scale: screen.backingScaleFactor)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    @objc private func frame(_ link: CADisplayLink) {
        link.invalidate()
        self.link = nil
        guard let pending else { return }
        self.pending = nil
        onFirstFrame?(pending.kind, (link.targetTimestamp - pending.eventTime) * 1000)
    }

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClickOutside?() }
        }
    }
}
