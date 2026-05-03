import Testing
import AppKit
@testable import LingoPulseApp

@Suite @MainActor struct QuickRefineCapturePanelSmokeTests {

    @Test func constructShowCloseSmokeNoCrash() async {
        let panel = QuickRefineCapturePanel()
        panel.show(onPick: { _ in })
        panel.close()
    }

    @Test func closeWithoutShowIsNoOp() async {
        let panel = QuickRefineCapturePanel()
        panel.close()
    }
}
