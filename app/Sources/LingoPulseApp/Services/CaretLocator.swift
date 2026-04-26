import AppKit
import ApplicationServices

enum CaretLocator {
    /// Returns the caret rect (screen coordinates) for the given element,
    /// falling back to element frame, then mouse position.
    static func locate(in element: AXUIElement) -> CGRect? {
        if let rect = caretRect(in: element) { return rect }
        if let rect = elementFrame(of: element) { return rect }
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y, width: 1, height: 16)
    }

    private static func caretRect(in element: AXUIElement) -> CGRect? {
        var rangeRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRaw) == .success,
              let axValue = rangeRaw, CFGetTypeID(axValue as CFTypeRef) == AXValueGetTypeID() else { return nil }

        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(axValue as! AXValue, .cfRange, &range)

        var rangeForBounds = range
        let rangeAX = AXValueCreate(.cfRange, &rangeForBounds)!
        var boundsRaw: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAX,
            &boundsRaw
        ) == .success else { return nil }

        guard let boundsVal = boundsRaw, CFGetTypeID(boundsVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var bounds = CGRect.zero
        AXValueGetValue(boundsVal as! AXValue, .cgRect, &bounds)
        return bounds
    }

    private static func elementFrame(of element: AXUIElement) -> CGRect? {
        var posRaw: AnyObject?
        var sizeRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRaw) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success else { return nil }

        guard let posVal = posRaw, CFGetTypeID(posVal as CFTypeRef) == AXValueGetTypeID(),
              let sizeVal = sizeRaw, CFGetTypeID(sizeVal as CFTypeRef) == AXValueGetTypeID() else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }
}
