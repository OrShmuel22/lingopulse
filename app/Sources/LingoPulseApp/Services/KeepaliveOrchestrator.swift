import Foundation

@MainActor
final class KeepaliveOrchestrator {
    private let ollama: OllamaService
    private let config: AppConfig
    private var timer: Timer?
    private let keepAliveDuration: String
    private let inactiveKeepAlive: String
    private var lastTickWasActive: Bool = true

    init(ollama: OllamaService, config: AppConfig) {
        self.ollama = ollama
        self.config = config
        self.keepAliveDuration = config.value(at: "keepalive.ollama_keep_alive") ?? "30m"
        self.inactiveKeepAlive = config.value(at: "keepalive.inactive_keep_alive") ?? "5m"
    }

    func start() {
        guard let enabled: Bool = config.value(at: "keepalive.enabled"), enabled else {
            Log.info("KeepaliveOrchestrator: disabled in config")
            return
        }

        let loginWarmup: Bool = config.value(at: "keepalive.login_warmup") ?? true
        if loginWarmup {
            Task { @MainActor in
                await warmup()
            }
        }

        let interval: Int = config.value(at: "keepalive.ping_interval_minutes") ?? 25
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.onTimerTick()
            }
        }
        Log.info("KeepaliveOrchestrator: started (ping interval: \(interval)m, keepAlive: \(keepAliveDuration))")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        Log.info("KeepaliveOrchestrator: stopped")
    }

    private func onTimerTick() async {
        let active = isInActiveHours()
        defer { lastTickWasActive = active }

        if !active {
            // Just transitioned active→inactive: send one ping with short
            // keep_alive so the model unloads soon and frees RAM. After that,
            // skip all pings until we cross back into active hours.
            if lastTickWasActive {
                Log.debug("KeepaliveOrchestrator: leaving active hours, scheduling unload via short keep_alive")
                await ping(keepAlive: inactiveKeepAlive)
            } else {
                Log.debug("KeepaliveOrchestrator: outside active hours, skipping ping")
            }
            return
        }
        await ping(keepAlive: keepAliveDuration)
    }

    private func warmup() async {
        let model = resolveModel()
        Log.info("KeepaliveOrchestrator: warming up model \(model)")
        do {
            _ = try await ollama.generate(
                model: model,
                prompt: "",
                keepAlive: keepAliveDuration,
                timeout: 30.0,
                maxRetries: 1
            )
            Log.info("KeepaliveOrchestrator: model \(model) warmup complete")
        } catch {
            Log.error("KeepaliveOrchestrator: warmup failed for \(model): \(error)")
        }
    }

    private func ping(keepAlive: String) async {
        let model = resolveModel()
        Log.debug("KeepaliveOrchestrator: pinging \(model) (keep_alive=\(keepAlive))")
        do {
            _ = try await ollama.generate(
                model: model,
                prompt: "",
                keepAlive: keepAlive,
                timeout: 10.0,
                maxRetries: 1
            )
            Log.debug("KeepaliveOrchestrator: ping successful for \(model)")
        } catch {
            Log.debug("KeepaliveOrchestrator: ping failed for \(model): \(error)")
        }
    }

    private func resolveModel() -> String {
        let configDefault: String = config.value(at: "fixer.model") ?? "gemma3:1b-it-qat"
        return Preferences.shared.fixerModel ?? configDefault
    }

    private func isInActiveHours() -> Bool {
        let startStr: String = config.value(at: "keepalive.active_hours_start") ?? "08:00"
        let endStr: String = config.value(at: "keepalive.active_hours_end") ?? "22:00"

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        guard let start = formatter.date(from: startStr),
              let end = formatter.date(from: endStr) else {
            Log.error("KeepaliveOrchestrator: failed to parse active hours (\(startStr)-\(endStr))")
            return true
        }

        let nowComponents = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let nowH = nowComponents.hour, let nowM = nowComponents.minute else { return true }
        let nowMinutes = nowH * 60 + nowM

        let startComponents = Calendar.current.dateComponents([.hour, .minute], from: start)
        let endComponents = Calendar.current.dateComponents([.hour, .minute], from: end)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes <= endMinutes
        } else {
            return nowMinutes >= startMinutes || nowMinutes <= endMinutes
        }
    }
}
