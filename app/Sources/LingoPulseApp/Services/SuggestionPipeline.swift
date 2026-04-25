import Foundation

@MainActor
protocol SuggestionPipelining {
    func requestSuggestions(for selection: Selection) async throws -> RefineResult?
    func applyAccepted(original: String, refined: String, indices: [Int]) async throws -> String
    func sendDismissalFeedback(input: String, rejected: String, app: AppKind, dismissedCount: Int) async
    func cancelInFlight()
}

@MainActor
final class SuggestionPipeline: SuggestionPipelining {
    private let daemon: DaemonClient
    private var currentTask: Task<RefineResult?, Error>?

    init(daemon: DaemonClient) {
        self.daemon = daemon
    }

    func requestSuggestions(for selection: Selection) async throws -> RefineResult? {
        currentTask?.cancel()
        let task = Task<RefineResult?, Error> { [daemon] in
            let resp = try await daemon.refine(selection: selection.text, app: selection.appName, toneOverride: nil)
            try Task.checkCancellation()
            guard !resp.edits.isEmpty else { return nil }
            return RefineResult(original: resp.original, refined: resp.refined, edits: resp.edits)
        }
        currentTask = task
        return try await task.value
    }

    func applyAccepted(original: String, refined: String, indices: [Int]) async throws -> String {
        let resp = try await daemon.applyEdits(original: original, refined: refined, acceptedIndices: indices)
        return resp.result
    }

    func sendDismissalFeedback(input: String, rejected: String, app: AppKind, dismissedCount: Int) async {
        _ = try? await daemon.feedback(
            input: input,
            rejected: rejected,
            reason: FeedbackReason.other.rawValue,
            app: app.rawValue,
            tone: "",
            note: "dismissed \(dismissedCount) edits via Esc"
        )
    }

    func cancelInFlight() {
        currentTask?.cancel()
        currentTask = nil
    }
}
