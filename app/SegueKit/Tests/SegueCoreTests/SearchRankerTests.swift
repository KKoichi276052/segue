import CoreGraphics
import Testing
@testable import SegueCore

@Suite struct SearchRankerTests {
    func window(_ id: WindowID, _ app: String, _ title: String) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: app, bundleID: nil, title: title, frame: .zero, isMinimized: false,
                   isAppHidden: false, isOnScreen: true, hasAccessibilityElement: true)
    }

    var windows: [WindowInfo] {
        [
            window(1, "Safari", "Apple Developer Documentation"),
            window(2, "Zed", "main.rs — segue"),
            window(3, "Ghostty", "kk@mac: ~/segue"),
            window(4, "Zen", "設計メモ — 日本語のタイトル"),
            window(5, "Notes", "カタカナのメモ"),
            window(6, "Zed", "SPEC.md — segue"),
        ]
    }

    @Test func emptyQueryKeepsRecencyOrder() {
        #expect(SearchIndex(windows: windows).search("  ") == [1, 2, 3, 4, 5, 6])
    }

    @Test func appNamePrefix() {
        #expect(SearchIndex(windows: windows).search("saf") == [1])
    }

    @Test func caseAndFullWidthAreIgnored() {
        let index = SearchIndex(windows: windows)
        #expect(index.search("SAFARI") == [1])
        #expect(index.search("ＳＡＦ") == [1])
        #expect(index.search("ｓｐｅｃ") == [6])
    }

    @Test func japaneseSubstring() {
        let index = SearchIndex(windows: windows)
        #expect(index.search("日本語") == [4])
        #expect(index.search("メモ").sorted() == [4, 5])
    }

    @Test func katakanaAndHiraganaMatchEachOther() {
        let index = SearchIndex(windows: windows)
        #expect(index.search("かたかな") == [5])
        #expect(index.search("ｶﾀｶﾅ") == [5], "half-width katakana")
    }

    @Test func everyWordMustMatch() {
        let index = SearchIndex(windows: windows)
        #expect(index.search("zed main") == [2])
        #expect(index.search("zed nothing").isEmpty)
    }

    @Test func wordPrefixBeatsSubstringAndTiesGoToRecency() {
        let index = SearchIndex(windows: windows)
        // "segue" is a word in 2, 3 and 6; 2 is the most recent of those.
        #expect(index.search("segue") == [2, 3, 6])
        // "doc" starts a word in 1; it's only inside another word elsewhere (none here).
        #expect(index.search("doc") == [1])
    }

    @Test func titleMatchBeatsAppMatchOfTheSameKind() {
        let ws = [window(1, "Notes", "Shopping"), window(2, "Shopping List", "Groceries")]
        #expect(SearchIndex(windows: ws).search("shop") == [1, 2])
    }

    @Test func scatteredLetters() {
        let index = SearchIndex(windows: windows)
        #expect(index.search("gsty") == [3])
        #expect(index.search("q").isEmpty, "one letter only matches as a substring")
    }

    @Test func scores() {
        func s(_ t: String, _ f: String) -> Int? { SearchIndex.score(Array(t), in: Array(f)) }
        #expect(s("ab", "ab") == 100)
        #expect(s("ab", "abc") == 90)
        #expect(s("cd", "ab cd") == 80)
        #expect(s("cd", "abcd") == 59)
        #expect(s("ac", "abc") == 29)
        #expect(s("abcd", "abc") == nil)
    }

    @Test func fastEnoughForEveryKeystroke() {
        let many = (0..<100).map { i in window(WindowID(i), "App \(i % 9)", "Document \(i) — 設計メモ project notes and more words") }
        let index = SearchIndex(windows: many)
        let (_, ms) = measure { for query in ["d", "do", "doc", "docu", "設計", "pnm"] { _ = index.search(query) } }
        #expect(ms / 6 < 16, "per keystroke: \(ms / 6) ms")
    }

    @Test func normalization() {
        #expect(SearchText.normalize("ＡＢＣ１２３") == "abc123")
        #expect(SearchText.normalize("カタカナ") == "かたかな")
        #expect(SearchText.normalize("が") == "が", "voicing marks stay")
    }
}
