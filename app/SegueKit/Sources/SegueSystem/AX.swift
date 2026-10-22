import ApplicationServices
import CoreGraphics

// Accessibility helpers, adapted from spikes/Sources/SpikeKit/Windows.swift.
public enum AX {
    public static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// The element's frame in Accessibility coordinates (origin at the top left of the
    /// primary display, y pointing down), the same space as the Window Server's bounds.
    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    public static func setBool(_ element: AXUIElement, _ name: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value as CFBoolean)
    }

    @discardableResult
    public static func perform(_ element: AXUIElement, _ action: String) -> AXError {
        AXUIElementPerformAction(element, action as CFString)
    }

    /// Sets the messaging timeout for every element, so one frozen app can't stall Segue
    /// (docs/SPEC.md §8 Reliability).
    public static func setGlobalTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }
}
