import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class PersonalDictWindowController: NSWindowController {
    convenience init(daemon: DaemonClient) {
        let host = NSHostingController(rootView: PersonalDictView(daemon: daemon))
        let window = NSWindow(contentViewController: host)
        window.title = "LingoPulse — Personal Dictionary"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        self.init(window: window)
    }
}

struct PersonalDictEntry: Codable, Identifiable, Equatable {
    var id: String { "\(token)|\(scope)" }
    let token: String
    let scope: String
    let added_at: String
}

@MainActor
final class PersonalDictModel: ObservableObject {
    @Published var entries: [PersonalDictEntry] = []
    @Published var newToken: String = ""
    @Published var newScope: String = "*"
    @Published var loading: Bool = false
    @Published var errorMessage: String?

    let daemon: DaemonClient
    init(daemon: DaemonClient) { self.daemon = daemon }

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await daemon.listPersonalDict()
            entries = resp.tokens.sorted { $0.added_at > $1.added_at }
            errorMessage = nil
        } catch {
            errorMessage = "Load failed: \(error)"
        }
    }

    func add() async {
        let t = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            _ = try await daemon.addPersonalDictEntry(token: t, scope: newScope)
            newToken = ""
            await reload()
        } catch {
            errorMessage = "Add failed: \(error)"
        }
    }

    func remove(_ entry: PersonalDictEntry) async {
        do {
            _ = try await daemon.removePersonalDictEntry(token: entry.token, scope: entry.scope)
            await reload()
        } catch {
            errorMessage = "Remove failed: \(error)"
        }
    }
}

struct PersonalDictView: View {
    @StateObject private var model: PersonalDictModel

    init(daemon: DaemonClient) {
        _model = StateObject(wrappedValue: PersonalDictModel(daemon: daemon))
    }

    private let scopeOptions = ["*", "Slack", "Mail", "Jira", "Confluence", "Cursor", "Chrome", "Notes"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tokens listed here will never be flagged for refinement.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("token (e.g. acme-payments)", text: $model.newToken)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $model.newScope) {
                    ForEach(scopeOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 120)
                Button("Add") {
                    Task { await model.add() }
                }
                .disabled(model.newToken.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Button("Export…") { Task { await exportDict() } }
                Button("Import…") { Task { await importDict() } }
                Spacer()
            }

            if let err = model.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Table(model.entries) {
                TableColumn("Token", value: \.token)
                TableColumn("Scope", value: \.scope)
                TableColumn("Added") { entry in
                    Text(entry.added_at.prefix(10))
                }
                TableColumn("") { entry in
                    Button("Remove") {
                        Task { await model.remove(entry) }
                    }
                }
            }
            .frame(minHeight: 240)
        }
        .padding(16)
        .task { await model.reload() }
    }

    private func exportDict() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "lingopulse-dict.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder().encode(model.entries)
            try data.write(to: url)
        } catch {
            model.errorMessage = "Export failed: \(error)"
        }
    }

    private func importDict() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([PersonalDictEntry].self, from: data)
            for entry in entries {
                _ = try await model.daemon.addPersonalDictEntry(token: entry.token, scope: entry.scope)
            }
            await model.reload()
        } catch {
            model.errorMessage = "Import failed: \(error)"
        }
    }
}
