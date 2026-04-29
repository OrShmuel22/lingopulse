import Foundation

enum ShellInstaller {
    enum Shell { case zsh, bash }

    struct Result {
        let title: String
        let message: String
    }

    static func install(_ shell: Shell) -> Result {
        let cfg = config(for: shell)

        guard let bundled = Bundle.main.url(forResource: cfg.scriptBase, withExtension: cfg.scriptExt) else {
            return Result(
                title: "Script not found",
                message: "\(cfg.scriptName) is not bundled in the app. Rebuild with build-bundle.sh."
            )
        }

        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse")
        let dest = configDir.appendingPathComponent(cfg.scriptName)
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: bundled, to: dest)
        } catch {
            return Result(title: "Install failed", message: error.localizedDescription)
        }

        let rcURL = URL(fileURLWithPath: cfg.rcFile)
        let existing = (try? String(contentsOf: rcURL, encoding: .utf8)) ?? ""
        var appended = ""
        if !existing.contains(cfg.scriptName) {
            appended += "\n# LingoPulse shell integration\n\(cfg.sourceLine)\n"
        }
        if !existing.contains(cfg.bindLine) {
            appended += "\(cfg.bindLine)\n"
        }

        if !appended.isEmpty {
            do {
                if FileManager.default.fileExists(atPath: rcURL.path) {
                    let handle = try FileHandle(forWritingTo: rcURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    if let data = appended.data(using: .utf8) { try handle.write(contentsOf: data) }
                } else {
                    let initial = "# LingoPulse shell integration\n\(cfg.sourceLine)\n\(cfg.bindLine)\n"
                    try initial.write(to: rcURL, atomically: true, encoding: .utf8)
                }
            } catch {
                return Result(title: "Could not write \(cfg.rcFile)", message: error.localizedDescription)
            }
        }

        return Result(
            title: "Installed",
            message: "Added to \(cfg.rcFile). Open a new terminal or run `source \(cfg.rcFile)`."
        )
    }

    static func regenerateToken() {
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse/shell-token")
        try? FileManager.default.removeItem(at: tokenFile)
    }

    private struct Config {
        let scriptName: String
        let scriptBase: String
        let scriptExt: String
        let rcFile: String
        let sourceLine: String
        let bindLine: String
    }

    private static func config(for shell: Shell) -> Config {
        switch shell {
        case .zsh:
            let rc = (ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()) + "/.zshrc"
            return Config(
                scriptName: "lp-refine.zsh",
                scriptBase: "lp-refine",
                scriptExt: "zsh",
                rcFile: rc,
                sourceLine: "source \"${HOME}/.config/lingopulse/lp-refine.zsh\"",
                bindLine: "bindkey '^G' lp-refine"
            )
        case .bash:
            return Config(
                scriptName: "lp-refine.bash",
                scriptBase: "lp-refine",
                scriptExt: "bash",
                rcFile: NSHomeDirectory() + "/.bashrc",
                sourceLine: "source \"${HOME}/.config/lingopulse/lp-refine.bash\"",
                bindLine: "bind -x '\"\\C-g\": lp-refine'"
            )
        }
    }
}
