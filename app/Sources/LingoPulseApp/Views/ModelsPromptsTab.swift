import SwiftUI

struct ModelsPromptsTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            ModelsSectionView(prefs: prefs)
            FixerPromptSectionView(prefs: prefs)
            TonesSectionView(prefs: prefs)
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
    }
}

// MARK: - Section A: Models

private struct ModelsSectionView: View {
    @ObservedObject var prefs: Preferences
    @State private var models: [OllamaModelInfo] = []
    @State private var loadError: String? = nil
    @State private var isLoading = false

    private var statusText: String {
        if let err = loadError { return err }
        if isLoading { return "Loading..." }
        if models.isEmpty { return "No models found" }
        let totalGB = Double(models.reduce(0) { $0 + $1.size }) / 1_073_741_824
        return "\(models.count) model(s) found, \(String(format: "%.1f", totalGB)) GB total"
    }

    var body: some View {
        Section(header: Text("Models")) {
            HStack {
                Picker("Refine model", selection: Binding(
                    get: { prefs.fixerModel ?? "" },
                    set: { prefs.fixerModel = $0.isEmpty ? nil : $0 }
                )) {
                    Text("(Use config default)").tag("")
                    ForEach(models, id: \.name) { m in
                        Text(m.name).tag(m.name)
                    }
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh model list from Ollama")
            }

            if let err = loadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await loadModels() }
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadModels() }
    }

    private func loadModels() async {
        isLoading = true
        loadError = nil
        let svc = OllamaService()
        do {
            models = try await svc.listModels()
            isLoading = false
        } catch {
            isLoading = false
            loadError = "Couldn't reach Ollama — is `ollama serve` running?"
        }
    }
}

// MARK: - Section B: Fixer Prompt

private struct FixerPromptSectionView: View {
    @ObservedObject var prefs: Preferences
    @State private var draft: String = ""
    @State private var showPreview = false
    @State private var debouncer = Debouncer()

    var body: some View {
        Section(header: Text("Fixer prompt")) {
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .onChange(of: draft) { _, newValue in
                    debouncer.schedule { prefs.fixerPromptOverride = newValue }
                }

            HStack {
                Spacer()
                Button("Reset to default") {
                    prefs.fixerPromptOverride = nil
                    draft = Prompts.fixerTemplate
                }
                .buttonStyle(.borderless)

                Button(showPreview ? "Hide preview" : "Show preview") {
                    showPreview.toggle()
                }
                .buttonStyle(.borderless)
            }

            if showPreview {
                PromptPreviewView(template: draft)
            }
        }
        .onAppear {
            draft = prefs.fixerPromptOverride ?? Prompts.fixerTemplate
        }
    }
}

private struct PromptPreviewView: View {
    let template: String

    private var rendered: String {
        Prompts.buildFixerPrompt(
            app: "Mail",
            tone: "Neutral",
            message: "Hello, world.",
            promptOverride: template
        )
    }

    var body: some View {
        DisclosureGroup("Preview (Mail / Neutral / \"Hello, world.\")") {
            ScrollView {
                Text(rendered)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(4)
        }
    }
}

// MARK: - Section C: Tone Descriptions

private struct TonesSectionView: View {
    @ObservedObject var prefs: Preferences
    @State private var drafts: [String: String] = [:]
    @State private var debouncer = Debouncer()

    private var sortedTones: [String] {
        Prompts.toneDescriptions.keys.sorted()
    }

    var body: some View {
        Section(header: Text("Tone descriptions")) {
            DisclosureGroup("Customize tones (\(sortedTones.count))") {
                ForEach(sortedTones, id: \.self) { tone in
                    ToneRowView(
                        tone: tone,
                        draft: Binding(
                            get: { drafts[tone] ?? "" },
                            set: { newVal in
                                drafts[tone] = newVal
                                scheduleToneFlush()
                            }
                        ),
                        placeholder: Prompts.toneDescriptions[tone] ?? "",
                        onReset: {
                            drafts[tone] = ""
                            var updated = prefs.toneOverrides
                            updated.removeValue(forKey: tone)
                            prefs.toneOverrides = updated
                        }
                    )
                }

                HStack {
                    Spacer()
                    Button("Reset all tones") {
                        drafts = [:]
                        prefs.toneOverrides = [:]
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            drafts = prefs.toneOverrides
        }
    }

    private func scheduleToneFlush() {
        debouncer.schedule {
            // Only persist non-empty overrides
            prefs.toneOverrides = drafts.filter { !$0.value.isEmpty }
        }
    }
}

private struct ToneRowView: View {
    let tone: String
    @Binding var draft: String
    let placeholder: String
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tone).bold()
                Spacer()
                if !draft.isEmpty {
                    Button("Reset", action: onReset)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            TextField("Override default…", text: $draft)
                .textFieldStyle(.roundedBorder)
            Text("Default: \(placeholder)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}
