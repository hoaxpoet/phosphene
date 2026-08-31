// FixtureManifestPresenceGate — Hard gate on the gitignored fixtures a default
// `swift test` depends on.
//
// On a fresh checkout, BeatThisLayerMatchTests + LiveDriftValidationTests both need
// the licensed tempo clips and `DSP.2-S8-python-activations.json` to actually run.
// The pre-QR.3 behaviour was to silently `return` when these were missing — a CI run
// that "passed" looked indistinguishable from a CI run that exercised the regression
// surface, which is how the entire DSP.2 S8 four-bug surface could disappear from a
// fresh clone without anyone noticing. This suite fails loudly whenever a required
// fixture is absent, with a path-and-instructions message in the failure text.
//
// RECON.13 — the required list is no longer hardcoded here. It is read from
// `Scripts/fixtures.manifest`, the same file `link_fixtures.sh` and
// `bootstrap_fixtures.sh` read. That closes the last BUG-080 follow-up: the shell
// side used to check "is the directory non-empty" while this file hardcoded one
// filename — two granularities kept in sync by hand, where a tempo tree holding
// 1 of 3 clips satisfied the shell check and still failed the tests it was meant
// to protect. Adding a fixture is now a one-line manifest edit rather than a
// two-file edit someone can half-finish.

import Testing
import Foundation

@Suite("FixtureManifestPresenceGate")
struct FixtureManifestPresenceGate {

    /// Repo root, resolved from this file's path so it holds regardless of the
    /// test runner's working directory.
    /// …/PhospheneEngine/Tests/PhospheneEngineTests/ML/ → up 5.
    static func repoRoot(file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    static var manifestURL: URL {
        repoRoot().appendingPathComponent("Scripts/fixtures.manifest")
    }

    /// Repo-relative paths from the manifest, comments and blanks stripped.
    static func requiredPaths() throws -> [String] {
        let text = try String(contentsOf: manifestURL, encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let withoutComment = line.split(separator: "#", maxSplits: 1,
                                                omittingEmptySubsequences: false)[0]
                return withoutComment.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    @Test("Scripts/fixtures.manifest exists and lists at least one required fixture")
    func test_manifestIsPresentAndNonEmpty() throws {
        // Guards the gate itself: if the manifest vanished or emptied, the per-file
        // check below would pass vacuously and this suite would go quietly useless —
        // the exact silent-skip failure mode it exists to prevent.
        #expect(
            FileManager.default.fileExists(atPath: Self.manifestURL.path),
            "Scripts/fixtures.manifest missing at \(Self.manifestURL.path) — the fixture presence gate cannot run."
        )
        let paths = try Self.requiredPaths()
        #expect(
            !paths.isEmpty,
            "Scripts/fixtures.manifest lists no fixtures — this gate would pass vacuously."
        )
    }

    @Test("Every fixture named in Scripts/fixtures.manifest is present on disk")
    func test_requiredFixturesPresent() throws {
        let root = Self.repoRoot()
        for rel in try Self.requiredPaths() {
            let url = root.appendingPathComponent(rel)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                """
                Required fixture missing: \(rel)
                Expected at: \(url.path)
                Tests that depend on it will be silently disabled. Restore it with \
                `Scripts/link_fixtures.sh` (from a primary checkout) or \
                `Scripts/fetch_tempo_fixtures.sh` (public iTunes Search CDN), then re-run.
                """
            )
        }
    }

    @Test("DSP.2-S8-python-activations.json is present at the repo-relative path")
    func test_pythonActivationsJSONPresent() {
        // Committed, not gitignored — so it is deliberately NOT in the manifest, but
        // its absence has the same consequence (BeatThisLayerMatchTests cannot run
        // end-to-end), which is why the check stays here.
        let jsonURL = Self.repoRoot()
            .appendingPathComponent("docs/diagnostics/DSP.2-S8-python-activations.json")
        #expect(
            FileManager.default.fileExists(atPath: jsonURL.path),
            """
            Python activations JSON missing at \(jsonURL.path) — \
            BeatThisLayerMatchTests cannot run end-to-end. The file is committed under \
            docs/diagnostics/; if absent, your checkout is incomplete.
            """
        )
    }
}
