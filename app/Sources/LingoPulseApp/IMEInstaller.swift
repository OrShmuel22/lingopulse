import Foundation
import Carbon.HIToolbox

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

    /// Registers the installed bundle with the TIS subsystem and enables it.
    ///
    /// Must be called after `install()` so the bundle exists at `installDestination`.
    /// TISRegisterInputSource tells macOS about the newly-copied bundle; once
    /// registered we look it up by bundle-id and call TISEnableInputSource so the
    /// IME appears in the input-source menu without requiring the user to open
    /// System Settings → Keyboard → Input Sources and click "+".
    ///
    /// OSStatus codes:
    ///   noErr (0)    — success
    ///   paramErr (-50) — source not registerable / not enable-capable
    ///
    /// - Returns: A pair of OSStatus values (register result, enable result).
    ///            Both are noErr on full success.  Errors are non-fatal: the IME
    ///            is still installed on disk; the user can add it manually.
    @discardableResult
    func enableViaTIS() async -> (register: OSStatus, enable: OSStatus) {
        let paramErrStatus = OSStatus(paramErr)
        let dest = installDestination
        guard fileManager.fileExists(atPath: dest.path),
              let destCFURL = CFURLCreateWithFileSystemPath(
                  nil, dest.path as CFString, .cfurlposixPathStyle, true)
        else {
            return (paramErrStatus, paramErrStatus)
        }

        let registerStatus = TISRegisterInputSource(destCFURL)

        // Retry up to 3 times with 1s spacing — macOS needs to re-scan
        // ~/Library/Input Methods/ after a fresh register before TIS can find
        // and enable the source. Single-shot enable usually fails with paramErr (-50).
        var enableStatus: OSStatus = paramErrStatus
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
            let filter: [String: Any] = [
                kTISPropertyBundleID as String: "com.lingopulse.ime"
            ]
            guard let cfList = TISCreateInputSourceList(filter as CFDictionary, true),
                  let sources = cfList.takeRetainedValue() as? [TISInputSource],
                  let source = sources.first
            else {
                continue
            }
            enableStatus = TISEnableInputSource(source)
            if enableStatus == noErr {
                // Also explicitly enable each input mode declared by the bundle so
                // the mode shows in the input picker (not just the parent IME).
                let modeFilter: [String: Any] = [
                    kTISPropertyInputSourceID as String: "com.lingopulse.inputmode.english"
                ]
                if let modeList = TISCreateInputSourceList(modeFilter as CFDictionary, true),
                   let modes = modeList.takeRetainedValue() as? [TISInputSource],
                   let mode = modes.first {
                    _ = TISEnableInputSource(mode)
                    _ = TISSelectInputSource(mode)
                }
                return (registerStatus, enableStatus)
            }
        }
        return (registerStatus, enableStatus)
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
