import Foundation

@MainActor
final class Debouncer {
    private var task: Task<Void, Never>?
    private let delayMs: Int

    init(delayMs: Int = 500) {
        self.delayMs = delayMs
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
