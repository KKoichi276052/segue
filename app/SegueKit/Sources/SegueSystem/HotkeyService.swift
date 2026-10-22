import Carbon.HIToolbox
import QuartzCore
import SegueCore

/// One global hotkey through Carbon `RegisterEventHotKey` (docs/SPEC.md §9), adapted from
/// spikes/Sources/s6-panel/main.swift. Needs no permission.
///
/// Registration only fails when another app registered the same keys this way; apps that
/// catch keys with event taps can't be detected (§6.1).
@MainActor
public final class HotkeyService {
    public enum Status: Equatable {
        case notRegistered
        case registered(HotkeySpec)
        /// Another app holds it, or the keys are invalid.
        case failed(HotkeySpec, OSStatus)
    }

    /// Called with the key event's time (`CACurrentMediaTime` base) when the hotkey is pressed.
    public var onPress: ((CFTimeInterval) -> Void)?
    public private(set) var status: Status = .notRegistered

    private var ref: EventHotKeyRef?
    private static var shared: HotkeyService?
    private static var handlerInstalled = false

    public init() {}

    @discardableResult
    public func register(_ spec: HotkeySpec) -> Status {
        unregister()
        Self.shared = self
        Self.installHandler()
        var carbon: UInt32 = 0
        if spec.modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if spec.modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if spec.modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if spec.modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        let result = RegisterEventHotKey(spec.keyCode, carbon, EventHotKeyID(signature: 0x5347_5545, id: 1),
                                         GetApplicationEventTarget(), 0, &ref)
        status = result == noErr ? .registered(spec) : .failed(spec, result)
        if result == noErr {
            Log.keys.info("hotkey \(spec.description, privacy: .public) registered")
        } else {
            Log.keys.error("hotkey \(spec.description, privacy: .public) failed to register (\(result)); another app may own it")
        }
        return status
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        status = .notRegistered
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            let time = GetEventTime(event)
            MainActor.assumeIsolated { HotkeyService.shared?.onPress?(time) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
