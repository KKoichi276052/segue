/// A key, as the switcher sees it.
public enum KeyInput: Equatable, Sendable {
    case tab(backward: Bool)
    case arrow(Direction)
    case escape
    case enter
    /// A printable character, without the effect of ⌥ (so ⌥ A is "a").
    case character(String)
    /// Anything else, including Space.
    case other
}

public enum Direction: Sendable {
    case left, right, up, down
}

/// Where a key came from. During a hold the event tap delivers every key. While the switcher
/// is open its search field has the keyboard, so input methods work, and the panel forwards
/// navigation keys.
public enum InputSource: Sendable {
    case eventTap
    case panel
}

/// What the app should do after a state change. Applied in order.
public enum SwitcherEffect: Equatable, Sendable {
    case scheduleShow(afterMs: Int)
    case cancelScheduledShow
    case show
    case hide
    case focus(WindowID)
    /// Give the search field the keyboard, starting with this text.
    case beginSearch(String)
    /// Text typed while ⌥ is still held after a search started; add it to the field.
    case appendSearch(String)
    /// The query changed; the app ranks the windows and calls `setResults`.
    case search(String)
    case clearSearch
    case selectionChanged
}

/// The hold, tap and search state machine (docs/SPEC.md §6.1, §6.5, §11 M1 plan).
///
/// - Hold: ⌥ Tab starts it, Tab and ⇧ Tab move, arrows move, esc cancels, releasing ⌥
///   switches. Released before the show delay, it switches to the previous window without
///   showing anything.
/// - Tap: ⌥ Space opens the switcher and keeps it open. return switches; esc clears the
///   search, then closes.
/// - Typing a letter during a hold starts a search and keeps the switcher open.
public struct SwitcherState: Sendable {
    public enum Phase: Equatable, Sendable {
        case hidden
        /// Holding, before the show delay has passed: nothing is on screen yet.
        case holdPending
        case holding
        /// Open until return, a click, esc or ⌥ Space.
        case open
    }

    public private(set) var phase: Phase = .hidden
    /// The windows on show, most recently used first, or search results in rank order.
    public private(set) var items: [WindowID] = []
    public private(set) var selectedIndex: Int?
    public private(set) var query = ""
    /// Columns in the view's grid, for ▲ ▼.
    public var columns = 1
    public var showDelayMs: Int

    private var windows: [WindowID] = []
    private var focusedID: WindowID?
    /// A search started during a hold, and ⌥ is still down.
    private var latchedWithOption = false

    public init(showDelayMs: Int = 100) {
        self.showDelayMs = showDelayMs
    }

    public var selectedID: WindowID? { selectedIndex.map { items[$0] } }
    public var isVisible: Bool { phase == .holding || phase == .open }
    public var isSearching: Bool { phase == .open && !query.isEmpty }

    // MARK: Windows

    /// The current windows, most recently used first. Keeps the selection on the same window.
    public mutating func updateWindows(_ ids: [WindowID], focusedID: WindowID?) -> [SwitcherEffect] {
        windows = ids
        self.focusedID = focusedID
        guard phase != .hidden else { return [] }
        if isSearching { return [.search(query)] }
        return setItems(ids, keepSelection: true)
    }

    /// Search results for the current query, best first. Selects the best.
    public mutating func setResults(_ ids: [WindowID]) -> [SwitcherEffect] {
        items = ids
        selectedIndex = ids.isEmpty ? nil : 0
        return [.selectionChanged]
    }

    private mutating func setItems(_ ids: [WindowID], keepSelection: Bool) -> [SwitcherEffect] {
        let previous = selectedID
        items = ids
        if keepSelection, let previous, let i = ids.firstIndex(of: previous) {
            selectedIndex = i
        } else if let index = selectedIndex, !ids.isEmpty {
            selectedIndex = min(index, ids.count - 1)
        } else {
            selectedIndex = ids.isEmpty ? nil : 0
        }
        return [.selectionChanged]
    }

    /// The first selection: the previous window, so a quick ⌥ Tab switches back.
    private func startIndex(backward: Bool) -> Int? {
        guard !windows.isEmpty else { return nil }
        if backward { return windows.count - 1 }
        return windows.first == focusedID && windows.count > 1 ? 1 : 0
    }

    private mutating func open(backward: Bool) {
        items = windows
        query = ""
        selectedIndex = startIndex(backward: backward)
    }

    // MARK: Keys

    /// Handles a key. Returns whether to swallow it (only meaningful from the event tap).
    public mutating func handle(_ input: KeyInput, optionDown: Bool, from source: InputSource) -> (swallow: Bool, effects: [SwitcherEffect]) {
        switch phase {
        case .hidden:
            guard source == .eventTap, case .tab(let backward) = input, optionDown else { return (false, []) }
            open(backward: backward)
            if showDelayMs <= 0 {
                phase = .holding
                return (true, [.show, .selectionChanged])
            }
            phase = .holdPending
            return (true, [.scheduleShow(afterMs: showDelayMs), .selectionChanged])

        case .holdPending, .holding:
            let pending = phase == .holdPending
            switch input {
            case .tab(let backward):
                return (true, move(backward ? -1 : 1, wrap: true))
            case .arrow(let direction):
                var effects = move(direction)
                if pending {
                    phase = .holding
                    effects = [.cancelScheduledShow, .show] + effects
                }
                return (true, effects)
            case .escape:
                phase = .hidden
                return (true, pending ? [.cancelScheduledShow] : [.hide])
            case .enter:
                return (true, finish())
            case .character(let text):
                phase = .open
                latchedWithOption = optionDown
                query = text
                return (true, (pending ? [.cancelScheduledShow, .show] : []) + [.beginSearch(text), .search(text)])
            case .other:
                return (true, [])
            }

        case .open:
            switch (input, source) {
            case (.tab(let backward), .eventTap) where optionDown:
                return (true, move(backward ? -1 : 1, wrap: true))
            case (.character(let text), .eventTap) where optionDown && latchedWithOption:
                return (true, [.appendSearch(text)])
            case (_, .eventTap):
                return (false, [])
            case (.tab(let backward), .panel):
                return (true, move(backward ? -1 : 1, wrap: true))
            case (.arrow(let direction), .panel):
                return (true, move(direction))
            case (.escape, .panel):
                if !query.isEmpty {
                    query = ""
                    items = windows
                    selectedIndex = startIndex(backward: false)
                    return (true, [.clearSearch, .selectionChanged])
                }
                return (true, close())
            case (.enter, .panel):
                return (true, finish())
            case (.character, .panel), (.other, .panel):
                return (false, [])
            }
        }
    }

    /// ⌥ was released.
    public mutating func optionReleased() -> [SwitcherEffect] {
        switch phase {
        case .holdPending:
            phase = .hidden
            return [.cancelScheduledShow] + focusSelected()
        case .holding:
            return finish()
        case .open:
            latchedWithOption = false
            return []
        case .hidden:
            return []
        }
    }

    /// The show delay passed while ⌥ is still held.
    public mutating func showDelayElapsed() -> [SwitcherEffect] {
        guard phase == .holdPending else { return [] }
        phase = .holding
        return [.show]
    }

    /// ⌥ Space.
    public mutating func toggleTap() -> [SwitcherEffect] {
        switch phase {
        case .hidden:
            open(backward: false)
            phase = .open
            return [.show, .selectionChanged]
        case .holdPending:
            phase = .open
            return [.cancelScheduledShow, .show]
        case .holding:
            phase = .open
            return []
        case .open:
            return close()
        }
    }

    /// The search field's text changed.
    public mutating func queryChanged(_ text: String) -> [SwitcherEffect] {
        guard phase == .open, text != query else { return [] }
        query = text
        if text.isEmpty {
            items = windows
            selectedIndex = startIndex(backward: false)
            return [.selectionChanged]
        }
        return [.search(text)]
    }

    /// A card was clicked.
    public mutating func choose(_ id: WindowID) -> [SwitcherEffect] {
        guard phase != .hidden else { return [] }
        phase = .hidden
        return [.hide, .focus(id)]
    }

    /// Closes without switching: a click outside, a display change.
    public mutating func dismiss() -> [SwitcherEffect] {
        close()
    }

    // MARK: Helpers

    private mutating func close() -> [SwitcherEffect] {
        let was = phase
        phase = .hidden
        query = ""
        latchedWithOption = false
        switch was {
        case .hidden: return []
        case .holdPending: return [.cancelScheduledShow]
        default: return [.hide]
        }
    }

    private mutating func finish() -> [SwitcherEffect] {
        let effects = close()
        return effects + focusSelected()
    }

    private func focusSelected() -> [SwitcherEffect] {
        selectedID.map { [.focus($0)] } ?? []
    }

    private mutating func move(_ step: Int, wrap: Bool) -> [SwitcherEffect] {
        guard !items.isEmpty else { return [] }
        let current = selectedIndex ?? 0
        let next = wrap ? ((current + step) % items.count + items.count) % items.count
            : max(0, min(items.count - 1, current + step))
        selectedIndex = next
        return [.selectionChanged]
    }

    private mutating func move(_ direction: Direction) -> [SwitcherEffect] {
        switch direction {
        case .left: return move(-1, wrap: true)
        case .right: return move(1, wrap: true)
        case .up, .down:
            guard let current = selectedIndex else { return [] }
            let next = current + (direction == .down ? columns : -columns)
            guard items.indices.contains(next) else { return [] }
            selectedIndex = next
            return [.selectionChanged]
        }
    }
}
