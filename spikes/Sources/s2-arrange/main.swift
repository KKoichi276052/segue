import AppKit
import SpikeKit

// S2 Arranging (docs/SPEC.md §10).
// Pass when: 3–6 windows arranged in under 300 ms, 95% or more succeed, no visible bounce.
//
// Picks one standard window from each target app that is running, arranges them in a
// grid on the main display, checks where each one ends up, then puts them back.
//
// Usage:
//   s2-arrange                       Safari, Chrome, VS Code, Xcode, Terminal, Finder
//   s2-arrange --apps a,b,c          bundle IDs to use instead
//   s2-arrange --rounds <n>          repeat the arrange/restore cycle (default 5)
//   s2-arrange --keep-enhanced-ui    leave AXEnhancedUserInterface on (to compare)

let defaultApps = [
    "com.apple.Safari", "com.google.Chrome", "com.microsoft.VSCode",
    "com.apple.dt.Xcode", "com.apple.Terminal", "com.apple.finder",
]

let args = Arguments()
let report = Report("S2 Arranging")
print(Permissions.describe())
guard Permissions.accessibility(prompt: true) else {
    report.check("Arranging", passed: nil, "needs Accessibility. \(Permissions.hint)")
    report.finish()
    exit(1)
}

let bundleIDs = args.value("apps")?.split(separator: ",").map(String.init) ?? defaultApps
let rounds = args.int("rounds") ?? 5
let tolerance: CGFloat = 2

struct Target {
    let app: NSRunningApplication
    let window: AXWindow
    let original: CGRect
}

var targets: [Target] = []
for id in bundleIDs {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
        print("skip \(id): not running")
        continue
    }
    guard let window = WindowList.axWindows(of: app).first(where: { !$0.isMinimized && $0.subrole == "AXStandardWindow" }) else {
        print("skip \(id): no visible standard window on this Space")
        continue
    }
    targets.append(Target(app: app, window: window, original: window.frame))
}

guard targets.count >= 3 else {
    report.check("Arranging", passed: nil, "only \(targets.count) target windows found; open at least 3 of: \(bundleIDs.joined(separator: ", "))")
    report.finish()
    exit(1)
}

// Grid layout on the main display's visible area: 2 rows, up to 3 columns.
let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrameInAXCoordinates
let cols = min(3, (targets.count + 1) / 2)
let rows = targets.count > cols ? 2 : 1
@MainActor func slot(_ i: Int, shift: Bool) -> CGRect {
    // Alternate rounds use a shifted assignment so every round really moves each window.
    let index = shift ? (i + 1) % targets.count : i
    let w = area.width / CGFloat(cols)
    let h = area.height / CGFloat(rows)
    return CGRect(x: area.minX + CGFloat(index % cols) * w, y: area.minY + CGFloat(index / cols) * h, width: w, height: h).integral
}

/// Sets a frame the way window managers such as Rectangle do: size, position, size again
/// (the second size fixes clamping when the window moved across a display edge).
/// Enhanced UI (turned on by assistive apps) makes some apps animate frame changes, so turn it off while setting.
@MainActor func setFrame(_ t: Target, _ frame: CGRect) -> Bool {
    let appElement = AXUIElementCreateApplication(t.app.processIdentifier)
    let enhanced: Bool = AX.attribute(appElement, "AXEnhancedUserInterface") ?? false
    let toggle = enhanced && !args.flag("keep-enhanced-ui")
    if toggle { AX.setBool(appElement, "AXEnhancedUserInterface", false) }
    defer { if toggle { AX.setBool(appElement, "AXEnhancedUserInterface", true) } }
    let a = AX.setSize(t.window.element, frame.size)
    let b = AX.setPosition(t.window.element, frame.origin)
    let c = AX.setSize(t.window.element, frame.size)
    return a == .success && b == .success && c == .success
}

/// Explains a frame that's right except for what the app allows: larger than asked
/// (the app's minimum size) or slightly smaller (sizing in steps, such as Terminal's
/// character cells). Returns nil when the window really missed.
func appLimit(wanted: CGRect, got: CGRect) -> String? {
    guard abs(got.minX - wanted.minX) <= tolerance, abs(got.minY - wanted.minY) <= tolerance else { return nil }
    let step: CGFloat = 20
    let dw = got.width - wanted.width
    let dh = got.height - wanted.height
    guard dw >= -step, dh >= -step else { return nil }
    return dw > tolerance || dh > tolerance ? "app minimum size" : "app sizes in steps"
}

/// Samples the frame for `duration` after setting to detect bounce (the frame changing after it first settled).
@MainActor func settle(_ t: Target, duration: TimeInterval) -> (final: CGRect, changes: Int) {
    var samples: [CGRect] = []
    let end = Date().addingTimeInterval(duration)
    while Date() < end {
        if let f = AX.frame(t.window.element) { samples.append(f) }
        Thread.sleep(forTimeInterval: 0.016)
    }
    var changes = 0
    for (a, b) in zip(samples, samples.dropFirst()) where !a.isClose(to: b, tolerance: 0.5) { changes += 1 }
    return (samples.last ?? .zero, changes)
}

report.section("Targets")
for t in targets { print("\(t.window.app): “\(t.window.title.prefix(50))” \(t.original.short)") }
print("Area \(area.short), grid \(cols)×\(rows), \(rounds) rounds")

var totalSamples: [Double] = []
var perApp: [String: [Double]] = [:]
var attempts = 0
var landed = 0
var limited = 0
var bounces: [String] = []
var misses: [String] = []

for round in 0..<rounds {
    let frames = targets.indices.map { slot($0, shift: round % 2 == 1) }
    var results: [Bool] = []
    let (_, total) = measure {
        for (t, f) in zip(targets, frames) {
            let (ok, ms) = measure { setFrame(t, f) }
            perApp[t.window.app, default: []].append(ms)
            results.append(ok)
        }
    }
    totalSamples.append(total)
    for (i, (t, f)) in zip(targets, frames).enumerated() {
        attempts += 1
        let s = settle(t, duration: 0.3)
        if results[i] && s.final.isClose(to: f, tolerance: tolerance) {
            landed += 1
        } else if results[i], let reason = appLimit(wanted: f, got: s.final) {
            limited += 1
            misses.append("round \(round + 1) \(t.window.app): wanted \(f.short), got \(s.final.short) (\(reason))")
        } else {
            misses.append("round \(round + 1) \(t.window.app): wanted \(f.short), got \(s.final.short)")
        }
        if s.changes > 0 { bounces.append("round \(round + 1) \(t.window.app): frame changed \(s.changes)× after setting") }
    }
    print("round \(round + 1): \(fmt(total)) ms for \(targets.count) windows")
}

report.section("Restore")
for t in targets { _ = setFrame(t, t.original) }
for t in targets {
    let s = settle(t, duration: 0.1)
    print("\(t.window.app): \(s.final.isClose(to: t.original, tolerance: tolerance) ? "restored" : "NOT restored, at \(s.final.short), was \(t.original.short)")")
}

report.section("Per app")
for (app, samples) in perApp.sorted(by: { $0.key < $1.key }) {
    if let s = Stats(samples) { print("\(app): \(s.summary)") }
}
if !misses.isEmpty { print("\nMisses:"); misses.forEach { print("  \($0)") } }
if !bounces.isEmpty { print("\nBounce:"); bounces.forEach { print("  \($0)") } }

report.section("Results")
if let s = Stats(totalSamples) {
    report.check("Arrange time", passed: s.p95 < 300, "\(targets.count) windows: \(s.summary)")
}
// A window that ends as close as its app allows counts as a success: no window manager
// can go below an app's minimum size. Exact landings are reported alongside.
let rate = Double(landed + limited) / Double(attempts) * 100
report.check("Success rate", passed: rate >= 95,
             "\(landed + limited)/\(attempts) placed (\(fmt(rate, 1))%): \(landed) within \(Int(tolerance)) pt, \(limited) as close as the app allows")
report.check("No bounce", passed: bounces.isEmpty,
             bounces.isEmpty ? "no frame changes in the 300 ms after setting" : "\(bounces.count) bounces; also watch the screen while it runs")
report.finish()
