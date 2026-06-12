// MoodPathRegressionTests — the D-024 / former-FA-#25 mood-plumbing gate (REVIEW.4, 2026-06-11).
//
// Mood (valence/arousal) reaches the GPU only via `RenderPipeline.setMood`, on a slower
// cadence than the per-frame MIR `setFeatures` stream. `setFeatures` must therefore
// PRESERVE the mood fields across overwrites — without that, mood silently resets to 0
// every MIR frame and presets show no mood response while the debug overlay looks fine
// (the original FA #25 failure shape). The preserving code lives in
// `RenderPipeline+PresetSwitching.setFeatures`; until this gate, nothing guarded it
// against refactor (noted as an open follow-up at the RB.2 rulebook purge).

import Metal
import Testing
@testable import Renderer
@testable import Shared

@Suite("Mood path (D-024): setFeatures preserves setMood values")
struct MoodPathRegressionTests {

    private enum SetupError: Error { case noMetalDevice, metalSetupFailed }

    private func makePipeline() throws -> RenderPipeline {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SetupError.noMetalDevice
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let fftBuf = device.makeBuffer(length: 512 * 4, options: .storageModeShared),
              let wavBuf = device.makeBuffer(length: 2048 * 4, options: .storageModeShared) else {
            throw SetupError.metalSetupFailed
        }
        return try RenderPipeline(context: ctx, shaderLibrary: lib,
                                  fftBuffer: fftBuf, waveformBuffer: wavBuf)
    }

    @Test func setFeatures_preservesMoodAcrossMIRFrames() throws {
        let pipeline = try makePipeline()

        pipeline.setMood(valence: 0.7, arousal: -0.3)

        // A fresh MIR frame arrives with zeroed mood fields (the classifier hasn't run
        // this frame) — the per-frame overwrite must not clobber the held mood.
        var frame = FeatureVector.zero
        frame.bass = 0.5
        pipeline.setFeatures(frame)

        let after = pipeline.featuresLock.withLock { pipeline.latestFeatures }
        #expect(after.valence == 0.7 && after.arousal == -0.3,
                "setFeatures clobbered mood (valence \(after.valence), arousal \(after.arousal)) — the D-024 preserve block in setFeatures was removed or bypassed")
        #expect(after.bass == 0.5, "setFeatures should still apply the MIR fields")
    }

    @Test func setMood_updatesOnlyMoodFields() throws {
        let pipeline = try makePipeline()

        var frame = FeatureVector.zero
        frame.bass = 0.5
        frame.treble = 0.25
        pipeline.setFeatures(frame)

        pipeline.setMood(valence: -0.2, arousal: 0.9)

        let after = pipeline.featuresLock.withLock { pipeline.latestFeatures }
        #expect(after.valence == -0.2 && after.arousal == 0.9)
        #expect(after.bass == 0.5 && after.treble == 0.25,
                "setMood must not disturb MIR-populated fields")
    }
}
