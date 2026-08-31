// SchemeTestActionRegressionTests — BUG-048 regression gate (2026-06-11).
//
// The UzumeApp scheme's test action included the UzumeEngineTests
// bundle from U.1 until BUG-048. Under `xcodebuild test` the engine bundle
// runs inside the app test host's sandboxed runner context, where ffmpeg
// subprocess spawning, audio-device access, and repo-relative file reads are
// all denied ("Operation not permitted") — ~30 environment-class failures
// that `swift test` does not reproduce, and only ~440 of the engine suite's
// 1439 tests even load. Three closeout evidence blocks (2026-06-11, two
// shells + Matt's terminal) confirmed the failure cluster is the xcodebuild
// context, not the code. The engine suite's canonical runner is
// `swift test --package-path UzumeEngine`; `xcodebuild test` covers the
// app suite. Re-adding the engine bundle to the scheme's test action
// silently reintroduces a permanently-red app step in every closeout
// evidence block — this gate makes that re-add loud.

import Foundation
import Testing

@Suite("App scheme test action (BUG-048)")
struct SchemeTestActionRegressionTests {

    /// Repo root derived from this file's path (same pattern as DocIntegrityTests).
    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // file → Tests dir ×2 → UzumeEngine → root
        return url
    }()

    private static let schemePath =
        "UzumeApp.xcodeproj/xcshareddata/xcschemes/UzumeApp.xcscheme"

    @Test("the shared UzumeApp scheme's test action does not include the engine test bundle")
    func schemeTestActionExcludesEngineBundle() throws {
        let url = Self.repoRoot.appendingPathComponent(Self.schemePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // A bundled test-product run outside the checkout cannot see the
            // scheme; a missing scheme in a real checkout is its own failure.
            Issue.record("scheme file missing at \(url.path) — cannot verify BUG-048 invariant")
            return
        }
        let scheme = try String(contentsOf: url, encoding: .utf8)

        guard let testablesRange = scheme.range(of: "<Testables>"),
              let testablesEnd = scheme.range(of: "</Testables>") else {
            Issue.record("scheme has no <Testables> block — test action shape changed; re-evaluate the BUG-048 gate")
            return
        }
        let testables = scheme[testablesRange.upperBound ..< testablesEnd.lowerBound]

        #expect(
            !testables.contains("UzumeEngineTests"),
            "UzumeEngineTests is back in the app scheme's test action — BUG-048 regression. Engine tests run via `swift test --package-path UzumeEngine`; under xcodebuild's runner they fail on environment (subprocess/audio/file access), not code."
        )
        #expect(
            testables.contains("UzumeAppTests"),
            "the app scheme's test action no longer runs UzumeAppTests — the canonical app-test invocation would silently test nothing"
        )
    }
}
