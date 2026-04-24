import Foundation

/// Minimal GitHub Releases API client for self-update checks.
/// Polls `repos/{owner}/{repo}/releases/latest` periodically; compares the
/// returned `tag_name` against the current `CFBundleShortVersionString`.
enum GitHubReleaseChecker {

    static let owner = "bechou0410"
    static let repo = "ZaDarkHelper"

    struct Asset: Sendable, Equatable {
        let name: String
        let downloadURL: URL
        let sizeBytes: Int
    }

    struct Release: Sendable, Equatable {
        let tagName: String        // e.g. "v0.2.0"
        let name: String           // release title
        let htmlURL: URL           // release page to open in browser
        let publishedAt: Date?
        let body: String           // changelog markdown
        let assets: [Asset]        // attached files (DMGs, etc.)

        /// Strip leading 'v' for numeric comparison.
        var versionString: String {
            tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        }

        /// First .dmg asset — what the auto-updater downloads.
        var dmgAsset: Asset? {
            assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        }
    }

    enum CheckResult: Sendable {
        case upToDate(currentVersion: String)
        case updateAvailable(current: String, latest: Release)
        case failed(Error)
    }

    /// Fetches latest release and compares to the running helper version.
    /// Uses basic semver compare — tolerant of pre-release suffixes.
    static func check() async -> CheckResult {
        let current = currentHelperVersion()
        do {
            let latest = try await fetchLatest()
            if compareSemver(latest.versionString, isNewerThan: current) {
                return .updateAvailable(current: current, latest: latest)
            } else {
                return .upToDate(currentVersion: current)
            }
        } catch {
            return .failed(error)
        }
    }

    /// Synchronous accessor used by FooterStrip and diagnostics.
    static func currentHelperVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    // MARK: - Internals

    private static func fetchLatest() async throws -> Release {
        // Cache-bust query param so GitHub's edge CDN doesn't hand us a stale
        // copy. Without this, a freshly-published release can take minutes to
        // appear via `releases/latest`.
        let cacheBust = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest?_=\(cacheBust)")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ZaDarkHelper", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        // Ignore the local URLSession cache too — user clicked a manual refresh,
        // they want a real hit. Periodic checks also benefit.
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "GitHub", code: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "GitHub",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ReleasePayload.self, from: data)
        guard let url = URL(string: payload.html_url) else {
            throw NSError(domain: "GitHub", code: -2, userInfo: [NSLocalizedDescriptionKey: "Bad URL"])
        }
        let assets: [Asset] = (payload.assets ?? []).compactMap { a in
            guard let dl = URL(string: a.browser_download_url) else { return nil }
            return Asset(name: a.name, downloadURL: dl, sizeBytes: a.size)
        }
        return Release(
            tagName: payload.tag_name,
            name: payload.name ?? payload.tag_name,
            htmlURL: url,
            publishedAt: payload.published_at,
            body: payload.body ?? "",
            assets: assets
        )
    }

    /// Naive but correct for our purposes: split by dots, pad, numeric compare.
    /// Returns true when `lhs` > `rhs`.
    private static func compareSemver(_ lhs: String, isNewerThan rhs: String) -> Bool {
        let lp = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rp = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxLen = max(lp.count, rp.count)
        for i in 0..<maxLen {
            let a = i < lp.count ? lp[i] : 0
            let b = i < rp.count ? rp[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    // snake_case to match GitHub API shape
    private struct ReleasePayload: Decodable {
        let tag_name: String
        let name: String?
        let html_url: String
        let published_at: Date?
        let body: String?
        let assets: [AssetPayload]?
    }

    private struct AssetPayload: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int
    }
}
