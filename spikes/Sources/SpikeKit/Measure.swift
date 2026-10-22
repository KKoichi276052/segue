import Foundation

/// Runs `body` and returns its result with the elapsed time in milliseconds.
public func measure<T>(_ body: () throws -> T) rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let value = try body()
    return (value, (ContinuousClock.now - start).milliseconds)
}

public func measure<T>(_ body: () async throws -> T) async rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let value = try await body()
    return (value, (ContinuousClock.now - start).milliseconds)
}

extension Duration {
    public var milliseconds: Double {
        let (s, attos) = components
        return Double(s) * 1_000 + Double(attos) / 1e15
    }
}

public struct Stats {
    public let count: Int
    public let min: Double
    public let median: Double
    public let p95: Double
    public let max: Double

    public init?(_ samples: [Double]) {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        count = sorted.count
        min = sorted.first!
        max = sorted.last!
        median = sorted[sorted.count / 2]
        p95 = sorted[Swift.min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)]
    }

    public var summary: String {
        "n=\(count) min \(fmt(min)) · median \(fmt(median)) · p95 \(fmt(p95)) · max \(fmt(max)) ms"
    }
}

public func fmt(_ value: Double, _ digits: Int = 2) -> String {
    String(format: "%.\(digits)f", value)
}

/// Resident memory of this process in bytes.
public func residentMemory() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

/// Joins columns, padding each to its width (`String(format:)` can't pad Swift strings).
/// A width of 0 leaves the cell as is.
public func columns(_ cells: [(String, Int)]) -> String {
    cells.map { text, width in
        width == 0 ? text : text.count >= width ? String(text.prefix(width)) : text + String(repeating: " ", count: width - text.count)
    }.joined(separator: " ")
}
