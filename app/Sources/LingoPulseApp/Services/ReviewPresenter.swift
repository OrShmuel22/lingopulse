import AppKit
import ApplicationServices

@MainActor
protocol ReviewPresenting {
    func present(
        result: RefineResult,
        in app: AppKind,
        near element: AXUIElement?,
        onAccept: @escaping ([Int]) -> Void,
        onDismiss: @escaping (Int) -> Void
    )
    func dismiss()
}

@MainActor
final class ReviewPresenter: ReviewPresenting {
    private let panel = ReviewPanel()
    private let keyMonitor = KeyMonitor()
    private var currentState: ReviewPanelState?

    func present(
        result: RefineResult,
        in app: AppKind,
        near element: AXUIElement?,
        onAccept: @escaping ([Int]) -> Void,
        onDismiss: @escaping (Int) -> Void
    ) {
        let state = ReviewPanelState(result: result)
        currentState = state

        state.onAcceptSafe = { [weak self] in
            onAccept(state.safeIndices)
            self?.dismiss()
        }
        state.onAcceptAll = { [weak self] in
            onAccept(Array(0..<result.edits.count))
            self?.dismiss()
        }
        state.onDismissAll = { [weak self] in
            onDismiss(result.edits.count - state.acceptedIndices.count)
            self?.dismiss()
        }

        panel.show(state: state, near: element)

        keyMonitor.onArrowDown = { [weak state] in state?.cursorNext() }
        keyMonitor.onArrowUp = { [weak state] in state?.cursorPrev() }
        keyMonitor.onTab = { [weak state] in state?.toggleCurrent() }
        keyMonitor.onSpace = { [weak state] in state?.toggleCurrent() }
        keyMonitor.onReturn = { [weak state] in state?.onAcceptAll?() }
        keyMonitor.onCommandReturn = { [weak state] in state?.onAcceptSafe?() }
        keyMonitor.onEsc = { [weak self] in
            guard let state = self?.currentState else { return }
            onDismiss(result.edits.count - state.acceptedIndices.count)
            self?.dismiss()
        }
        keyMonitor.start()
    }

    func dismiss() {
        keyMonitor.stop()
        panel.hide()
        currentState = nil
    }
}
