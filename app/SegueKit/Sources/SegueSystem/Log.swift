import os

/// Loggers and the signposter used across Segue. View with
/// `log stream --predicate 'subsystem == "io.github.kkoichi276052.segue"'`.
public enum Log {
    public static let subsystem = "io.github.kkoichi276052.segue"
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let inventory = Logger(subsystem: subsystem, category: "inventory")
    public static let focus = Logger(subsystem: subsystem, category: "focus")
    public static let keys = Logger(subsystem: subsystem, category: "keys")
    public static let snapshots = Logger(subsystem: subsystem, category: "snapshots")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
