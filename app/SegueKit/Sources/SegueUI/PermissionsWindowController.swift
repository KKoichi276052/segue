import AppKit
import SegueCore

/// The small first-launch window (docs/SPEC.md §11, M1 step 2): Device Control and Data
/// Access first, then optional Screen Recording. It checks the status once a second, but
/// only while it's open.
public final class PermissionsWindowController: NSWindowController, NSWindowDelegate {
    public struct Actions {
        public var status: () -> PermissionStatus
        public var request: (PermissionKind) -> Void
        public var openSettings: (PermissionKind) -> Void
        public var relaunch: () -> Void
        public var skipScreenRecording: () -> Void
        public var changed: (PermissionStatus) -> Void

        public init(status: @escaping () -> PermissionStatus, request: @escaping (PermissionKind) -> Void,
                    openSettings: @escaping (PermissionKind) -> Void, relaunch: @escaping () -> Void,
                    skipScreenRecording: @escaping () -> Void, changed: @escaping (PermissionStatus) -> Void) {
            self.status = status
            self.request = request
            self.openSettings = openSettings
            self.relaunch = relaunch
            self.skipScreenRecording = skipScreenRecording
            self.changed = changed
        }
    }

    private let actions: Actions
    private let macOSMajor: Int
    private var rows: [PermissionKind: Row] = [:]
    private var timer: Timer?
    private var lastStatus: PermissionStatus?
    private var requested: Set<PermissionKind> = []

    public init(macOSMajor: Int, actions: Actions) {
        self.actions = actions
        self.macOSMajor = macOSMajor
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Set up Segue"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func present() {
        refresh()
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func buildContent() {
        let title = NSTextField(labelWithString: "Segue needs one permission, and one more is recommended.")
        title.font = .boldSystemFont(ofSize: 13)
        let stack = NSStackView(views: [title])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for kind in PermissionKind.allCases {
            let row = Row(kind: kind, macOSMajor: macOSMajor, owner: self)
            rows[kind] = row
            stack.addArrangedSubview(row.view)
        }
        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        done.keyEquivalent = "\r"
        stack.addArrangedSubview(done)
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
        window?.contentView = stack
    }

    @objc private func closeWindow() { window?.close() }

    fileprivate func primary(_ kind: PermissionKind) {
        if requested.contains(kind) {
            actions.openSettings(kind)
        } else {
            requested.insert(kind)
            actions.request(kind)
        }
        refresh()
    }

    fileprivate func secondary(_ kind: PermissionKind) {
        switch kind {
        case .control: actions.relaunch()
        case .screenRecording:
            if requested.contains(.screenRecording) {
                actions.relaunch()
            } else {
                actions.skipScreenRecording()
                window?.close()
            }
        }
    }

    private func refresh() {
        let status = actions.status()
        if status != lastStatus {
            lastStatus = status
            actions.changed(status)
        }
        rows[.control]?.update(granted: status.accessibility, requested: requested.contains(.control), enabled: true)
        rows[.screenRecording]?.update(granted: status.screenRecording, requested: requested.contains(.screenRecording),
                                       enabled: status.accessibility)
    }

    @MainActor
    private final class Row {
        let kind: PermissionKind
        let view: NSStackView
        private let state = NSTextField(labelWithString: "")
        private let primaryButton: NSButton
        private let secondaryButton: NSButton
        private let hint = NSTextField(wrappingLabelWithString: "")

        init(kind: PermissionKind, macOSMajor: Int, owner: PermissionsWindowController) {
            self.kind = kind
            let name = NSTextField(labelWithString: kind.paneName(macOSMajor: macOSMajor)
                                   + (kind == .control ? " (required)" : " (optional)"))
            name.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            let purpose = NSTextField(wrappingLabelWithString: kind.purpose)
            purpose.preferredMaxLayoutWidth = 440
            hint.preferredMaxLayoutWidth = 440
            hint.textColor = .secondaryLabelColor
            hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            primaryButton = NSButton(title: "Allow…", target: nil, action: nil)
            secondaryButton = NSButton(title: "", target: nil, action: nil)
            let header = NSStackView(views: [name, state])
            let buttons = NSStackView(views: [primaryButton, secondaryButton])
            view = NSStackView(views: [header, purpose, buttons, hint])
            view.orientation = .vertical
            view.alignment = .leading
            view.spacing = 6
            primaryButton.target = self
            primaryButton.action = #selector(primaryPressed)
            secondaryButton.target = self
            secondaryButton.action = #selector(secondaryPressed)
            self.owner = owner
        }

        private weak var owner: PermissionsWindowController?

        @objc private func primaryPressed() { owner?.primary(kind) }
        @objc private func secondaryPressed() { owner?.secondary(kind) }

        func update(granted: Bool, requested: Bool, enabled: Bool) {
            state.stringValue = granted ? "✓ Granted" : "Not granted"
            state.textColor = granted ? .systemGreen : .secondaryLabelColor
            primaryButton.isHidden = granted
            primaryButton.isEnabled = enabled
            primaryButton.title = requested ? "Open System Settings" : "Allow…"
            switch kind {
            case .control:
                secondaryButton.title = "Relaunch Segue"
                secondaryButton.isHidden = granted || !requested
                hint.stringValue = granted || !requested ? "" : "Turn Segue on in System Settings. If it stays “Not granted” after that, relaunch."
            case .screenRecording:
                secondaryButton.title = requested ? "Relaunch Segue" : "Skip"
                secondaryButton.isHidden = granted
                secondaryButton.isEnabled = enabled
                hint.stringValue = granted || !requested ? "" : "macOS applies Screen Recording when Segue starts, so relaunch after turning it on."
            }
            hint.isHidden = hint.stringValue.isEmpty
        }
    }
}
