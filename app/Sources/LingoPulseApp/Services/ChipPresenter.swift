import AppKit
import ApplicationServices

enum ChipAction {
    case acceptCurrent(index: Int, isLast: Bool)
    case dismissed(dismissedCount: Int)
    case cycleNext
    case cyclePrev
    case neverFix(token: String, scope: String)
}

@MainActor
protocol ChipPresenting {
    func present(
        result: RefineResult,
        in app: AppKind,
        near element: AXUIElement?,
        onAction: @escaping (ChipAction) -> Void
    )
    func dismiss()
    func chipState() -> (original: String, refined: String, acceptedIndices: Set<Int>)
}

@MainActor
final class ChipPresenter: ChipPresenting {
    private let chip = SuggestionChip()
    private let keyMonitor = KeyMonitor()

    func present(
        result: RefineResult,
        in app: AppKind,
        near element: AXUIElement?,
        onAction: @escaping (ChipAction) -> Void
    ) {
        chip.configure(edits: result.edits, original: result.original, refined: result.refined)
        chip.currentApp = app.rawValue
        chip.onNeverFix = { token, scope in
            onAction(.neverFix(token: token, scope: scope))
        }
        chip.show(near: element)

        keyMonitor.onTab = { [weak self] in
            guard let self = self else { return }
            let isLast = self.chip.acceptCurrent()
            onAction(.acceptCurrent(index: self.chip.currentIndex, isLast: isLast))
        }
        keyMonitor.onEsc = { [weak self] in
            guard let self = self else { return }
            onAction(.dismissed(dismissedCount: self.chip.dismissedCount))
            self.dismiss()
        }
        keyMonitor.onArrowDown = { [weak self] in
            self?.chip.cycleNext()
            onAction(.cycleNext)
        }
        keyMonitor.onArrowUp = { [weak self] in
            self?.chip.cyclePrev()
            onAction(.cyclePrev)
        }
        keyMonitor.onOtherKey = { [weak self] in
            self?.dismiss()
        }
        keyMonitor.start()
    }

    func dismiss() {
        chip.hide()
        keyMonitor.stop()
    }

    func chipState() -> (original: String, refined: String, acceptedIndices: Set<Int>) {
        (chip.originalText, chip.refinedText, chip.acceptedIndices)
    }
}
