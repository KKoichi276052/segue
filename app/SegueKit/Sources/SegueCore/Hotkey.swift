/// A hotkey written as text, such as "option+space" or "ctrl+opt+s", for `defaults write`.
public struct HotkeySpec: Equatable, Sendable, CustomStringConvertible {
    public enum Modifier: String, CaseIterable, Sendable {
        case control, option, shift, command
    }

    /// A macOS virtual key code (`kVK_*`).
    public var keyCode: UInt32
    public var modifiers: Set<Modifier>

    public init(keyCode: UInt32, modifiers: Set<Modifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultTap = HotkeySpec(keyCode: 49, modifiers: [.option])

    public static func parse(_ text: String) -> HotkeySpec? {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, let code = keyCodes[key] else { return nil }
        var modifiers: Set<Modifier> = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control", "⌃": modifiers.insert(.control)
            case "opt", "option", "alt", "⌥": modifiers.insert(.option)
            case "shift", "⇧": modifiers.insert(.shift)
            case "cmd", "command", "⌘": modifiers.insert(.command)
            default: return nil
            }
        }
        guard !modifiers.isEmpty else { return nil }
        return HotkeySpec(keyCode: code, modifiers: modifiers)
    }

    public var description: String {
        let symbols: [(Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let name = Self.keyCodes.first { $0.value == keyCode }.map { $0.key.count == 1 ? $0.key.uppercased() : $0.key.capitalized } ?? "key \(keyCode)"
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + " " + name
    }

    /// US-layout key codes (Carbon `kVK_*`).
    static let keyCodes: [String: UInt32] = {
        var codes: [String: UInt32] = [
            "space": 49, "tab": 48, "return": 36, "escape": 53, "grave": 50, "`": 50,
            "minus": 27, "equal": 24, "comma": 43, "period": 47, "slash": 44, "semicolon": 41, "quote": 39,
        ]
        let letters: [(String, UInt32)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
            ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("o", 31), ("u", 32),
            ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29),
        ]
        for (name, code) in letters { codes[name] = code }
        let functionKeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in functionKeys.enumerated() { codes["f\(i + 1)"] = code }
        return codes
    }()
}
