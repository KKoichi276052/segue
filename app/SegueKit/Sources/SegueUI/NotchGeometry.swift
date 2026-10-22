import AppKit

/// Where the notch is, or where a virtual one goes (docs/SPEC.md §6.10), adapted from
/// spikes/Sources/s6-panel/main.swift.
public enum NotchGeometry {
    /// The notch in global Cocoa coordinates, from the unobscured areas either side of it.
    public static func notch(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        let height = screen.safeAreaInsets.top
        return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// The real notch, or a virtual one: a black tab at the top center, as tall as the menu bar.
    public static func anchor(on screen: NSScreen) -> (rect: CGRect, isVirtual: Bool) {
        if let notch = notch(on: screen) { return (notch, false) }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBar >= 20 ? menuBar : 32
        let width: CGFloat = 200
        return (CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), true)
    }

    /// The screen that contains most of a rect given in Accessibility coordinates (top-left
    /// origin of the primary display, y down), such as a window's frame.
    public static func screen(containingAXRect rect: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoa = CGRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
        return NSScreen.screens.max { a, b in area(a.frame.intersection(cocoa)) < area(b.frame.intersection(cocoa)) }
            .flatMap { area($0.frame.intersection(cocoa)) > 0 ? $0 : nil }
    }

    public static func screenWithPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}
