import AppKit
import CoreGraphics
import ScreenCaptureKit
import SegueCore

/// Captures window images with ScreenCaptureKit (docs/SPEC.md §9 `SnapshotService`), adapted
/// from spikes/Sources/s4-capture/main.swift. A capture costs about 34 ms whatever its size
/// and the system mostly serializes them (S4), so this takes one at a time, in the order
/// asked. Images are handed to the caller and never written anywhere. Needs Screen Recording.
public actor SnapshotService {
    public typealias Delivery = @MainActor @Sendable (WindowID, CGImage, Double) -> Void

    private let deliver: Delivery
    private var queue: [(id: WindowID, size: (width: Double, height: Double))] = []
    private var running = false
    private var windows: [WindowID: SCWindow] = [:]
    private var contentFetchedAt: ContinuousClock.Instant?
    public private(set) var captureMs: [Double] = []
    public private(set) var blankCount = 0

    /// `deliver` gets each image with the capture time in milliseconds.
    public init(deliver: @escaping Delivery) {
        self.deliver = deliver
    }

    public static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Replaces the queue with these windows, in order. `sizes` are the windows' sizes in points.
    public func request(_ ids: [WindowID], sizes: [WindowID: CGSize]) {
        queue = ids.compactMap { id in sizes[id].map { (id, (Double($0.width), Double($0.height))) } }
        guard !running, !queue.isEmpty else { return }
        running = true
        Task { await drain() }
    }

    /// Appends one window, for the capture after a switch.
    public func requestOne(_ id: WindowID, size: CGSize) {
        queue.removeAll { $0.id == id }
        queue.append((id, (Double(size.width), Double(size.height))))
        guard !running else { return }
        running = true
        Task { await drain() }
    }

    public func cancelAll() {
        queue.removeAll()
    }

    private func drain() async {
        defer { running = false }
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard Self.isAllowed else { queue.removeAll(); return }
            guard let window = await scWindow(next.id) else { continue }
            let pixels = PreviewRefresh.pixelSize(windowSize: next.size)
            let config = SCStreamConfiguration()
            config.width = pixels.width
            config.height = pixels.height
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let start = ContinuousClock.now
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                       configuration: config)
                let ms = (ContinuousClock.now - start).milliseconds
                captureMs.append(ms)
                if captureMs.count > 500 { captureMs.removeFirst(100) }
                // Failed captures of off-screen windows usually come back all black.
                guard Self.hasContent(image) else {
                    blankCount += 1
                    continue
                }
                await deliver(next.id, image, ms)
            } catch {
                Log.snapshots.debug("capture \(next.id) failed: \(error.localizedDescription, privacy: .public)")
                windows[next.id] = nil
            }
        }
    }

    /// ScreenCaptureKit's window object for an ID, refreshing the shareable content (tens of
    /// milliseconds) at most once a second when a window is unknown.
    private func scWindow(_ id: WindowID) async -> SCWindow? {
        if let window = windows[id] { return window }
        if let fetched = contentFetchedAt, ContinuousClock.now - fetched < .seconds(1) { return nil }
        contentFetchedAt = .now
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return nil }
        windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        return windows[id]
    }

    /// Whether the image has any visible, non-black content, from a 16 × 16 thumbnail.
    static func hasContent(_ image: CGImage) -> Bool {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }
    }
}
