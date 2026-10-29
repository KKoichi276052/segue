import AppKit
import SpikeKit

// S5 Restoring (docs/SPEC.md §10).
// Pass when: windows are matched to their saved slots correctly for 90% or more of a test set.
//
// Saves the standard windows on the current Space as slots (app, title, document, frame),
// then later finds each slot's window again, launching apps or opening documents that
// aren't there, and puts the windows back.
//
// Usage:
//   s5-restore --inspect             what each window offers for reopening (read only)
//   s5-restore --save <file>         save the current Space's windows as slots (read only)
//   s5-restore --match <file>        match the slots to the windows open now (read only)
//   s5-restore --restore <file>      launch what's missing, match, and set the saved frames.
//                                    Launches apps and moves windows.

let args = Arguments()
let report = Report("S5 Restoring")
guard Permissions.accessibility(prompt: false) else {
    report.check("Restoring", passed: nil, "needs Accessibility. \(Permissions.hint)")
    report.finish()
    exit(1)
}

// MARK: Slots

struct Slot: Codable {
    var bundleID: String
    var appName: String
    var appPath: String
    var title: String
    /// A file URL from AXDocument, when the app reports one.
    var document: String?
    var frame: CGRect
}

/// What a window says about itself through Accessibility.
func document(of window: AXWindow) -> String? {
    guard let value: String = AX.attribute(window.element, kAXDocumentAttribute), !value.isEmpty else { return nil }
    return value
}

func standardWindows(of app: NSRunningApplication) -> [AXWindow] {
    WindowList.axWindows(of: app).filter { !$0.isMinimized && $0.subrole == "AXStandardWindow" }
}

func currentSlots() -> [Slot] {
    WindowList.regularApps().flatMap { app -> [Slot] in
        guard let id = app.bundleIdentifier, let url = app.bundleURL, id != Bundle.main.bundleIdentifier else { return [] }
        return standardWindows(of: app).map { w in
            Slot(bundleID: id, appName: w.app, appPath: url.path, title: w.title, document: document(of: w), frame: w.frame)
        }
    }
}

func load(_ path: String) -> [Slot] {
    guard let data = FileManager.default.contents(atPath: path), let slots = try? JSONDecoder().decode([Slot].self, from: data) else {
        print("Can't read slots from \(path)")
        exit(1)
    }
    return slots
}

// MARK: Matching

/// How well a window fits a slot. The product would use the same signals.
enum Fit: Int, Comparable {
    case none = 0, fallback, titleWords, titleExact, document
    static func < (a: Fit, b: Fit) -> Bool { a.rawValue < b.rawValue }
}

func words(_ s: String) -> Set<String> {
    Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 })
}

func fit(_ slot: Slot, _ window: AXWindow) -> Fit {
    if let d = slot.document, d == document(of: window) { return .document }
    if !slot.title.isEmpty, slot.title == window.title { return .titleExact }
    let a = words(slot.title), b = words(window.title)
    if !a.isEmpty, Double(a.intersection(b).count) / Double(a.count) >= 0.5 { return .titleWords }
    return .fallback
}

struct Match {
    var slot: Slot
    var window: AXWindow?
    var fit: Fit
}

/// Best fit first across all slots of an app, each window used once; leftover slots take
/// leftover windows of the same app as a fallback.
func match(_ slots: [Slot]) -> [Match] {
    var result: [Match] = []
    for (bundleID, group) in Dictionary(grouping: slots, by: \.bundleID) {
        let windows = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap(standardWindows)
        var pairs: [(slot: Int, window: Int, fit: Fit)] = []
        for (i, s) in group.enumerated() { for (j, w) in windows.enumerated() { pairs.append((i, j, fit(s, w))) } }
        pairs.sort { $0.fit > $1.fit }
        var slotTaken = Set<Int>(), windowTaken = Set<Int>()
        var found: [Int: (Int, Fit)] = [:]
        for p in pairs where !slotTaken.contains(p.slot) && !windowTaken.contains(p.window) {
            slotTaken.insert(p.slot); windowTaken.insert(p.window)
            found[p.slot] = (p.window, p.fit)
        }
        for (i, s) in group.enumerated() {
            if let (j, f) = found[i] { result.append(Match(slot: s, window: windows[j], fit: f)) }
            else { result.append(Match(slot: s, window: nil, fit: .none)) }
        }
    }
    return result.sorted { ($0.slot.appName, $0.slot.title) < ($1.slot.appName, $1.slot.title) }
}

/// Correct when the window is the one that was saved: same document, or same title.
func isCorrect(_ m: Match) -> Bool {
    guard let w = m.window else { return false }
    if let d = m.slot.document { return d == document(of: w) }
    return w.title == m.slot.title
}

func printMatches(_ matches: [Match]) -> Int {
    var correct = 0
    for m in matches {
        let ok = isCorrect(m)
        if ok { correct += 1 }
        let got = m.window.map { "“\($0.title.prefix(40))”" } ?? "no window"
        print("[\(ok ? "ok" : "--")] \(m.slot.appName): “\(m.slot.title.prefix(40))” → \(got) (\(m.fit))")
    }
    return correct
}

// MARK: Restoring

/// Waits for the app to have at least `count` standard windows, up to `timeout`.
func waitForWindows(_ bundleID: String, count: Int, timeout: TimeInterval) -> Double? {
    let start = ContinuousClock.now
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let n = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).flatMap(standardWindows).count
        if n >= count { return (ContinuousClock.now - start).milliseconds }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return nil
}

/// Launches the app, with the slots' documents when it has any. Returns how long until
/// its windows were there, or nil on timeout.
func launch(_ slots: [Slot]) -> (ms: Double?, note: String) {
    let first = slots[0]
    let appURL = URL(fileURLWithPath: first.appPath)
    let documents = slots.compactMap(\.document).compactMap(URL.init(string:))
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    var error: Error?
    var done = false
    if documents.isEmpty {
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, e in error = e; done = true }
    } else {
        NSWorkspace.shared.open(documents, withApplicationAt: appURL, configuration: config) { _, e in error = e; done = true }
    }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    if let error { return (nil, "launch failed: \(error.localizedDescription)") }
    let ms = waitForWindows(first.bundleID, count: slots.count, timeout: 10)
    return (ms, documents.isEmpty ? "launched (the app restores its own windows, if it does)" : "launched with \(documents.count) document(s)")
}

func setFrame(_ window: AXWindow, _ frame: CGRect) {
    AX.setSize(window.element, frame.size)
    AX.setPosition(window.element, frame.origin)
    AX.setSize(window.element, frame.size)
}

// MARK: Main

if args.flag("inspect") {
    report.section("Windows on this Space")
    var withDocument = 0
    let slots = currentSlots()
    for s in slots {
        if s.document != nil { withDocument += 1 }
        print("\(s.appName) [\(s.bundleID)]: “\(s.title.prefix(50))”  document: \(s.document ?? "none")")
    }
    print("\n\(slots.count) windows, \(withDocument) with a document")
    report.finish()
} else if let path = args.value("save") {
    let slots = currentSlots()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileManager.default.createFile(atPath: path, contents: try! encoder.encode(slots))
    print("saved \(slots.count) slots to \(path)")
    for s in slots { print("  \(s.appName): “\(s.title.prefix(50))” \(s.frame.short)") }
} else if let path = args.value("match") {
    let slots = load(path)
    let (matches, ms) = measure { match(slots) }
    report.section("Matches")
    let correct = printMatches(matches)
    report.section("Results")
    let rate = Double(correct) / Double(max(slots.count, 1)) * 100
    report.check("Correct match", passed: rate >= 90, "\(correct)/\(slots.count) (\(fmt(rate, 1))%), matched in \(fmt(ms)) ms")
    report.finish()
} else if let path = args.value("restore") {
    let slots = load(path)
    report.section("Launching")
    let start = ContinuousClock.now
    for (bundleID, group) in Dictionary(grouping: slots, by: \.bundleID) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            let (ms, note) = launch(group)
            print("\(group[0].appName): \(note); \(ms.map { "\(group.count) window(s) after \(fmt($0, 0)) ms" } ?? "windows didn't all appear within 10 s")")
        } else {
            // Running: reopen the documents whose windows are gone.
            let present = match(group).filter(isCorrect).map(\.slot.title)
            let missing = group.filter { !present.contains($0.title) && $0.document != nil }
            if !missing.isEmpty {
                let (ms, note) = launch(missing)
                print("\(group[0].appName): running; reopened \(missing.count) document(s): \(note), \(ms.map { "\(fmt($0, 0)) ms" } ?? "timed out")")
            } else {
                print("\(group[0].appName): running")
            }
        }
    }
    report.section("Matches")
    let matches = match(slots)
    let correct = printMatches(matches)
    for m in matches { if let w = m.window { setFrame(w, m.slot.frame) } }
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    var placed = 0
    for m in matches {
        guard let w = m.window, let f = AX.frame(w.element) else { continue }
        if abs(f.minX - m.slot.frame.minX) <= 2 && abs(f.minY - m.slot.frame.minY) <= 2 { placed += 1 }
    }
    let total = (ContinuousClock.now - start).milliseconds
    report.section("Results")
    let rate = Double(correct) / Double(max(slots.count, 1)) * 100
    report.check("Correct match", passed: rate >= 90, "\(correct)/\(slots.count) (\(fmt(rate, 1))%)")
    print("placed at the saved position: \(placed)/\(matches.filter { $0.window != nil }.count); whole restore \(fmt(total, 0)) ms")
    report.finish()
} else {
    print("Usage: s5-restore --inspect | --save <file> | --match <file> | --restore <file>")
    exit(2)
}
