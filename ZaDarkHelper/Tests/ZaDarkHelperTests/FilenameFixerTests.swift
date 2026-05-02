import XCTest
@testable import ZaDarkHelper

/// F1 — pure logic tests. Real filesystem ops use a temp directory so we
/// don't touch the user's Downloads folder.
final class FilenameFixerTests: XCTestCase {

    // MARK: - target(for:)

    func test_target_stripsPrefixOnAllowedExtensions() {
        XCTAssertEqual(FilenameFixer.target(for: "gen-h-foo.jpg"), "foo.jpg")
        XCTAssertEqual(FilenameFixer.target(for: "gen-h-bar.PNG"), "bar.PNG")
        XCTAssertEqual(FilenameFixer.target(for: "gen-h-clip.mp4"), "clip.mp4")
        XCTAssertEqual(FilenameFixer.target(for: "gen-h-anim.webp"), "anim.webp")
    }

    /// Zalo cache convention uses `gen-{tag}-` where {tag} varies (h, n, …).
    /// We accept any 1-4 alphanumeric tag.
    func test_target_stripsAllGenLetterVariants() {
        XCTAssertEqual(FilenameFixer.target(for: "gen-n-z776.jpg"), "z776.jpg")
        XCTAssertEqual(FilenameFixer.target(for: "gen-x-foo.png"), "foo.png")
        XCTAssertEqual(FilenameFixer.target(for: "gen-o-bar.jpg"), "bar.jpg")    // user-reported variant
        XCTAssertEqual(FilenameFixer.target(for: "gen-12-clip.mp4"), "clip.mp4")
        XCTAssertEqual(FilenameFixer.target(for: "gen-h1-mix.png"), "mix.png")   // alphanumeric mix
        XCTAssertEqual(FilenameFixer.target(for: "gen-1234-edge.jpg"), "edge.jpg") // tag at 4-char limit
        XCTAssertEqual(FilenameFixer.target(for: "GEN-N-photo.jpg"), "photo.jpg")  // case-insensitive
    }

    /// Real-world Zalo filenames mix long underscore-separated IDs with the
    /// `gen-{tag}-` prefix. Verify the regex doesn't over-match on the inner
    /// dashes that don't exist in Zalo's IDs (Zalo uses underscore separators).
    func test_target_handlesRealZaloFilenames() {
        let cases: [(String, String)] = [
            ("gen-h-z7765451534122_451de5c3bcfeb46775a1ab99bd97a3a6.jpg",
             "z7765451534122_451de5c3bcfeb46775a1ab99bd97a3a6.jpg"),
            ("gen-n-z7766965098045_57cac0ec92f4bc2457d419708a677567.jpg",
             "z7766965098045_57cac0ec92f4bc2457d419708a677567.jpg"),
            ("gen-o-z7767015538037_8be6c76d2d011fde0d5cf53b591801a6.jpg",
             "z7767015538037_8be6c76d2d011fde0d5cf53b591801a6.jpg")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(FilenameFixer.target(for: input), expected, "input=\(input)")
        }
    }

    /// Every extension on the whitelist should match — guards against
    /// accidental whitelist regression.
    func test_target_acceptsAllAllowedExtensions() {
        for ext in ["jpg", "jpeg", "png", "webp", "gif", "mp4", "mov", "m4v"] {
            XCTAssertEqual(FilenameFixer.target(for: "gen-h-x.\(ext)"), "x.\(ext)",
                           "extension \(ext) should be allowed")
        }
    }

    func test_target_returnsNilForDisallowedExtension() {
        XCTAssertNil(FilenameFixer.target(for: "gen-h-foo.txt"))
        XCTAssertNil(FilenameFixer.target(for: "gen-h-archive.zip"))
    }

    func test_target_returnsNilWhenPrefixDiffers() {
        XCTAssertNil(FilenameFixer.target(for: "foo.jpg"))
        XCTAssertNil(FilenameFixer.target(for: "gen-foo.jpg"))           // missing tag dash
        XCTAssertNil(FilenameFixer.target(for: "gen-toolong-foo.jpg"))   // tag > 4 chars
        XCTAssertNil(FilenameFixer.target(for: "regular-photo.jpg"))
    }

    func test_target_returnsNilWhenBaseEmpty() {
        XCTAssertNil(FilenameFixer.target(for: "gen-h-.jpg"))
        XCTAssertNil(FilenameFixer.target(for: "gen-n-.png"))
    }

    // MARK: - rename(at:)

    func test_rename_movesFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("gen-h-photo.jpg")
        try Data("x".utf8).write(to: src)

        let dest = try FilenameFixer.rename(at: src)
        XCTAssertEqual(dest?.lastPathComponent, "photo.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest!.path))
    }

    func test_rename_returnsNilOnNoMatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("regular.jpg")
        try Data("x".utf8).write(to: src)

        let dest = try FilenameFixer.rename(at: src)
        XCTAssertNil(dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path))
    }

    func test_rename_throwsConflictWhenDestExists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("gen-h-photo.jpg")
        let dst = dir.appendingPathComponent("photo.jpg")
        try Data("x".utf8).write(to: src)
        try Data("y".utf8).write(to: dst)

        XCTAssertThrowsError(try FilenameFixer.rename(at: src)) { err in
            guard case FilenameFixer.FixerError.conflict = err else {
                XCTFail("Expected .conflict error, got \(err)")
                return
            }
        }
    }

    /// Calling rename on a file whose name doesn't carry the prefix is a
    /// pure no-op (returns nil, file untouched). Verifies idempotency when
    /// helper retries after a successful prior rename.
    func test_rename_isIdempotentOnAlreadyClean() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("photo.jpg")
        try Data("x".utf8).write(to: url)

        XCTAssertNil(try FilenameFixer.rename(at: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - undoRename(currentURL:originalName:)

    func test_undoRename_revertsFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let renamed = dir.appendingPathComponent("photo.jpg")
        try Data("x".utf8).write(to: renamed)

        try FilenameFixer.undoRename(currentURL: renamed, originalName: "gen-h-photo.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gen-h-photo.jpg").path))
    }

    // MARK: - scanAndRename(in:)

    func test_scanAndRename_processesAllMatches() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["gen-h-a.jpg", "gen-h-b.png", "regular.jpg", "gen-h-c.txt"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }

        let result = FilenameFixer.scanAndRename(in: dir)
        XCTAssertEqual(result.renamed, 2)        // only .jpg and .png matched
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("b.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("regular.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gen-h-c.txt").path))
    }

    /// Bulk scan must surface conflict errors without aborting the rest of
    /// the work. One file can't rename (dest already exists), the other
    /// still completes successfully.
    func test_scanAndRename_partialFailureSurfacesError() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // gen-h-conflict.jpg can't rename — conflict.jpg already exists.
        try Data("x".utf8).write(to: dir.appendingPathComponent("gen-h-conflict.jpg"))
        try Data("y".utf8).write(to: dir.appendingPathComponent("conflict.jpg"))
        // gen-h-clean.jpg renames cleanly.
        try Data("z".utf8).write(to: dir.appendingPathComponent("gen-h-clean.jpg"))

        let result = FilenameFixer.scanAndRename(in: dir)
        XCTAssertEqual(result.renamed, 1, "only the conflict-free file should rename")
        XCTAssertEqual(result.errors.count, 1)
        if case FilenameFixer.FixerError.conflict? = result.errors.first as? FilenameFixer.FixerError {
            // expected
        } else {
            XCTFail("Expected .conflict in errors, got \(result.errors)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("clean.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("gen-h-conflict.jpg").path),
                      "conflicting source should remain untouched")
    }

    // MARK: - helpers

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zadark-fixer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
