import Testing
@testable import SegueCore

@Suite struct SwitcherStateTests {
    /// Windows 1–4, most recent first; 1 is focused.
    func state(delay: Int = 100) -> SwitcherState {
        var s = SwitcherState(showDelayMs: delay)
        _ = s.updateWindows([1, 2, 3, 4], focusedID: 1)
        return s
    }

    @Test func quickTapSwitchesToPreviousWithoutShowing() {
        var s = state()
        let start = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(start.swallow)
        #expect(start.effects.contains(.scheduleShow(afterMs: 100)))
        #expect(s.phase == .holdPending)
        #expect(s.selectedID == 2)
        let release = s.optionReleased()
        #expect(release == [.cancelScheduledShow, .focus(2)])
        #expect(!release.contains(.show))
        #expect(s.phase == .hidden)
    }

    @Test func holdShowsAfterDelayAndSwitchesOnRelease() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(s.showDelayElapsed() == [.show])
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 3)
        #expect(s.optionReleased() == [.hide, .focus(3)])
    }

    @Test func shiftTabGoesBackAndWraps() {
        var s = state()
        _ = s.handle(.tab(backward: true), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 4)
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 1)
        _ = s.handle(.tab(backward: true), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 4)
    }

    @Test func tabWithoutOptionIsNotOurs() {
        var s = state()
        let r = s.handle(.tab(backward: false), optionDown: false, from: .eventTap)
        #expect(!r.swallow)
        #expect(r.effects.isEmpty)
        #expect(s.handle(.character("a"), optionDown: true, from: .eventTap).swallow == false)
    }

    @Test func arrowsMoveAndShowAtOnce() {
        var s = state()
        s.columns = 2
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        let r = s.handle(.arrow(.down), optionDown: true, from: .eventTap)
        #expect(r.effects.prefix(2) == [.cancelScheduledShow, .show])
        #expect(s.phase == .holding)
        #expect(s.selectedID == 4)
        _ = s.handle(.arrow(.down), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 4, "▼ past the last row stays put")
        _ = s.handle(.arrow(.right), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 1, "◀ ▶ wrap")
    }

    @Test func escapeCancelsWithoutSwitching() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        _ = s.showDelayElapsed()
        #expect(s.handle(.escape, optionDown: true, from: .eventTap).effects == [.hide])
        #expect(s.optionReleased().isEmpty)
    }

    @Test func otherKeysAreSwallowedDuringAHold() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        let r = s.handle(.other, optionDown: true, from: .eventTap)
        #expect(r.swallow)
        #expect(r.effects.isEmpty)
    }

    @Test func letterDuringHoldStartsSearchAndStaysOpen() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        let r = s.handle(.character("s"), optionDown: true, from: .eventTap)
        #expect(r.swallow)
        #expect(r.effects == [.cancelScheduledShow, .show, .takeKeyboard, .beginSearch("s"), .search("s")])
        #expect(s.phase == .open)
        // Still holding ⌥: later letters are added through the tap.
        #expect(s.handle(.character("a"), optionDown: true, from: .eventTap).effects == [.appendSearch("a")])
        #expect(s.optionReleased().isEmpty)
        #expect(s.phase == .open)
        // Released: typing goes to the field, not the tap.
        #expect(s.handle(.character("f"), optionDown: false, from: .eventTap).swallow == false)
        #expect(s.handle(.character("f"), optionDown: true, from: .eventTap).swallow == false)
    }

    @Test func tapModeOpensAndStaysOpen() {
        var s = state()
        #expect(s.toggleTap() == [.show, .takeKeyboard, .selectionChanged])
        #expect(s.phase == .open)
        #expect(s.selectedID == 2)
        #expect(s.optionReleased().isEmpty)
        _ = s.handle(.arrow(.right), optionDown: false, from: .panel)
        #expect(s.selectedID == 3)
        #expect(s.handle(.enter, optionDown: false, from: .panel).effects == [.hide, .focus(3)])
        #expect(s.phase == .hidden)
    }

    @Test func tapHotkeyAgainCloses() {
        var s = state()
        _ = s.toggleTap()
        #expect(s.toggleTap() == [.hide])
    }

    @Test func tapHotkeyDuringHoldKeepsItOpen() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(s.toggleTap() == [.cancelScheduledShow, .show, .takeKeyboard])
        #expect(s.optionReleased().isEmpty)
        #expect(s.phase == .open)
    }

    @Test func searchResultsAndEscape() {
        var s = state()
        _ = s.toggleTap()
        #expect(s.queryChanged("ter") == [.search("ter")])
        _ = s.setResults([4, 2])
        #expect(s.items == [4, 2])
        #expect(s.selectedID == 4)
        // First esc clears the search, second closes.
        #expect(s.handle(.escape, optionDown: false, from: .panel).effects == [.clearSearch, .selectionChanged])
        #expect(s.items == [1, 2, 3, 4])
        #expect(s.selectedID == 2)
        #expect(s.handle(.escape, optionDown: false, from: .panel).effects == [.hide])
    }

    @Test func clearingTheFieldRestoresTheList() {
        var s = state()
        _ = s.toggleTap()
        _ = s.queryChanged("x")
        _ = s.setResults([])
        #expect(s.selectedID == nil)
        #expect(s.handle(.enter, optionDown: false, from: .panel).effects == [.hide])
        _ = s.toggleTap()
        _ = s.queryChanged("x")
        #expect(s.queryChanged("") == [.selectionChanged])
        #expect(s.items == [1, 2, 3, 4])
    }

    @Test func windowChangesKeepTheSelectedWindow() {
        var s = state()
        _ = s.toggleTap()
        _ = s.handle(.arrow(.right), optionDown: false, from: .panel)
        #expect(s.selectedID == 3)
        _ = s.updateWindows([5, 1, 3, 4], focusedID: 5)
        #expect(s.selectedID == 3)
        _ = s.updateWindows([5, 1], focusedID: 5)
        #expect(s.selectedID == 1, "the selected window closed: clamp")
    }

    @Test func windowChangesWhileSearchingRerank() {
        var s = state()
        _ = s.toggleTap()
        _ = s.queryChanged("a")
        #expect(s.updateWindows([1, 2], focusedID: 1) == [.search("a")])
    }

    @Test func noDelayShowsAtOnce() {
        var s = state(delay: 0)
        #expect(s.handle(.tab(backward: false), optionDown: true, from: .eventTap).effects == [.show, .selectionChanged])
        #expect(s.phase == .holding)
    }

    @Test func noWindows() {
        var s = SwitcherState()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(s.selectedID == nil)
        #expect(s.optionReleased() == [.cancelScheduledShow])
    }

    @Test func frontmostAppWithoutWindowsSelectsTheMostRecent() {
        var s = SwitcherState()
        _ = s.updateWindows([1, 2], focusedID: nil)
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        #expect(s.selectedID == 1)
    }

    @Test func tapHotkeyAfterTheDelayTakesTheKeyboard() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        _ = s.showDelayElapsed()
        #expect(s.toggleTap() == [.takeKeyboard])
    }

    @Test func reRankingKeepsTheSelectionButANewQuerySelectsTheBest() {
        var s = state()
        _ = s.toggleTap()
        _ = s.queryChanged("a")
        _ = s.setResults([3, 2, 4])
        _ = s.handle(.arrow(.right), optionDown: false, from: .panel)
        #expect(s.selectedID == 2)
        // A window changed: same query, results re-ranked.
        #expect(s.updateWindows([1, 2, 3, 4, 5], focusedID: 1) == [.search("a")])
        _ = s.setResults([5, 3, 2, 4])
        #expect(s.selectedID == 2)
        // The owner typed more: the best match is selected.
        _ = s.queryChanged("ab")
        _ = s.setResults([4, 2])
        #expect(s.selectedID == 4)
    }

    @Test func navigationWhileOptionIsStillHeldAfterTyping() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        _ = s.handle(.character("z"), optionDown: true, from: .eventTap)
        _ = s.setResults([3, 4])
        let right = s.handle(.arrow(.right), optionDown: true, from: .eventTap)
        #expect(right.swallow)
        #expect(s.selectedID == 4)
        #expect(s.handle(.enter, optionDown: true, from: .eventTap).effects == [.hide, .focus(4)])
    }

    @Test func navigationAfterReleasingOptionGoesToTheField() {
        var s = state()
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        _ = s.handle(.character("z"), optionDown: true, from: .eventTap)
        _ = s.optionReleased()
        #expect(s.handle(.arrow(.right), optionDown: false, from: .eventTap).swallow == false)
    }

    @Test func tapHotkeyDuringAHoldComesThroughTheTap() {
        var s = state()
        #expect(s.handle(.tapHotkey, optionDown: true, from: .eventTap).swallow == false, "hidden: the hotkey fires itself")
        _ = s.handle(.tab(backward: false), optionDown: true, from: .eventTap)
        let r = s.handle(.tapHotkey, optionDown: true, from: .eventTap)
        #expect(r.swallow)
        #expect(r.effects == [.cancelScheduledShow, .show, .takeKeyboard])
        #expect(s.phase == .open)
        #expect(s.handle(.tapHotkey, optionDown: true, from: .eventTap).swallow == false, "open: the hotkey closes it itself")
    }

    @Test func clickChooses() {
        var s = state()
        _ = s.toggleTap()
        #expect(s.choose(4) == [.hide, .focus(4)])
        #expect(s.dismiss().isEmpty)
    }
}
