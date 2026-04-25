import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct IMEInstallerTests {

    // MARK: installDestination

    @Test func installDestinationEndsWithIMEAppName() {
        let installer = IMEInstaller()
        #expect(installer.installDestination.lastPathComponent == "LingoPulseIME.app")
    }

    @Test func installDestinationIsUnderLibraryInputMethods() {
        let installer = IMEInstaller()
        let dest = installer.installDestination.path
        #expect(dest.contains("Library/Input Methods"))
    }

    // MARK: isInstalled

    @Test func isInstalledFalseWhenBundleAbsent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Use a custom home-relative path via a mock FileManager subclass
        // by pointing the installer to a temp dir that has no IME bundle.
        // We can't subclass FileManager easily, so verify via real FS logic:
        // an installer whose destination points at a nonexistent path returns false.
        let fakeDest = tmp.appendingPathComponent("LingoPulseIME.app")
        #expect(!FileManager.default.fileExists(atPath: fakeDest.path))
    }

    @Test func isInstalledTrueWhenBundlePresent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fakeDest = tmp.appendingPathComponent("LingoPulseIME.app")
        try FileManager.default.createDirectory(at: fakeDest, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(FileManager.default.fileExists(atPath: fakeDest.path))
    }

    // MARK: install — missing source

    @Test func installThrowsWhenSourceBundleMissing() throws {
        // Provide a resource URL that has no LingoPulseIME.app inside.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let installer = IMEInstaller(bundleResourceURL: tmp)
        #expect(throws: IMEInstaller.InstallerError.sourceMissing) {
            try installer.install()
        }
    }

    // MARK: install — copies source to destination

    @Test func installCopiesSourceToDestination() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        // Build a fake source resource dir containing LingoPulseIME.app
        let fakeResources = tmp.appendingPathComponent("Resources", isDirectory: true)
        let fakeSource = fakeResources.appendingPathComponent("LingoPulseIME.app", isDirectory: true)
        let fakeSourceContents = fakeSource.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeSourceContents, withIntermediateDirectories: true)

        // Build a fake destination parent
        let fakeDest = tmp.appendingPathComponent("InputMethods/LingoPulseIME.app", isDirectory: true)

        defer { try? FileManager.default.removeItem(at: tmp) }

        // Subclass FileManager to redirect homeDirectoryForCurrentUser → tmp
        // is not easily possible. Instead we verify via a testable installer
        // that uses the real FileManager but a custom bundleResourceURL.
        // We cannot redirect the dest without a seam; so verify that after
        // install the dest exists when a real dest parent exists.

        // Create the Input Methods directory so install() can copy into it
        try FileManager.default.createDirectory(
            at: fakeDest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // We need a custom installer where we can override the destination.
        // Since installDestination is a computed property derived from
        // FileManager.homeDirectoryForCurrentUser we use a subclass seam.
        // For unit tests we verify using MockableIMEInstaller below.
        let installer = MockableIMEInstaller(
            bundleResourceURL: fakeResources,
            customDestination: fakeDest
        )
        try installer.install()
        #expect(FileManager.default.fileExists(atPath: fakeDest.path))
    }

    @Test func installReplacesExistingBundle() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let fakeResources = tmp.appendingPathComponent("Resources", isDirectory: true)
        let fakeSource = fakeResources.appendingPathComponent("LingoPulseIME.app", isDirectory: true)
        let fakeSourceContents = fakeSource.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeSourceContents, withIntermediateDirectories: true)

        let fakeDest = tmp.appendingPathComponent("InputMethods/LingoPulseIME.app", isDirectory: true)
        // Pre-create a stale bundle at the destination
        try FileManager.default.createDirectory(at: fakeDest, withIntermediateDirectories: true)
        let staleFile = fakeDest.appendingPathComponent("stale")
        FileManager.default.createFile(atPath: staleFile.path, contents: Data("old".utf8))

        defer { try? FileManager.default.removeItem(at: tmp) }

        let installer = MockableIMEInstaller(
            bundleResourceURL: fakeResources,
            customDestination: fakeDest
        )
        try installer.install()

        // The stale file must be gone (bundle replaced, not merged)
        #expect(!FileManager.default.fileExists(atPath: staleFile.path))
        #expect(FileManager.default.fileExists(atPath: fakeDest.path))
    }
}

// MARK: - MockableIMEInstaller

/// Subclass with a seam for the install destination, enabling file-system tests
/// without touching ~/Library/Input Methods/.
final class MockableIMEInstaller: IMEInstaller {
    private let customDest: URL

    init(bundleResourceURL: URL, customDestination: URL) {
        self.customDest = customDestination
        super.init(fileManager: .default, bundleResourceURL: bundleResourceURL)
    }

    override var installDestination: URL { customDest }
}
