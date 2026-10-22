import AppKit
import SpikeKit

// S1 Window list (docs/SPEC.md §10).
// Pass when: 50 windows listed in under 50 ms when warm; any window focuses
// reliably, including on other Spaces.
//
// Usage:
//   s1-windows                 list windows and time the warm listing
//   s1-windows --focus <id>    also focus one window by CGWindowID
//   s1-windows --focus-all     also focus every window in turn (moves focus around!)
//   s1-windows --runs <n>      timing iterations (default 30)

let args = Arguments()
let report = Report("S1 Window list")
print(Permissions.describe())

let trusted = Permissions.accessibility(prompt: true)
if !trusted {
    print("Accessibility is missing, so only the Window Server list is measured. \(Permissions.hint)")
}

/// The full listing the product would need: Window Server list plus Accessibility, matched by ID.
func fullListing() -> (cg: [CGWindow], ax: [AXWindow]) {
    (WindowList.cgWindows(), trusted ? WindowList.axWindows() : [])
}

// Cold run, then warm runs.
let (_, coldMs) = measure { fullListing() }
let runs = args.int("runs") ?? 30
var cgSamples: [Double] = []
var axSamples: [Double] = []
var fullSamples: [Double] = []
var last = fullListing()
for _ in 0..<runs {
    let (cg, cgMs) = measure { WindowList.cgWindows() }
    let (ax, axMs) = measure { trusted ? WindowList.axWindows() : [] }
    cgSamples.append(cgMs)
    axSamples.append(axMs)
    fullSamples.append(cgMs + axMs)
    last = (cg, ax)
}

let (cgWindows, axWindows) = last
let axByID = Dictionary(axWindows.compactMap { w in w.windowID.map { ($0, w) } }, uniquingKeysWith: { a, _ in a })
let regularPIDs = Set(WindowList.regularApps().map(\.processIdentifier))
let userCG = cgWindows.filter { regularPIDs.contains($0.pid) }

report.section("Windows")
print("Window Server: \(cgWindows.count) normal-layer windows, \(userCG.count) owned by regular apps (\(userCG.filter(\.isOnScreen).count) on screen)")
print("Accessibility: \(axWindows.count) windows, \(axWindows.filter { $0.windowID != nil }.count) with a window ID, \(axWindows.filter(\.isMinimized).count) minimized")
print("")
print(columns([("id", 8), ("pid", 6), ("scr", 4), ("app", 18), ("frame", 26), ("title / state", 0)]))
for w in userCG.sorted(by: { ($0.owner, $0.id) < ($1.owner, $1.id) }) {
    let ax = axByID[w.id]
    var state: [String] = []
    if let ax {
        if ax.isMinimized { state.append("minimized") }
        if let sub = ax.subrole, sub != "AXStandardWindow" { state.append(sub) }
    } else if trusted {
        state.append(w.isOnScreen ? "no AX match" : "no AX match (other Space or hidden?)")
    }
    let title = ax?.title ?? w.title ?? "—"
    print(columns([("\(w.id)", 8), ("\(w.pid)", 6), (w.isOnScreen ? "yes" : "no", 4), (w.owner, 18), (w.bounds.short, 26),
                   (([String(title.prefix(40))] + state).joined(separator: " · "), 0)]))
}

report.section("Timing")
print("cold full listing: \(fmt(coldMs)) ms")
if let s = Stats(cgSamples) { print("Window Server:  \(s.summary)") }
if let s = Stats(axSamples), trusted { print("Accessibility:  \(s.summary)") }
if let s = Stats(fullSamples) { print("Full listing:   \(s.summary)") }

// Target is 50 windows in under 50 ms. Scale the target to the windows actually listed.
let listed = max(userCG.count, axWindows.count)
if let s = Stats(fullSamples) {
    let perWindow = s.median / Double(max(listed, 1))
    let projected50 = perWindow * 50
    report.check("Warm listing", passed: trusted ? s.median < 50 && projected50 < 50 : nil,
                 "median \(fmt(s.median)) ms for \(listed) windows; projected \(fmt(projected50)) ms for 50"
                     + (trusted ? "" : " (Window Server only; Accessibility missing)"))
}

if trusted {
    let matched = userCG.filter { axByID[$0.id] != nil }.count
    let unmatchedOnScreen = userCG.filter { $0.isOnScreen && axByID[$0.id] == nil }
    report.check("AX ↔ window ID matching", passed: unmatchedOnScreen.isEmpty,
                 "\(matched)/\(userCG.count) Window Server windows matched; \(unmatchedOnScreen.count) on-screen windows unmatched")
    let offScreenUnmatched = userCG.filter { !$0.isOnScreen && axByID[$0.id] == nil }.count
    print("  \(offScreenUnmatched) off-screen windows have no Accessibility element. Windows on other Spaces are expected here: Accessibility only returns the current Space's windows.")
} else {
    report.check("AX ↔ window ID matching", passed: nil, "needs Accessibility")
}

// Focusing. Windows on the current Space go through public Accessibility calls. Windows
// on other Spaces have no element in `AXWindows`, so they're found by remote token and
// brought forward with SkyLight, which also switches Space (see SpikeKit/Focus.swift).
@MainActor
func focus(_ windowID: CGWindowID) -> (ok: Bool, ms: Double, detail: String) {
    guard let cg = WindowList.cgWindows().first(where: { $0.id == windowID }) else { return (false, 0, "no such window") }
    guard let app = NSRunningApplication(processIdentifier: cg.pid) else { return (false, 0, "app gone") }
    let target = WindowList.axWindows(of: app).first(where: { $0.windowID == windowID })
    var method = "AX"
    let (_, ms) = measure {
        if let target {
            if target.isMinimized { AX.setBool(target.element, kAXMinimizedAttribute, false) }
            AX.setBool(target.element, kAXMainAttribute, true)
            AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
            app.activate(options: [])
            return
        }
        let (found, tried) = OffSpace.element(pid: cg.pid, windowID: windowID)
        method = found == nil ? "SkyLight, no AX element (\(tried) tokens tried)" : "SkyLight + token element (\(tried) tokens tried)"
        guard OffSpace.focus(pid: cg.pid, windowID: windowID) else { method += ", SkyLight calls unavailable"; return }
        if let found {
            if AX.attribute(found, kAXMinimizedAttribute) == true { AX.setBool(found, kAXMinimizedAttribute, false) }
            AXUIElementPerformAction(found, kAXRaiseAction as CFString)
        }
    }
    let name = "\(cg.owner) “\((target?.title ?? cg.title ?? "").prefix(40))” via \(method)"
    // Verify: the app is frontmost and its focused window is the target. A Space switch
    // animates, so allow 1.5 s.
    let deadline = Date().addingTimeInterval(1.5)
    var verifiedAt: Double?
    let start = ContinuousClock.now
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == cg.pid
        let appElement = AXUIElementCreateApplication(cg.pid)
        if frontmost, let focused: AXUIElement = AX.attribute(appElement, kAXFocusedWindowAttribute), AX.windowID(focused) == windowID {
            verifiedAt = (ContinuousClock.now - start).milliseconds
            break
        }
    }
    if let verifiedAt { return (true, ms, "\(name) · focused \(fmt(verifiedAt)) ms after the request") }
    return (false, ms, "\(name) did not become the focused window within 1.5 s")
}

if trusted, let id = args.int("focus").map(CGWindowID.init) {
    report.section("Focus \(id)")
    let r = focus(id)
    report.check("Focus window \(id)", passed: r.ok, "\(r.detail) · request took \(fmt(r.ms)) ms")
} else if trusted, args.flag("focus-all") {
    report.section("Focus every window")
    let original = NSWorkspace.shared.frontmostApplication
    var results: [Bool] = []
    let offSpace = userCG.filter { !$0.isOnScreen && axByID[$0.id] == nil }
    let offSpaceIDs = Set(offSpace.map(\.id))
    var offSpaceOK = 0
    for w in userCG where axByID[w.id]?.subrole == "AXStandardWindow" || axByID[w.id] == nil {
        let r = focus(w.id)
        results.append(r.ok)
        if r.ok, offSpaceIDs.contains(w.id) { offSpaceOK += 1 }
        print("  \(r.ok ? "ok  " : "FAIL") \(w.id) \(r.detail) (\(fmt(r.ms)) ms)")
    }
    original?.activate(options: [])
    let ok = results.filter { $0 }.count
    report.check("Focus any window", passed: ok == results.count,
                 "\(ok)/\(results.count) focused, including \(offSpaceOK)/\(offSpace.count) on other Spaces or hidden")
} else {
    report.check("Focus any window", passed: nil, trusted ? "run with --focus <id> or --focus-all" : "needs Accessibility")
}

report.finish()
