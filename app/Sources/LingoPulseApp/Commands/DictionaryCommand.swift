import Foundation

@MainActor
final class DictionaryCommand {
    private let ollama: OllamaService
    private let config: AppConfig
    private let accessibility: AccessibilityServicing

    init(ollama: OllamaService, config: AppConfig, accessibility: AccessibilityServicing) {
        self.ollama = ollama
        self.config = config
        self.accessibility = accessibility
    }

    func execute() async {
        let query = await accessibility.readOrFallback()?.text
        guard let q = query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else {
            Notifications.show(title: "LingoPulse", body: "Select a word or description first.")
            return
        }

        let prompt = Dictionary.buildPrompt(query: q)
        let modelFromConfig = config.value(at: "dictionary.model", as: String.self) ?? "gemma3:1b-it-qat"
        let model = Preferences.shared.dictionaryModel ?? modelFromConfig
        let timeout = config.value(at: "dictionary.timeout_seconds", as: Double.self) ?? 15.0

        do {
            let raw = try await ollama.generate(
                model: model,
                prompt: prompt,
                keepAlive: "30m",
                format: Dictionary.jsonSchema,
                timeout: timeout
            )
            let candidates = Dictionary.parseResponse(raw)

            if candidates.isEmpty {
                Notifications.show(title: "LingoPulse", body: "No candidates found.")
                return
            }

            await DictionaryPanel().show(query: q, candidates: candidates)
        } catch {
            Log.error("dictionary error: \(error)")
            Notifications.show(title: "LingoPulse", body: "Dictionary failed: \(error)")
        }
    }
}
