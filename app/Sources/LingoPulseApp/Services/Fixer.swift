import Foundation

struct FixerResult: Equatable {
    let original: String
    let refined: String
    let app: String
}

enum FixerError: Error, Equatable {
    case emptySelection
    case ollama(OllamaError)
    case protection(String)
}

@MainActor
final class Fixer {
    let ollama: OllamaService
    let config: AppConfig
    let history: HistoryStore
    let ring: RingBuffer
    let spellCheck: SpellChecking?

    init(ollama: OllamaService,
         config: AppConfig,
         history: HistoryStore,
         ring: RingBuffer,
         spellCheck: SpellChecking? = nil) {
        self.ollama = ollama
        self.config = config
        self.history = history
        self.ring = ring
        self.spellCheck = spellCheck
    }

    /// `onToken` enables streaming: when non-nil, tokens are forwarded as they
    /// arrive from Ollama. The returned `FixerResult` still contains the full
    /// refined text. UI surfaces that want incremental render should pass a
    /// closure; callers that only need the final string can leave it nil.
    func refine(
        selection: String,
        app: String,
        toneOverride: String? = nil,
        onToken: (@MainActor (String) -> Void)? = nil
    ) async throws -> FixerResult {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FixerError.emptySelection }

        let tone = toneOverride ?? Prompts.tone(forApp: app, selection: trimmed, config: config)
        let protected = Protection.protect(trimmed)
        var preCorrected = protected.redacted
        var spellEdits: [SpellCorrection] = []
        let spellEnabled: Bool = config.value(at: "spell_check.enabled") ?? true
        if spellEnabled, let spell = spellCheck {
            let result = spell.correct(protected.redacted)
            preCorrected = result.corrected
            spellEdits = result.edits
            if !spellEdits.isEmpty {
                let summary = spellEdits.map { "\($0.original)→\($0.corrected)" }.joined(separator: ", ")
                Log.info("SpellCheck pre-pass corrected \(spellEdits.count) word(s): \(summary)")
            }
        }
        let prefs = Preferences.shared
        let prompt = Prompts.buildFixerPrompt(
            app: app,
            tone: tone,
            message: preCorrected,
            promptOverride: prefs.fixerPromptOverride,
            toneOverrides: prefs.toneOverrides
        )

        let modelFromConfig: String = config.value(at: "fixer.model") ?? "gemma3:1b-it-qat"
        let model: String = prefs.fixerModel ?? modelFromConfig
        Log.info("refine using model=\(model) (override=\(prefs.fixerModel != nil))")
        let keepAlive: String = config.value(at: "keepalive.ollama_keep_alive") ?? "30m"
        let timeout: Double = {
            if let t: Int = config.value(at: "fixer.timeout_seconds") { return Double(t) }
            return 15.0
        }()

        // Cap generation length: refined output is rarely longer than ~1.7x input.
        // Floor of 64 covers very short selections; ceiling of 2048 keeps a safety
        // net for pathological inputs without leaving generation unbounded.
        let predictCap = min(2048, max(64, (preCorrected.count * 5) / 3))

        // Editing-mode sampling: deterministic, narrow distribution, no repeat penalty.
        // Repeat penalty > 1.0 actively breaks the minimum-edit principle by causing
        // the model to rephrase correct repeated words. top_k caps the candidate set
        // to high-confidence picks ("only edit when sure").
        let options: [String: Any] = [
            "temperature": 0.1,
            "top_p": 0.9,
            "top_k": 40,
            "repeat_penalty": 1.0,
            "num_predict": predictCap,
            "stop": ["\nInput:", "\n\n", "\nOutput:"],
        ]

        let response: String
        let generateStart = Date()
        do {
            if let onToken {
                response = try await ollama.generateStream(
                    model: model,
                    prompt: prompt,
                    keepAlive: keepAlive,
                    timeout: timeout,
                    options: options,
                    onToken: onToken
                )
            } else {
                response = try await ollama.generate(
                    model: model,
                    prompt: prompt,
                    keepAlive: keepAlive,
                    timeout: timeout,
                    options: options
                )
            }
        } catch let err as OllamaError {
            throw FixerError.ollama(err)
        }
        let durationMs = Int(Date().timeIntervalSince(generateStart) * 1000)

        let refined: String
        do {
            refined = try Protection.restore(response.trimmingCharacters(in: .whitespacesAndNewlines), tokens: protected.tokens)
        } catch let err as ProtectionError {
            switch err {
            case .placeholderMissing(let ph):
                throw FixerError.protection("placeholder missing: \(ph)")
            }
        } catch {
            throw FixerError.protection(error.localizedDescription)
        }

        let timestamp = isoNow()
        do {
            try await ring.append([
                "original": trimmed,
                "refined": refined,
                "app": app,
                "timestamp": timestamp,
            ])
        } catch {
            Log.error("Fixer: failed to append to ring: \(error)")
        }

        do {
            try await history.append([
                "mode": "fixer_refine",
                "app": app,
                "original": trimmed,
                "refined": refined,
                "spell_edits": spellEdits.count,
                "model": model,
                "tone": tone,
                "duration_ms": durationMs,
                "original_chars": trimmed.count,
                "refined_chars": refined.count,
            ])
        } catch {
            Log.error("Fixer: failed to append to history: \(error)")
        }

        return FixerResult(original: trimmed, refined: refined, app: app)
    }

    func alreadyRefined(_ selection: String) async -> Bool {
        let entries = (try? await ring.listAll()) ?? []
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterNoFrac = ISO8601DateFormatter()

        for entry in entries {
            guard entry["refined"] as? String == selection else { continue }
            guard let tsStr = entry["timestamp"] as? String else { continue }
            let ts = formatter.date(from: tsStr) ?? formatterNoFrac.date(from: tsStr)
            guard let ts else { continue }
            if now.timeIntervalSince(ts) <= 30 { return true }
        }
        return false
    }

    private func isoNow() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date())
    }
}
