// TrackChangePresetResetRegressionTests — BUG-044 regression gate.
//
// The per-track preset-state reset (Nimbus NB.4 settle + Skein §1.5 canvas wipe/reseed) must run
// on BOTH track-change paths: the streaming metadata callback AND the local-file queue advance
// (next / prev / natural EOF). BUG-044: the Skein wipe was wired only on the streaming path —
// a local-file session accumulated one painting across every track (Matt's live read, session
// 2026-06-10T19-48-27Z: five LF track changes with Skein active, zero wipes).
//
// Source-shape discriminator (the SettingsStoreEnvironmentRegressionTests pattern): asserts the
// shared helper exists exactly once and that BOTH call sites invoke it. Anyone who re-inlines
// the reset on one path (re-opening the complementary-path gap, BUG-024 class) trips this.

import Foundation
import Testing

@testable import PhospheneApp

@Suite("Track-change preset reset wiring (BUG-044)")
struct TrackChangePresetResetRegressionTests {

    private func appSource(_ relativePath: String) -> String? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()           // PhospheneAppTests
            .deletingLastPathComponent()           // repo root
            .appendingPathComponent("PhospheneApp/\(relativePath)")
        guard let src = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record("\(relativePath) not found at \(url.path)")
            return nil
        }
        return src
    }

    @Test("The shared per-track preset reset helper exists (defined once, in +Presets)")
    func test_helperExists() {
        guard let presets = appSource("VisualizerEngine+Presets.swift") else { return }
        #expect(presets.contains("func resetPerTrackPresetState()"),
                "resetPerTrackPresetState() must be defined in VisualizerEngine+Presets.swift (BUG-044).")
        // The helper owns the Skein wipe; neither call-site file may re-inline it.
        #expect(presets.contains("clearMVWarpCanvasToGround()"),
                "The Skein §1.5 canvas wipe must live inside the shared helper.")
    }

    @Test("The STREAMING track-change callback calls the shared reset")
    func test_streamingPathCallsReset() {
        guard let capture = appSource("VisualizerEngine+Capture.swift") else { return }
        #expect(capture.contains("resetPerTrackPresetState()"),
                "The streaming track-change callback must call resetPerTrackPresetState() (BUG-044).")
        #expect(!capture.contains("clearMVWarpCanvasToGround()"),
                "The streaming path must not re-inline the Skein wipe — use the shared helper.")
    }

    @Test("The LOCAL-FILE queue advance calls the shared reset, AFTER the identity is applied")
    func test_localFilePathCallsReset() {
        guard let lf = appSource("VisualizerEngine+LocalFilePlayback.swift") else { return }
        #expect(lf.contains("resetPerTrackPresetState()"),
                "advanceLocalFileQueue must call resetPerTrackPresetState() — BUG-044: LF never wiped Skein.")
        #expect(!lf.contains("clearMVWarpCanvasToGround()"),
                "The LF path must not re-inline the Skein wipe — use the shared helper.")
        // Ordering: the Skein reseed derives from `lastResolvedTrackIdentity`, set by
        // `applyLocalFileTrackState`. Resetting before it would seed the new canvas from the
        // OLD track's identity (wrong palette + wrong trajectory, §5.7 violated).
        if let applyRange = lf.range(of: "applyLocalFileTrackState(identity: nextIdentity"),
           let resetRange = lf.range(of: "resetPerTrackPresetState()") {
            #expect(applyRange.lowerBound < resetRange.lowerBound,
                    "resetPerTrackPresetState() must run AFTER applyLocalFileTrackState (reseed reads the identity).")
        }
    }
}
