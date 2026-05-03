import Testing
import AppKit
@testable import LingoPulseApp

@Suite struct QuickActionTests {

    @Test func allCasesCountIsFive() {
        #expect(QuickAction.allCases.count == 5)
    }

    @Test func allCasesHaveNonEmptyLabelAndSystemImage() {
        for action in QuickAction.allCases {
            #expect(!action.label.isEmpty)
            #expect(!action.systemImage.isEmpty)
        }
    }

    @Test func shortcutHintMatchesRawValue() {
        for action in QuickAction.allCases {
            #expect(action.shortcutHint == String(action.rawValue))
        }
    }

    @Test func rawValueInitForValidRange() {
        #expect(QuickAction(rawValue: 1) == .preview)
        #expect(QuickAction(rawValue: 2) == .refine)
        #expect(QuickAction(rawValue: 3) == .tone)
        #expect(QuickAction(rawValue: 4) == .quickRefine)
        #expect(QuickAction(rawValue: 5) == .undo)
    }

    @Test func rawValueInitForOutOfRange() {
        #expect(QuickAction(rawValue: 0) == nil)
        #expect(QuickAction(rawValue: 6) == nil)
    }
}

@Suite @MainActor struct QuickActionPanelViewModelTests {

    @Test func initialHighlightIsFirst() {
        let vm = QuickActionPanelViewModel()
        #expect(vm.highlightedIndex == 0)
        #expect(vm.highlighted == .preview)
    }

    @Test func moveDownWraps() {
        let vm = QuickActionPanelViewModel()
        for _ in 0..<5 { vm.moveDown() }
        #expect(vm.highlightedIndex == 0)
    }

    @Test func moveUpWraps() {
        let vm = QuickActionPanelViewModel()
        vm.moveUp()
        #expect(vm.highlightedIndex == QuickAction.allCases.count - 1)
    }

    @Test func moveDownAdvances() {
        let vm = QuickActionPanelViewModel()
        vm.moveDown()
        #expect(vm.highlighted == .refine)
        vm.moveDown()
        #expect(vm.highlighted == .tone)
    }
}

@Suite @MainActor struct QuickActionPanelSmokeTests {

    @Test func constructShowCloseSmokeNoCrash() async {
        let panel = QuickActionPanel()
        panel.show(anchor: nil, onPick: { _ in })
        panel.close()
        panel.close()
    }

    @Test func showTwiceReplacesCallback() async {
        let panel = QuickActionPanel()
        var firstFired = false
        var secondFired = false
        panel.show(anchor: nil, onPick: { _ in firstFired = true })
        panel.show(anchor: nil, onPick: { _ in secondFired = true })
        panel.close()
        #expect(firstFired == true)
        #expect(secondFired == true)
    }
}
