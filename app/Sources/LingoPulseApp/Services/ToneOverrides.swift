import Foundation

@MainActor
final class ToneOverrides {
    private let defaults: UserDefaults
    private let key = "lp.toneOverrides"  // [String: String] dict — app → tone

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func tone(for app: String) -> String? {
        let dict = defaults.dictionary(forKey: key) as? [String: String]
        return dict?[app]
    }

    func setTone(_ tone: String, for app: String) {
        var dict = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        dict[app] = tone
        defaults.set(dict, forKey: key)
    }
}
