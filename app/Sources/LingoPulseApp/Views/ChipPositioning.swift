import CoreGraphics

enum ChipPositioning {
    static func computeOrigin(
        elementBounds: CGRect,    // top-left origin (AX style)
        panelSize: CGSize,
        screenBounds: CGRect      // bottom-left origin (AppKit style)
    ) -> CGPoint {
        // AX-Y to Cocoa-Y: cocoaY = screenBounds.maxY - axY
        let elementBottomAX = elementBounds.maxY  // AX maxY = top + height
        let elementBottomCocoa = screenBounds.maxY - elementBottomAX
        let panelBottomY = elementBottomCocoa - panelSize.height - Constants.Layout.chipElementOffset

        var x = elementBounds.minX
        if x + panelSize.width > screenBounds.maxX - 8 {
            x = screenBounds.maxX - panelSize.width - 8
        }
        if x < screenBounds.minX + 8 {
            x = screenBounds.minX + 8
        }

        var y = panelBottomY
        if y < screenBounds.minY + 8 {
            let elementTopCocoa = screenBounds.maxY - elementBounds.minY
            y = elementTopCocoa + Constants.Layout.chipElementOffset
        }

        return CGPoint(x: x, y: y)
    }
}
