// BeatBenchFixturePresenceGate — hard gate on the BeatBench suite fixtures (GT.1).
//
// The suite tracks (BEAT_SYNC_PROGRAM_PLAN.md §1) are full-length copyrighted audio
// living OUTSIDE the repo at BEATBENCH_FIXTURES_DIR. The committed manifest
// (Tests/Fixtures/beatbench/manifest.json) pins each track's sha256 + duration.
//
// Two tests, deliberately split (QR.3 — never a silent skip):
//   • manifestWellFormed  — ALWAYS runs (CI included): the committed manifest parses
//     and has all 17 tracks across suites 1–5. This is the artifact that never skips.
//   • localFixturesPresent — ENV-GATED (local-only per GT.3): when BEATBENCH_FIXTURES_DIR
//     is set, every local fixture must be present with the exact committed sha256; a
//     missing or re-encoded file fails loud. Inactive (with a printed note) when the env
//     var is unset, so CI/worktrees without the audio stay green.

import Testing
import Foundation
import CryptoKit

@Suite("BeatBenchFixturePresenceGate")
struct BeatBenchFixturePresenceGate {

    struct Manifest: Decodable {
        let tracks: [Track]
        struct Track: Decodable {
            let id: String
            let suite: Int
            let source: String
            let filename: String?
            let sha256: String?
        }
    }

    static func manifestURL() -> URL {
        URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()  // BeatBench/
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/beatbench/manifest.json")
    }

    static func loadManifest() throws -> Manifest {
        let data = try Data(contentsOf: manifestURL())
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    @Test("BeatBench manifest is present and well-formed (17 tracks across suites 1–5)")
    func manifestWellFormed() throws {
        let manifest = try Self.loadManifest()
        #expect(
            manifest.tracks.count == 17,
            "expected 17 BeatBench suite tracks, got \(manifest.tracks.count) at \(Self.manifestURL().path)"
        )
        for track in manifest.tracks {
            #expect((1...5).contains(track.suite), "\(track.id): suite \(track.suite) out of range 1…5")
            #expect(track.source == "local" || track.source == "tap", "\(track.id): bad source '\(track.source)'")
            #expect(track.filename != nil, "\(track.id): missing filename")
        }
        #expect(
            Set(manifest.tracks.map(\.suite)) == Set(1...5),
            "every benchmark suite 1…5 must be represented"
        )
    }

    @Test("BeatBench fixtures present + hash-matched when BEATBENCH_FIXTURES_DIR is set")
    func fixturesPresentAndHashed() throws {
        guard let dir = ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"], !dir.isEmpty else {
            print("BeatBench: BEATBENCH_FIXTURES_DIR unset — local-only presence gate inactive (see the beatbench skill).")
            return
        }
        let base = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
        let manifest = try Self.loadManifest()
        for track in manifest.tracks {
            guard let filename = track.filename else { continue }
            let url = base.appendingPathComponent(filename)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "BeatBench fixture missing: \(url.path) — run Scripts/beatbench_copy_fixtures.sh"
            )
            guard let expected = track.sha256, let data = try? Data(contentsOf: url) else { continue }
            let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(
                got == expected,
                """
                BeatBench fixture \(filename) sha256 mismatch (re-encoded / wrong file): \
                expected \(expected.prefix(12))…, got \(got.prefix(12))…. \
                Regenerate with tools/beatbench_manifest.py if the change is intentional.
                """
            )
        }
    }
}
