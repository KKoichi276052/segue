import Foundation

/// Text normalization for search: NFKC (full-width Latin and digits become half-width,
/// half-width katakana becomes full-width), case folding, and katakana folded to hiragana so
/// either kana matches. Diacritics are kept: folding them would also strip Japanese voicing
/// marks (が would match か).
public enum SearchText {
    public static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        var scalars = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value), let hiragana = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(hiragana)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}

/// Ranks windows for a query (docs/SPEC.md §6.5): window titles and app names.
public struct SearchIndex: Sendable {
    private struct Entry: Sendable {
        var id: WindowID
        var title: [Character]
        var app: [Character]
    }

    private let entries: [Entry]

    /// `windows` most recently used first; that order breaks ties.
    public init(windows: [WindowInfo]) {
        entries = windows.map { Entry(id: $0.id, title: Array(SearchText.normalize($0.title)), app: Array(SearchText.normalize($0.appName))) }
    }

    /// Matching windows, best first. Every word of the query must match the title or app name.
    public func search(_ query: String) -> [WindowID] {
        let tokens = SearchText.normalize(query).split(whereSeparator: \.isWhitespace).map { Array($0) }
        guard !tokens.isEmpty else { return entries.map(\.id) }
        var scored: [(id: WindowID, score: Int, rank: Int)] = []
        for (rank, entry) in entries.enumerated() {
            var total = 0
            var matchedAll = true
            for token in tokens {
                let title = Self.score(token, in: entry.title)
                let app = Self.score(token, in: entry.app).map { $0 - 5 } // a title match wins a tie
                guard let best = [title, app].compactMap({ $0 }).max() else {
                    matchedAll = false
                    break
                }
                total += best
            }
            if matchedAll { scored.append((entry.id, total, rank)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }.map(\.id)
    }

    /// The best way `token` matches `field`, or nil: the whole field, its start, the start of
    /// a word, anywhere, or as scattered letters in order.
    static func score(_ token: [Character], in field: [Character]) -> Int? {
        guard !token.isEmpty, token.count <= field.count else { return nil }
        if field == token { return 100 }
        if field.starts(with: token) { return 90 }
        var substringAt: Int?
        var i = 0
        while i + token.count <= field.count {
            if field[i] == token[0], Array(field[i..<i + token.count]) == token {
                if isWordStart(field, i) { return 80 }
                if substringAt == nil { substringAt = i }
            }
            i += 1
        }
        if let at = substringAt { return 60 - min(at, 20) / 2 }
        // Scattered letters, only for two or more, so one letter doesn't match everything.
        guard token.count >= 2 else { return nil }
        var t = 0
        var gaps = 0
        var last = -1
        for (j, c) in field.enumerated() where t < token.count && c == token[t] {
            if last >= 0 { gaps += j - last - 1 }
            last = j
            t += 1
        }
        guard t == token.count else { return nil }
        return max(10, 30 - gaps)
    }

    private static func isWordStart(_ field: [Character], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let previous = field[i - 1]
        return !(previous.isLetter || previous.isNumber)
    }
}
