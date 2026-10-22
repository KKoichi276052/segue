import AppKit
import ScreenCaptureKit
import SpikeKit
import CoreMedia

// S4 Window images (docs/SPEC.md §10).
// Pass when: 15 ms or less per capture at preview size; cache for about 20 images at 60 MB or less.
// Also records whether minimized, hidden-app and other-Space windows can be captured.
//
// Usage:
//   s4-capture                      capture up to 20 windows
//   s4-capture --count <n>          number of windows to cache (default 20)
//   s4-capture --pixel-scale <x>    image pixels per window point (default 0.7: the preview is
//                                   about 70% of screen size, kept at 1× density to stay small)
//
// Single captures cost about 30 ms each regardless of size, so it also measures two ways
// around that: capturing every window at once, and keeping an SCStream per window.

// ScreenCaptureKit asserts unless the process has a Window Server connection, which a bare
// command-line tool only gets once AppKit is set up.
_ = NSApplication.shared

let args = Arguments()
let report = Report("S4 Window images")
print(Permissions.describe())
guard Permissions.screenRecording(prompt: true) else {
    report.check("Capture", passed: nil, "needs Screen Recording. \(Permissions.hint)")
    report.finish()
    exit(1)
}

let count = args.int("count") ?? 20
let pixelScale = args.value("pixel-scale").flatMap(Double.init) ?? 0.7
let axTrusted = Permissions.accessibility(prompt: false)

let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
let regularPIDs = Set(WindowList.regularApps().map(\.processIdentifier))
let ownPID = ProcessInfo.processInfo.processIdentifier
let windows = content.windows.filter {
    $0.windowLayer == 0 && $0.frame.width >= 100 && $0.frame.height >= 100
        && ($0.owningApplication.map { regularPIDs.contains($0.processID) && $0.processID != ownPID } ?? false)
}

// Minimized state comes from Accessibility, when available.
var minimizedIDs: Set<CGWindowID> = []
if axTrusted {
    minimizedIDs = Set(WindowList.axWindows().filter(\.isMinimized).compactMap(\.windowID))
}

enum WindowState: String, CaseIterable {
    case onScreen = "on screen"
    case minimized
    case hiddenApp = "app hidden"
    case otherSpace = "off screen (other Space?)"
}

@MainActor func state(of w: SCWindow) -> WindowState {
    if w.isOnScreen { return .onScreen }
    if minimizedIDs.contains(w.windowID) { return .minimized }
    if let pid = w.owningApplication?.processID, NSRunningApplication(processIdentifier: pid)?.isHidden == true { return .hiddenApp }
    return .otherSpace
}

/// Draws the image into a tiny bitmap and reports whether it has any visible, non-black content.
func hasContent(_ image: CGImage) -> Bool {
    let side = 16
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }
}

@MainActor func capture(_ w: SCWindow) async throws -> CGImage {
    let config = SCStreamConfiguration()
    config.width = max(1, Int(w.frame.width * pixelScale))
    config.height = max(1, Int(w.frame.height * pixelScale))
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: config)
}

// Prefer a mix of states so each kind gets tried, then fill up with on-screen windows.
var picked: [SCWindow] = []
for s in WindowState.allCases.reversed() {
    picked += windows.filter { state(of: $0) == s }.prefix(s == .onScreen ? count : 4)
}
picked = Array(picked.prefix(count))

report.section("Captures (\(picked.count) windows, pixel scale \(pixelScale))")
let rssBefore = residentMemory()
var cache: [CGWindowID: CGImage] = [:]
var coldSamples: [Double] = []
var warmSamples: [Double] = []
var byState: [WindowState: (tried: Int, ok: Int, blank: Int)] = [:]

for w in picked {
    let s = state(of: w)
    let name = "\(w.owningApplication?.applicationName ?? "?") “\((w.title ?? "").prefix(30))”"
    byState[s, default: (0, 0, 0)].tried += 1
    do {
        let (image, cold) = try await measure { try await capture(w) }
        let (_, warm) = try await measure { try await capture(w) }
        coldSamples.append(cold)
        warmSamples.append(warm)
        let visible = hasContent(image)
        if visible { byState[s]!.ok += 1 } else { byState[s]!.blank += 1 }
        cache[w.windowID] = image
        print("\(columns([("\(w.windowID)", 7), (s.rawValue, 26), ("\(image.width)×\(image.height)", 11)])) cold \(fmt(cold)) · warm \(fmt(warm)) ms\(visible ? "" : " · BLANK") · \(name)")
    } catch {
        print("\(columns([("\(w.windowID)", 7), (s.rawValue, 26)])) FAILED: \(error.localizedDescription) · \(name)")
    }
}
let rssAfter = residentMemory()
let imageBytes = cache.values.reduce(0) { $0 + $1.bytesPerRow * $1.height }

report.section("States")
for s in WindowState.allCases {
    guard let r = byState[s] else { print("\(s.rawValue): none to try"); continue }
    print("\(s.rawValue): \(r.ok)/\(r.tried) captured with content, \(r.blank) blank, \(r.tried - r.ok - r.blank) failed")
}
if !axTrusted { print("(Accessibility missing, so minimized windows are counted as other-Space.)") }

report.section("Strategies")
// 1. Parallel: request every picked window at once and time the whole batch.
var parallelSamples: [Double] = []
for _ in 0..<3 {
    let start = ContinuousClock.now
    let tasks = picked.map { w in Task { @MainActor in _ = try? await capture(w) } }
    for t in tasks { await t.value }
    parallelSamples.append((ContinuousClock.now - start).milliseconds)
}
if let s = Stats(parallelSamples) {
    print("parallel, \(picked.count) windows at once: batch \(s.summary); \(fmt(s.median / Double(max(picked.count, 1)))) ms per window")
}

// 2. Streams: one SCStream per window. Time to start it and to its first complete frame,
// then how often frames arrive while nothing is touched (a still window sends few).
final class FrameCatcher: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [ContinuousClock.Instant] = []
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete
        else { return }
        lock.withLock { frames.append(.now) }
    }
    var times: [ContinuousClock.Instant] { lock.withLock { frames } }
}

var startSamples: [Double] = []
var firstFrameSamples: [Double] = []
var noFrame: [String] = []
var idleFrames: [Int] = []
for w in picked.prefix(6) {
    let config = SCStreamConfiguration()
    config.width = max(1, Int(w.frame.width * pixelScale))
    config.height = max(1, Int(w.frame.height * pixelScale))
    config.showsCursor = false
    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    let catcher = FrameCatcher()
    let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: w), configuration: config, delegate: nil)
    let name = "\(w.windowID) \(w.owningApplication?.applicationName ?? "?") (\(state(of: w).rawValue))"
    do {
        try stream.addStreamOutput(catcher, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
        let t0 = ContinuousClock.now
        try await stream.startCapture()
        startSamples.append((ContinuousClock.now - t0).milliseconds)
        try await Task.sleep(for: .seconds(1))
        try? await stream.stopCapture()
        let times = catcher.times
        if let first = times.first {
            firstFrameSamples.append((first - t0).milliseconds)
            idleFrames.append(times.count)
        } else {
            noFrame.append(name)
        }
    } catch {
        noFrame.append("\(name): \(error.localizedDescription)")
    }
}
if let s = Stats(startSamples) { print("stream start: \(s.summary)") }
if let s = Stats(firstFrameSamples) { print("stream first frame after start: \(s.summary)") }
if !idleFrames.isEmpty { print("complete frames in the first second, window untouched: \(idleFrames.map(String.init).joined(separator: ", "))") }
if !noFrame.isEmpty { print("no frame within 1 s:"); noFrame.forEach { print("  \($0)") } }
print("A running stream holds its latest frame, so reading it costs nothing; the cost is in keeping streams open.")

report.section("Results")
if let s = Stats(warmSamples), let c = Stats(coldSamples) {
    print("cold: \(c.summary)")
    report.check("Capture time", passed: s.median <= 15, "warm \(s.summary)")
} else {
    report.check("Capture time", passed: false, "no captures succeeded")
}
let imageMB = Double(imageBytes) / 1_048_576
let rssMB = Double(Int64(rssAfter) - Int64(rssBefore)) / 1_048_576
let projected20 = cache.isEmpty ? 0 : imageMB / Double(cache.count) * 20
report.check("Cache memory", passed: projected20 <= 60,
             "\(cache.count) images use \(fmt(imageMB, 1)) MB of pixels (projected \(fmt(projected20, 1)) MB for 20); process memory grew \(fmt(rssMB, 1)) MB")
report.finish()
