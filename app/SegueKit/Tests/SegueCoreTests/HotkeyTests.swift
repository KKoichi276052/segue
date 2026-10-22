import Testing
@testable import SegueCore

@Suite struct HotkeyTests {
    @Test func parses() {
        #expect(HotkeySpec.parse("option+space") == .defaultTap)
        #expect(HotkeySpec.parse("ctrl+opt+S") == HotkeySpec(keyCode: 1, modifiers: [.control, .option]))
        #expect(HotkeySpec.parse("cmd + shift + f5") == HotkeySpec(keyCode: 96, modifiers: [.command, .shift]))
    }

    @Test func rejects() {
        #expect(HotkeySpec.parse("space") == nil, "needs a modifier")
        #expect(HotkeySpec.parse("hyper+space") == nil)
        #expect(HotkeySpec.parse("option+nope") == nil)
    }

    @Test func describes() {
        #expect(HotkeySpec.defaultTap.description == "⌥ Space")
    }
}

@Suite struct ShowTimingsTests {
    @Test func summary() {
        var t = ShowTimings()
        t.record(.tap, ms: 50, first: true)
        t.record(.tap, ms: 12, first: false)
        t.record(.tap, ms: 13, first: false)
        let text = t.summary()
        #expect(text.contains("⌥ Space: n=3"))
        #expect(text.contains("PASS"))
        #expect(text.contains("first shows (launch or display change): 50.0 ms"))
        #expect(text.contains("hold: no samples"))
    }
}
