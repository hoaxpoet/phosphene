// BeatThisFixturePresenceGate — Hard gate on the offline fixtures the BeatThis!
// regression surface depends on.
//
// On a fresh checkout, BeatThisLayerMatchTests + LiveDriftValidationTests both need
// `love_rehab.m4a` and `DSP.2-S8-python-activations.json` to actually run. The pre-QR.3
// behaviour was to silently `return` when these were missing — a CI run that "passed"
// looked indistinguishable from a CI run that exercised the regression surface, which is
// how the entire DSP.2 S8 four-bug surface could disappear from a fresh clone without
// anyone noticing. This suite fails loudly whenever a required fixture is absent, with
// a path-and-instructions message in the failure text.

import Testing
import Foundation

@Suite("BeatThisFixturePresenceGate")
struct BeatThisFixturePresenceGate {

    @Test("love_rehab.m4a is present in the test fixtures tree")
    func test_loveRehabAudioFixturePresent() {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let audioURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        #expect(
            FileManager.default.fileExists(atPath: audioURL.path),
            """
            love_rehab.m4a missing at \(audioURL.path) — \
            BeatThisLayerMatchTests + LiveDriftValidationTests will be silently disabled. \
            Restore the fixture before committing.
            """
        )
    }

    @Test("DSP.2-S8-python-activations.json is present at the repo-relative path")
    func test_pythonActivationsJSONPresent() {
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let jsonURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // PhospheneEngine/
            .deletingLastPathComponent()  // repo root
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
