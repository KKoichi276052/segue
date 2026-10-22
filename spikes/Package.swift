// swift-tools-version: 6.0
import PackageDescription

// M0 technical spikes (docs/SPEC.md §10). One executable per spike; each prints
// its measurements and a pass or fail against the spec's targets.
let package = Package(
    name: "SegueSpikes",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SpikeKit"),
        .executableTarget(name: "s1-windows", dependencies: ["SpikeKit"]),
        .executableTarget(name: "s2-arrange", dependencies: ["SpikeKit"]),
        .executableTarget(name: "s4-capture", dependencies: ["SpikeKit"]),
        .executableTarget(name: "s6-panel", dependencies: ["SpikeKit"]),
    ]
)
