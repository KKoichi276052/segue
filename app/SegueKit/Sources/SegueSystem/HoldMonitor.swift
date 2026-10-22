import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SegueCore

/// The hold-mode event tap (docs/SPEC.md §9 `HoldMonitor`), adapted from
/// spikes/Sources/s6-panel/main.swift. It sees key-down and modifier events system-wide,
/// turns them into `KeyInput`, and swallows only what the handler says to: in practice, keys
/// during a hold. Needs Device Control and Data Access (Accessibility).
///
/// The tap runs on the main run loop, so the handler must stay fast: macOS disables a tap
/// whose callback is slow, and it's re-enabled here when that happens.
@MainActor
public final class HoldMonitor {
    /// Returns whether to swallow the key.
    public var onKey: ((KeyInput, _ optionDown: Bool) -> Bool)?
    public var onOptionReleased: (() -> Void)?
    /// When set, logs modifier changes and Tab, arrow, esc and return keys with their raw
    /// fields (keycode, flags, keyboard type, source), to diagnose key remappers such as
    /// kanata. Other keys are logged only as "other" during a hold, never with their code,
    /// so typing is never recorded.
    public var logsRawEvents = false
    /// Passes every event through (the menu's Pause).
    public var paused = false
    /// Whether the switcher currently wants all keys (during a hold), for the raw log.
    public var holding = false

    public private(set) var isInstalled = false
    public private(set) var disabledCount = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var optionDown = false
    private static var shared: HoldMonitor?

    public init() {}

    /// Creates the tap. Returns false without Device Control and Data Access.
    @discardableResult
    public func install() -> Bool {
        guard tap == nil else { return true }
        Self.shared = self
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                let swallow = MainActor.assumeIsolated { HoldMonitor.shared?.handle(type: type, event: event) ?? false }
                return swallow ? nil : Unmanaged.passUnretained(event)
            }, userInfo: nil)
        else {
            Log.keys.error("event tap could not be created (needs Device Control and Data Access)")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isInstalled = true
        Log.keys.info("event tap created")
        return true
    }

    /// Re-enables the tap if macOS turned it off without telling us (after sleep, for
    /// example). Returns whether it was off.
    @discardableResult
    public func ensureEnabled() -> Bool {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        disabledCount += 1
        Log.keys.error("event tap was off; re-enabled")
        return true
    }

    public func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isInstalled = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            disabledCount += 1
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.keys.error("event tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)); re-enabled")
            return false
        }
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        if logsRawEvents { logRaw(type: type, keyCode: keyCode, event: event) }
        guard !paused else { return false }

        let option = flags.contains(.maskAlternate)
        if type == .flagsChanged {
            let wasDown = optionDown
            optionDown = option
            if wasDown && !option { onOptionReleased?() }
            return false
        }
        guard type == .keyDown else { return false }
        optionDown = option
        let input = Self.input(keyCode: keyCode, flags: flags, event: event)
        return onKey?(input, option) ?? false
    }

    static func input(keyCode: Int, flags: CGEventFlags, event: CGEvent) -> KeyInput {
        switch keyCode {
        case kVK_Tab:
            // ⌘ or ⌃ with Tab belongs to other shortcuts (Cmd-Tab, Ctrl-Tab).
            if flags.contains(.maskCommand) || flags.contains(.maskControl) { return .other }
            return .tab(backward: flags.contains(.maskShift))
        case kVK_LeftArrow: return .arrow(.left)
        case kVK_RightArrow: return .arrow(.right)
        case kVK_UpArrow: return .arrow(.up)
        case kVK_DownArrow: return .arrow(.down)
        case kVK_Escape: return .escape
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Space: return .other
        default:
            if flags.contains(.maskCommand) || flags.contains(.maskControl) { return .other }
            // charactersIgnoringModifiers drops ⌥'s effect (⌥ A → "a") but keeps Shift.
            guard let text = NSEvent(cgEvent: event)?.charactersIgnoringModifiers, let scalar = text.unicodeScalars.first,
                  text.unicodeScalars.count == 1, !CharacterSet.controlCharacters.contains(scalar),
                  !(0xF700...0xF8FF).contains(scalar.value) // function keys
            else { return .other }
            return .character(text)
        }
    }

    private func logRaw(type: CGEventType, keyCode: Int, event: CGEvent) {
        let navigation: Set<Int> = [kVK_Tab, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape, kVK_Return]
        let fields = "flags 0x\(String(event.flags.rawValue, radix: 16)) kbType \(event.getIntegerValueField(.keyboardEventKeyboardType)) "
            + "sourceState \(event.getIntegerValueField(.eventSourceStateID)) sourcePID \(event.getIntegerValueField(.eventSourceUnixProcessID)) "
            + "repeat \(event.getIntegerValueField(.keyboardEventAutorepeat)) t \(event.timestamp)"
        if type == .flagsChanged {
            Log.keys.info("raw flagsChanged key \(keyCode) \(fields, privacy: .public)")
        } else if navigation.contains(keyCode) {
            Log.keys.info("raw keyDown key \(keyCode) \(fields, privacy: .public)")
        } else if holding {
            Log.keys.info("raw keyDown other (during hold) \(fields, privacy: .public)")
        }
    }
}
