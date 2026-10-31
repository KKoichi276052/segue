import os

enum Log {
    static let ui = Logger(subsystem: "io.github.kkoichi276052.segue", category: "ui")
    static let signposter = OSSignposter(subsystem: "io.github.kkoichi276052.segue", category: .pointsOfInterest)
}
