// PreviewAudioContentHashTests — LF.3 / D-130.
//
// Locks the content-hash → cache-key contract that the persistent stem
// cache depends on:
//   1. `PreviewAudio.sha256(of:)` produces a hex digest byte-for-byte
//      identical to `shasum -a 256 <file>`.
//   2. `PreviewAudio.fromLocalFile(at:)` builds the synthetic identity
//      in the form `local:sha256:<hash>` (LF.2's path-based identity
//      is gone).
//   3. Two identically-named copies of the same bytes resolve to the
//      same identity — and bytes-different files don't.

import Foundation
import Testing
@testable import Session

@Suite("PreviewAudio content-hash + identity migration")
struct PreviewAudioContentHashTests {

    // MARK: - Fixtures

    private static func makeTempFile(bytes: [UInt8]) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PreviewAudioContentHashTests-\(UUID().uuidString).bin")
        try Data(bytes).write(to: url)
        return url
    }

    /// Literal ASCII bytes "phosphene" (9 bytes). Used as a small,
    /// audio-decoder-free input for the hash-stability and
    /// content-vs-path tests below.
    private static let phospheneBytes: [UInt8] = [
        0x70, 0x68, 0x6f, 0x73, 0x70, 0x68, 0x65, 0x6e, 0x65,
    ]

    // MARK: - sha256(of:)

    @Test("sha256(of:) returns a 64-char lowercase hex digest")
    func test_sha256_returnsLowercaseHex() throws {
        let url = try Self.makeTempFile(bytes: Self.phospheneBytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let hash = try PreviewAudio.sha256(of: url)

        #expect(hash.count == 64, "SHA-256 hex must be 64 chars")
        #expect(hash == hash.lowercased(), "SHA-256 hex must be lowercase")
        // Every char in [0-9a-f].
        let validChars = CharacterSet(charactersIn: "0123456789abcdef")
        let hashCharacters = CharacterSet(charactersIn: hash)
        #expect(hashCharacters.isSubset(of: validChars),
                "hex digest must contain only [0-9a-f] (got '\(hash)')")
    }

    @Test("sha256(of:) is stable across repeated reads of the same bytes")
    func test_sha256_isStable() throws {
        let url = try Self.makeTempFile(bytes: Self.phospheneBytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let a = try PreviewAudio.sha256(of: url)
        let b = try PreviewAudio.sha256(of: url)
        let c = try PreviewAudio.sha256(of: url)
        #expect(a == b)
        #expect(b == c)
    }

    @Test("sha256(of:) ignores the file path — bytes are all that matter")
    func test_sha256_isContentNotPath() throws {
        let url1 = try Self.makeTempFile(bytes: Self.phospheneBytes)
        defer { try? FileManager.default.removeItem(at: url1) }
        let url2 = try Self.makeTempFile(bytes: Self.phospheneBytes)
        defer { try? FileManager.default.removeItem(at: url2) }

        #expect(url1.path != url2.path, "fixture sanity: paths differ")
        let h1 = try PreviewAudio.sha256(of: url1)
        let h2 = try PreviewAudio.sha256(of: url2)
        #expect(h1 == h2, "same bytes at different paths must hash the same")
    }

    @Test("sha256(of:) distinguishes different byte content")
    func test_sha256_distinguishesContent() throws {
        let url1 = try Self.makeTempFile(bytes: Self.phospheneBytes)
        defer { try? FileManager.default.removeItem(at: url1) }
        let url2 = try Self.makeTempFile(bytes: Self.phospheneBytes + [0x00])
        defer { try? FileManager.default.removeItem(at: url2) }

        let h1 = try PreviewAudio.sha256(of: url1)
        let h2 = try PreviewAudio.sha256(of: url2)
        #expect(h1 != h2, "appending one byte must change the SHA-256")
    }

    @Test("sha256(of:) throws on a missing file rather than returning empty")
    func test_sha256_missingFile_throws() throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).bin")
        #expect(throws: (any Error).self) {
            _ = try PreviewAudio.sha256(of: missing)
        }
    }

    // MARK: - love_rehab fixture cross-check (matches `shasum -a 256`)

    /// Anchors the in-process hash output to the reference `shasum -a 256`
    /// CLI output. The expected hash was captured at the same revision
    /// the test code lands at; if either the fixture bytes or the hash
    /// implementation drifts, the assertion fires.
    @Test("sha256(of: love_rehab.m4a) matches `shasum -a 256` output")
    func test_sha256_loveRehab_matchesShasum() throws {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let fixtureURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            Issue.record("love_rehab.m4a fixture missing — see Scripts/fetch_tempo_fixtures.sh")
            return
        }
        let expected = "c1685f07d55997cb9e3343e5be5ff72dac9fc0470e5ecc8d83514caf88032290"
        let actual = try PreviewAudio.sha256(of: fixtureURL)
        #expect(actual == expected,
                "in-process SHA-256 must match `shasum -a 256` reference (got '\(actual)')")
    }

    // MARK: - Identity migration (LF.2 `local:` + path → LF.3 `local:sha256:` + hash)

    @Test("fromLocalFile(at:) builds a sha256-based synthetic identity")
    func test_fromLocalFile_identityIsSha256Form() throws {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let fixtureURL = testDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            Issue.record("love_rehab.m4a fixture missing")
            return
        }
        let preview = try PreviewAudio.fromLocalFile(at: fixtureURL)
        let id = preview.trackIdentity.spotifyID
        #expect(id?.hasPrefix("local:sha256:") == true,
                "identity must use the LF.3 prefix (got \(id ?? "nil"))")
        let hashFromIdentity = id?.replacingOccurrences(of: "local:sha256:", with: "")
        let hashFromHelper = try PreviewAudio.sha256(of: fixtureURL)
        #expect(hashFromIdentity == hashFromHelper,
                "identity hash must match PreviewAudio.sha256(of:)")
    }

    @Test("fromLocalFile(at:contentHash:) honours the precomputed hash")
    func test_fromLocalFile_honoursPrecomputedHash() throws {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let fixtureURL = testDir
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            Issue.record("love_rehab.m4a fixture missing")
            return
        }
        let canned = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let preview = try PreviewAudio.fromLocalFile(at: fixtureURL, contentHash: canned)
        #expect(preview.trackIdentity.spotifyID == "local:sha256:" + canned,
                "explicit contentHash must be used verbatim — no recompute")
    }
}
