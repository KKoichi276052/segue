import Foundation

/// A thread with its own run loop for every Accessibility call and observer, so a slow or
/// frozen app never blocks the main thread (docs/SPEC.md §8 Reliability).
final class AXThread: Thread, @unchecked Sendable {
    private let ready = DispatchSemaphore(value: 0)
    private(set) var runLoop: CFRunLoop!

    override init() {
        super.init()
        name = "Segue Accessibility"
        qualityOfService = .userInteractive
        start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A source keeps the run loop alive while nothing else is scheduled.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while !isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    /// Runs `block` on this thread.
    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `block` on this thread after `delay` seconds.
    func perform(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent() + delay, 0, 0, 0) { _ in block() }
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
    }

    /// Runs `block` on this thread and waits for its result. Never call from this thread.
    func sync<T>(_ block: @escaping () -> T) -> T {
        nonisolated(unsafe) var result: T?
        let done = DispatchSemaphore(value: 0)
        perform {
            result = block()
            done.signal()
        }
        done.wait()
        return result!
    }
}
