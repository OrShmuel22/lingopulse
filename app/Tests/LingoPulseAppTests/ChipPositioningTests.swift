import Testing
import CoreGraphics
@testable import LingoPulseApp

@Suite struct ChipPositioningTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let panel = CGSize(width: 300, height: 80)

    @Test func elementInMiddle_chipBelow() {
        let element = CGRect(x: 800, y: 400, width: 200, height: 30)  // AX top-left
        let origin = ChipPositioning.computeOrigin(elementBounds: element, panelSize: panel, screenBounds: screen)
        #expect(abs(origin.x - 800) < 1)
        // chip below: cocoaBottomOfElement - panelHeight - 6 = (1080 - 430) - 80 - 6 = 564
        #expect(abs(origin.y - 564) < 1)
    }

    @Test func elementNearRightEdge_chipClampedRight() {
        let element = CGRect(x: 1800, y: 400, width: 200, height: 30)
        let origin = ChipPositioning.computeOrigin(elementBounds: element, panelSize: panel, screenBounds: screen)
        #expect(origin.x + panel.width <= screen.maxX - 8)
    }

    @Test func elementNearLeftEdge_chipClampedLeft() {
        let element = CGRect(x: -50, y: 400, width: 200, height: 30)
        let origin = ChipPositioning.computeOrigin(elementBounds: element, panelSize: panel, screenBounds: screen)
        #expect(origin.x >= screen.minX + 8)
    }

    @Test func elementNearBottomOfScreen_chipPlacedAbove() {
        // Element at AX y=1050 (near visible bottom)
        let element = CGRect(x: 800, y: 1050, width: 200, height: 30)
        let origin = ChipPositioning.computeOrigin(elementBounds: element, panelSize: panel, screenBounds: screen)
        // Chip should be above element. Element top in cocoa: 1080 - 1050 = 30. Plus 6 offset = 36.
        #expect(abs(origin.y - 36) < 1)
    }
}
