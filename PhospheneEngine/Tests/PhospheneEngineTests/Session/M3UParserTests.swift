// M3UParserTests — LF.5 / D-132 .m3u parser regression suite.
//
// Covers the six discriminator cases the kickoff prompt names:
//   (a) trivial 3-track playlist
//   (b) #EXTINF extension metadata ignored
//   (c) relative-path resolution against the .m3u file's parent dir
//   (d) BOM + CRLF tolerance (combined into one test for readability)
//   (e) skip-unreadable behaviour surfaces in `skippedLines`
//   (f) zero-resolved result throws `.noEntriesResolved`
//
// Plus three extra edge tests: file-unreadable throw, file:// URL form,
// and parse(data:relativeTo:) with malformed UTF-8.

import Foundation
import Testing
@testable import Session

@Suite("M3UParser")
struct M3UParserTests {

    // MARK: - Fixture scaffolding

    /// Allocate a unique temp directory for one test; cleaned up via defer at
    /// each call site. Each test owns its own directory so parallel runs don't
    /// collide.
    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("M3UParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Touch an empty audio-like file at `dir/<filename>`. M3UParser does
    /// not validate audio content; readability is all that matters.
    @discardableResult
    private func touchFile(_ filename: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(filename)
        try Data().write(to: url)
        return url
    }

    /// Write `text` UTF-8 encoded to `dir/<filename>` and return the URL.
    private func writeM3U(_ text: String, named filename: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(filename)
        try text.data(using: .utf8)!.write(to: url)             // swiftlint:disable:this force_unwrapping
        return url
    }

    // MARK: - Tests

    @Test func parse_trivialThreeTracks() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try touchFile("a.m4a", in: dir)
        let b = try touchFile("b.m4a", in: dir)
        let c = try touchFile("c.m4a", in: dir)
        let m3u = try writeM3U("""
        a.m4a
        b.m4a
        c.m4a
        """, named: "mix.m3u", in: dir)

        let result = try M3UParser.parse(at: m3u)

        #expect(result.urls.count == 3)
        #expect(result.urls[0].standardizedFileURL == a.standardizedFileURL)
        #expect(result.urls[1].standardizedFileURL == b.standardizedFileURL)
        #expect(result.urls[2].standardizedFileURL == c.standardizedFileURL)
        #expect(result.skippedLines.isEmpty)
    }

    @Test func parse_skipsExtensionMetadata() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try touchFile("a.m4a", in: dir)
        let b = try touchFile("b.m4a", in: dir)
        let m3u = try writeM3U("""
        #EXTM3U
        #EXTINF:212,Artist A — Track A
        a.m4a
        # blank comment
        #EXTINF:185,Artist B — Track B
        b.m4a
        """, named: "mix.m3u", in: dir)

        let result = try M3UParser.parse(at: m3u)

        #expect(result.urls.count == 2)
        #expect(result.urls[0].standardizedFileURL == a.standardizedFileURL)
        #expect(result.urls[1].standardizedFileURL == b.standardizedFileURL)
    }

    @Test func parse_resolvesRelativePathsAgainstParentDir() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let nested = try touchFile("nested.m4a", in: sub)
        let m3u = try writeM3U("""
        subdir/nested.m4a
        """, named: "mix.m3u", in: dir)

        let result = try M3UParser.parse(at: m3u)

        #expect(result.urls.count == 1)
        #expect(result.urls[0].standardizedFileURL == nested.standardizedFileURL)
    }

    @Test func parse_toleratesBOMAndCRLF() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try touchFile("a.m4a", in: dir)
        let b = try touchFile("b.m4a", in: dir)

        // Build: UTF-8 BOM (EF BB BF) + CRLF-terminated body.
        var bytes: [UInt8] = [0xEF, 0xBB, 0xBF]
        let body = "#EXTM3U\r\na.m4a\r\nb.m4a\r\n"
        bytes.append(contentsOf: Array(body.utf8))
        let data = Data(bytes)

        let result = try M3UParser.parse(data: data, relativeTo: dir)

        #expect(result.urls.count == 2)
        #expect(result.urls[0].standardizedFileURL == a.standardizedFileURL)
        #expect(result.urls[1].standardizedFileURL == b.standardizedFileURL)
    }

    @Test func parse_skipsUnreadableEntries() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try touchFile("a.m4a", in: dir)
        let m3u = try writeM3U("""
        a.m4a
        does_not_exist.m4a
        another_missing.flac
        """, named: "mix.m3u", in: dir)

        let result = try M3UParser.parse(at: m3u)

        #expect(result.urls.count == 1)
        #expect(result.urls[0].standardizedFileURL == a.standardizedFileURL)
        #expect(result.skippedLines == ["does_not_exist.m4a", "another_missing.flac"])
    }

    @Test func parse_zeroResolved_throwsNoEntriesResolved() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let m3u = try writeM3U("""
        #EXTM3U
        missing_a.m4a
        missing_b.m4a
        """, named: "mix.m3u", in: dir)

        #expect(throws: M3UParser.ParseError.noEntriesResolved) {
            _ = try M3UParser.parse(at: m3u)
        }
    }

    @Test func parse_fileUnreadable_throws() throws {
        let nonexistent = URL(fileURLWithPath: "/private/var/tmp/does-not-exist-\(UUID().uuidString).m3u")
        #expect(throws: M3UParser.ParseError.self) {
            _ = try M3UParser.parse(at: nonexistent)
        }
    }

    @Test func parse_acceptsFileURLForm() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try touchFile("a.m4a", in: dir)
        let fileURLString = a.absoluteString                              // file:///private/var/tmp/.../a.m4a
        let m3u = try writeM3U("""
        \(fileURLString)
        """, named: "mix.m3u", in: dir)

        let result = try M3UParser.parse(at: m3u)

        #expect(result.urls.count == 1)
        #expect(result.urls[0].standardizedFileURL == a.standardizedFileURL)
    }

    @Test func parse_malformedUTF8_throws() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 0xFF / 0xFE are the UTF-16 BOM bytes — invalid UTF-8 start bytes.
        let data = Data([0xFF, 0xFE, 0x00, 0x61, 0x00, 0x62])

        #expect(throws: M3UParser.ParseError.malformedUTF8) {
            _ = try M3UParser.parse(data: data, relativeTo: dir)
        }
    }
}
