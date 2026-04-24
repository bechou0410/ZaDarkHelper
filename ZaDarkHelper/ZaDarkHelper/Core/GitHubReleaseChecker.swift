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
        // Try JSON API first (richer: has DMG asset URL for auto-update).
        // If rate-limited (60 req/h anonymous), fall back to Atom feed which
        // has no API rate limit — we lose DMG asset info but still detect new
        // versions so banner can show "Tải thủ công" (opens browser).
        do {
            return try await fetchJSON()
        } catch GitHubError.rateLimited {
            return try await fetchAtom()
        }
    }

    enum GitHubError: Error {
        case rateLimited
        case httpError(Int)
        case decodeError
    }

    private static func fetchJSON() async throws -> Release {
        let cacheBust = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest?_=\(cacheBust)")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ZaDarkHelper", forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.httpError(-1)
        }
        if http.statusCode == 403 {
            // GitHub API rate limit — surface for fallback path.
            throw GitHubError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubError.httpError(http.statusCode)
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

    /// Atom feed fallback — public RSS endpoint with NO rate limit.
    /// Gives us tag name + release page URL, but not DMG assets. Banner falls
    /// back to "Tải thủ công" (opens browser) when this path is used.
    private static func fetchAtom() async throws -> Release {
        let cacheBust = Int(Date().timeIntervalSince1970)
        let url = URL(string: "https://github.com/\(owner)/\(repo)/releases.atom?_=\(cacheBust)")!
        var req = URLRequest(url: url)
        req.setValue("ZaDarkHelper", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw GitHubError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw GitHubError.decodeError
        }

        // Minimal XML parse — find first <entry> then extract tag + URL.
        // Avoids pulling in XMLParser for just 2 fields.
        // Tag name lives as the suffix of the entry link: /releases/tag/vX.Y.Z
        guard let linkHref = matchFirst(#"<link rel="alternate"[^>]*href="([^"]+)""#, in: xml)
                ?? matchFirst(#"<link href="([^"]+/releases/tag/[^"]+)""#, in: xml),
              let linkURL = URL(string: linkHref),
              linkHref.contains("/releases/tag/") else {
            throw GitHubError.decodeError
        }
        let tag = linkHref.components(separatedBy: "/releases/tag/").last ?? "?"
        let title = matchFirst(#"<title>([^<]+)</title>"#, in: xml.components(separatedBy: "<entry>").dropFirst().first ?? "")
            ?? tag

        return Release(
            tagName: tag,
            name: title,
            htmlURL: linkURL,
            publishedAt: nil,
            body: "",
            assets: []
        )
    }

    private static func matchFirst(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let range = Range(m.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
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
