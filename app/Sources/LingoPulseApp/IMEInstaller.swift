import Foundation

/// Installs LingoPulseIME.app from the main bundle's Resources/ into
/// ~/Library/Input Methods/ so macOS recognises it as an input method.
class IMEInstaller {

    let fileManager: FileManager
    private let bundleResourceURL: URL?

    init(fileManager: FileManager = .default,
         bundleResourceURL: URL? = Bundle.main.resourceURL) {
        self.fileManager = fileManager
        self.bundleResourceURL = bundleResourceURL
    }

    /// Destination path: ~/Library/Input Methods/LingoPulseIME.app
    var installDestination: URL {
        let inputMethods = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
        return inputMethods.appendingPathComponent("LingoPulseIME.app", isDirectory: true)
    }

    /// Returns true when the bundle is already present at the install destination.
    var isInstalled: Bool {
        fileManager.fileExists(atPath: installDestination.path)
    }

    /// Source path: <MainBundle>/Resources/LingoPulseIME.app
    private var sourceURL: URL? {
        bundleResourceURL?.appendingPathComponent("LingoPulseIME.app", isDirectory: true)
    }

    /// Copies LingoPulseIME.app into ~/Library/Input Methods/.
    /// Removes any pre-existing installation first so the copy is always fresh.
    /// - Throws: if the source bundle is missing or the file operation fails.
    func install() throws {
        guard let source = sourceURL else {
            throw InstallerError.sourceMissing
        }
        guard fileManager.fileExists(atPath: source.path) else {
            throw InstallerError.sourceMissing
        }

        let dest = installDestination
        let destParent = dest.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: destParent.path) {
            try fileManager.createDirectory(at: destParent,
                                            withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: dest.path) {
            try fileManager.removeItem(at: dest)
        }

        try fileManager.copyItem(at: source, to: dest)
    }

    enum InstallerError: Error, LocalizedError {
        case sourceMissing

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "LingoPulseIME.app not found in the main bundle's Resources. " +
                       "Re-install LingoPulse from the original .dmg."
            }
        }
    }
}
