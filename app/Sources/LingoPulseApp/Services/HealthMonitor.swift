import AppKit
import ApplicationServices

@MainActor
final class HealthMonitor {
    private let ollama: OllamaService
    private var task: Task<Void, Never>?
    private var current: AppHealth = .ok
    var onChange: ((AppHealth) -> Void)?

    init(ollama: OllamaService) {
        self.ollama = ollama
    }

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func tick() async {
        let h: AppHealth
        if !AXIsProcessTrusted() {
            h = .axRevoked
        } else if await !daemonReachable() {
            h = .daemonDown
        } else {
            h = .ok
        }
        if h != current {
            Log.info("HealthMonitor: \(current) -> \(h)")
            current = h
            onChange?(h)
        }
    }

    private func daemonReachable() async -> Bool {
        do {
            _ = try await ollama.listModels(timeout: 2.0)
            return true
        } catch {
            return false
        }
    }
}
