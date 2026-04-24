import Foundation

/// Resolves Homebrew binary path across Apple Silicon and Intel Macs.
enum BrewLocation {
    static let candidates: [String] = [
        "/opt/homebrew/bin/brew",     // Apple Silicon default
        "/usr/local/bin/brew"          // Intel default
    ]

    /// Returns the first existing brew executable, or nil if Homebrew is absent.
    static func resolve(fileManager: FileManager = .default) -> String? {
        candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Prefix directory (e.g. `/opt/homebrew`). Used to locate installed CLIs.
    static func prefix(fileManager: FileManager = .default) -> String? {
        guard let brew = resolve(fileManager: fileManager) else { return nil }
        // /opt/homebrew/bin/brew -> /opt/homebrew
        return (brew as NSString).deletingLastPathComponent
            .replacingOccurrences(of: "/bin", with: "")
    }

    /// Official bootstrap one-liner. App runs via Terminal hand-off (needs TTY/sudo).
    static let bootstrapCommand = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
}
