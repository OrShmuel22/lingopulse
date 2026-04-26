import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct AppConfigTests {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("config-\(UUID().uuidString).json")
    }

    @Test @MainActor func defaultsReturnedWhenNoFileExists() {
        let url = tempURL()
        let config = AppConfig(configURL: url)
        let model: String? = config.value(at: "fixer.model")
        #expect(model == "gemma3:1b-it-qat")
    }

    @Test @MainActor func fileCreatedAtFirstRead() {
        let url = tempURL()
        _ = AppConfig(configURL: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test @MainActor func fileContainsDefaultsAfterCreation() throws {
        let url = tempURL()
        _ = AppConfig(configURL: url)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json != nil)
        let fixer = json?["fixer"] as? [String: Any]
        #expect(fixer?["model"] as? String == "gemma3:1b-it-qat")
    }

    @Test @MainActor func userOverridesDeepMergeOverDefaults() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let userConfig: [String: Any] = ["fixer": ["model": "custom-model"]]
        let data = try JSONSerialization.data(withJSONObject: userConfig)
        try data.write(to: url)

        let config = AppConfig(configURL: url)
        let model: String? = config.value(at: "fixer.model")
        let timeout: Int? = config.value(at: "fixer.timeout_seconds")
        #expect(model == "custom-model")
        #expect(timeout == 15)
    }

    @Test @MainActor func valueAtFixerModelReturnsString() {
        let config = AppConfig(configURL: tempURL())
        let model: String? = config.value(at: "fixer.model")
        #expect(model == "gemma3:1b-it-qat")
    }

    @Test @MainActor func valueAtToneAppMapSlackReturnsCasual() {
        let config = AppConfig(configURL: tempURL())
        let appMap: [String: String]? = config.value(at: "tone.app_map")
        #expect(appMap?["Slack"] == "Casual")
    }

    @Test @MainActor func valueAtMissingKeyReturnsNil() {
        let config = AppConfig(configURL: tempURL())
        let result: String? = config.value(at: "missing.key")
        #expect(result == nil)
    }

    @Test @MainActor func pathAtHistoryPathExpandsTilde() {
        let config = AppConfig(configURL: tempURL())
        let url = config.path(at: "history.path")
        #expect(url != nil)
        #expect(url?.path.hasPrefix("/") == true)
        #expect(url?.path.contains("~") == false)
    }
}
