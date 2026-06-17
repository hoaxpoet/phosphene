// PresetLoaderSidecarTests — CLEAN.3.1: malformed-vs-missing sidecar classification.
//
// Before CLEAN.3.1, `loadDescriptor` combined `fileExists` + `try? Data(...)` +
// `try? decode(...)` into one guard, so a sidecar that EXISTED BUT WAS MALFORMED fell
// into the same `.info("No JSON sidecar…")` branch as a genuinely-absent file — a typo'd
// sidecar silently degraded the preset to default family/feedback params with no signal.
//
// The fix splits the two: `decodeSidecar(at:)` returns nil for a missing file (benign)
// and *throws* for a present-but-unreadable/malformed one (the caller logs `.error` and
// still degrades to the name-only default). These tests lock that classification — the
// throw is the testable proxy for "an error is surfaced".

import Testing
import Foundation
@testable import Presets

@Suite("PresetLoaderSidecar")
struct PresetLoaderSidecarTests {

    /// A unique temp directory for one test's fixtures.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetLoaderSidecarTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Missing sidecar → nil (benign default), no throw")
    func test_missingSidecar_returnsNil() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let absent = dir.appendingPathComponent("DoesNotExist.json")

        let descriptor = try PresetLoader.decodeSidecar(at: absent)
        #expect(descriptor == nil)
    }

    @Test("Malformed sidecar → throws (loud, not silently defaulted)")
    func test_malformedSidecar_throws() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("Broken.json")
        // Present on disk, but not valid JSON — the case that previously degraded silently.
        try Data(#"{ "name": "Broken", "family":  "#.utf8).write(to: bad)

        #expect(throws: (any Error).self) {
            _ = try PresetLoader.decodeSidecar(at: bad)
        }
    }

    @Test("Valid sidecar → decoded descriptor with its declared name")
    func test_validSidecar_decodes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = dir.appendingPathComponent("Good.json")
        try Data(#"{"name": "Good", "family": "waveform"}"#.utf8).write(to: good)

        let descriptor = try PresetLoader.decodeSidecar(at: good)
        #expect(descriptor?.name == "Good")
    }
}
