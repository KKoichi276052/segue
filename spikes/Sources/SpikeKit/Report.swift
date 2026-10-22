import Foundation

/// Collects pass/fail checks and prints a verdict at the end of a spike.
public final class Report {
    private var checks: [(name: String, passed: Bool?, detail: String)] = []
    private let title: String

    public init(_ title: String) {
        self.title = title
        print("== \(title) ==")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(machineModel())")
        print("")
    }

    public func section(_ name: String) {
        print("\n-- \(name) --")
    }

    /// Records a check against a spec target. `passed == nil` means not measured.
    public func check(_ name: String, passed: Bool?, _ detail: String) {
        checks.append((name, passed, detail))
        print("[\(label(passed))] \(name): \(detail)")
    }

    public func finish() {
        print("\n== \(title): summary ==")
        for c in checks {
            print("[\(label(c.passed))] \(c.name): \(c.detail)")
        }
        let measured = checks.compactMap(\.passed)
        let verdict = measured.isEmpty ? "NOT MEASURED" : (measured.allSatisfy { $0 } ? "PASS" : "FAIL")
        let incomplete = measured.count < checks.count ? " (some checks not measured)" : ""
        print("Verdict: \(verdict)\(incomplete)")
    }

    private func label(_ passed: Bool?) -> String {
        switch passed {
        case true?: "PASS"
        case false?: "FAIL"
        case nil: "SKIP"
        }
    }
}

public func machineModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &buffer, &size, nil, 0)
    return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
}

/// Parses `--name value` and `--flag` style arguments.
public struct Arguments {
    private let args = Array(CommandLine.arguments.dropFirst())

    public init() {}

    public func flag(_ name: String) -> Bool { args.contains("--\(name)") }

    public func value(_ name: String) -> String? {
        guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    public func int(_ name: String) -> Int? { value(name).flatMap(Int.init) }
}
