// swift-tools-version: 6.2
import PackageDescription

// Segue's code, split as in docs/SPEC.md §9 "Project structure":
// SegueCore is pure logic with no AppKit and carries the unit tests; SegueSystem talks to
// macOS; SegueUI draws the panel and windows. The app target in ../Segue wires them together.
let package = Package(
    name: "SegueKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SegueCore", targets: ["SegueCore"]),
        .library(name: "SegueSystem", targets: ["SegueSystem"]),
        .library(name: "SegueUI", targets: ["SegueUI"]),
    ],
    targets: [
        .target(name: "SegueCore"),
        .target(name: "SegueSystem", dependencies: ["SegueCore"]),
        .target(
            name: "SegueUI",
            dependencies: ["SegueCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SegueCoreTests", dependencies: ["SegueCore"]),
    ]
)
