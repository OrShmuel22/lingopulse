import AppKit

@MainActor
protocol ReviewPresenting {
    func present(
        result: RefineResult,
        in app: AppKind,
        onAccept: @escaping ([Int]) -> Void,
        onDismiss: @escaping (Int) -> Void
    )
    func dismiss()
}

@MainActor
final class ReviewPresenter: ReviewPresenting {
    private let panel = ReviewPanel()
    private var currentResult: RefineResult?

    func present(
        result: RefineResult,
        in app: AppKind,
        onAccept: @escaping ([Int]) -> Void,
        onDismiss: @escaping (Int) -> Void
    ) {
        currentResult = result
        panel.onAcceptSafe = { indices in onAccept(indices) }
        panel.onAcceptAll = { indices in onAccept(indices) }
        panel.onDismissAll = { onDismiss(result.edits.count) }
        panel.onAcceptIndex = { _ in }
        panel.onRejectIndex = { _ in }
        panel.show(result: result)
    }

    func dismiss() {
        panel.hide()
        currentResult = nil
    }
}
