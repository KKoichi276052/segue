/// Hotkey-to-first-frame timings (docs/SPEC.md §8: within 16 ms), for the Debug menu.
public struct ShowTimings: Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// ⌥ Space, from the key event to the first display frame after the panel was committed.
        case tap = "⌥ Space"
        /// Hold mode, from the end of the show delay.
        case hold = "hold"
    }

    public struct Sample: Sendable {
        public var kind: Kind
        public var ms: Double
        /// The first show after launch or after a display change.
        public var first: Bool
    }

    public private(set) var samples: [Sample] = []

    public init() {}

    public mutating func record(_ kind: Kind, ms: Double, first: Bool) {
        samples.append(Sample(kind: kind, ms: ms, first: first))
        if samples.count > 1000 { samples.removeFirst(samples.count - 1000) }
    }

    public func summary(targetMs: Double = 16) -> String {
        var lines: [String] = []
        for kind in Kind.allCases {
            let all = samples.filter { $0.kind == kind }
            guard let stats = Stats(all.map(\.ms)) else {
                lines.append("\(kind.rawValue): no samples")
                continue
            }
            lines.append("\(kind.rawValue): \(stats.summary) [\(stats.median <= targetMs ? "PASS" : "FAIL") median ≤ \(Int(targetMs)) ms]")
            let firsts = all.filter(\.first).map { fmt($0.ms) + " ms" }
            if !firsts.isEmpty { lines.append("  first shows (launch or display change): \(firsts.joined(separator: ", "))") }
        }
        return lines.joined(separator: "\n")
    }
}
