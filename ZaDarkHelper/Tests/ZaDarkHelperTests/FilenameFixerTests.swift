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

    func test_target_returnsNilForDisallowedExtension() {
        XCTAssertNil(FilenameFixer.target(for: "gen-h-foo.txt"))
        XCTAssertNil(FilenameFixer.target(for: "gen-h-archive.zip"))
    }

    func test_target_returnsNilWhenPrefixDiffers() {
        XCTAssertNil(FilenameFixer.target(for: "gen-x-foo.jpg"))
        XCTAssertNil(FilenameFixer.target(for: "foo.jpg"))
    }

    func test_target_returnsNilWhenBaseEmpty() {
        XCTAssertNil(FilenameFixer.target(for: "gen-h-.jpg"))
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

    // MARK: - helpers

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zadark-fixer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
