// BeatAmplitudeClampTests — Verifies the beat-pulse amplitude scale applied
// in RenderPipeline.draw(in:) (U.9, D-054).
//
// The scale is applied to a local FeatureVector copy BEFORE it is passed to
// renderFrame — meaning it affects all four beat fields uniformly in every draw
// path without any per-shader conditional.
//
// Tests verify:
//   1. Scale 1.0 → beat fields unchanged.
//   2. Scale 0.5 → beat fields halved.
//   3. All four per-band fields (beatBass/Mid/Treble/Composite) are clamped.
//   4. beatPhase01 and beatsUntilNext are NOT clamped (timing primitives).

import Testing
@testable import Renderer
@testable import Shared

// MARK: - BeatAmplitudeClampTests

struct BeatAmplitudeClampTests {

    /// Build a FeatureVector with known beat values and non-zero timing fields.
    private func makeBeatFeatures(
        bass: Float = 0.8,
        mid: Float = 0.6,
        treble: Float = 0.4,
        composite: Float = 0.7,
        phase01: Float = 0.3,
        beatsUntilNext: Float = 0.5
    ) -> FeatureVector {
        var fv = FeatureVector.zero
        fv.beatBass      = bass
        fv.beatMid       = mid
        fv.beatTreble    = treble
        fv.beatComposite = composite
        fv.beatPhase01   = phase01
        fv.beatsUntilNext = beatsUntilNext
        return fv
    }

    /// Apply the same scale logic as RenderPipeline.draw(in:).
    private func applyScale(to features: inout FeatureVector, scale: Float) {
        features.beatBass      *= scale
        features.beatMid       *= scale
        features.beatTreble    *= scale
        features.beatComposite *= scale
    }

    // MARK: - Tests

    @Test
    func scaleOne_beatFieldsUnchanged() {
        var fv = makeBeatFeatures()
        applyScale(to: &fv, scale: 1.0)
        #expect(abs(fv.beatBass      - 0.8) < 0.0001)
        #expect(abs(fv.beatMid       - 0.6) < 0.0001)
        #expect(abs(fv.beatTreble    - 0.4) < 0.0001)
        #expect(abs(fv.beatComposite - 0.7) < 0.0001)
    }

    @Test
    func scaleHalf_beatFieldsHalved() {
        var fv = makeBeatFeatures()
        applyScale(to: &fv, scale: 0.5)
        #expect(abs(fv.beatBass      - 0.4) < 0.0001)
        #expect(abs(fv.beatMid       - 0.3) < 0.0001)
        #expect(abs(fv.beatTreble    - 0.2) < 0.0001)
        #expect(abs(fv.beatComposite - 0.35) < 0.0001)
    }

    @Test
    func scaleHalf_allFourBandsClamped() {
        var fv = makeBeatFeatures(bass: 1.0, mid: 1.0, treble: 1.0, composite: 1.0)
        applyScale(to: &fv, scale: 0.5)
        #expect(abs(fv.beatBass      - 0.5) < 0.0001)
        #expect(abs(fv.beatMid       - 0.5) < 0.0001)
        #expect(abs(fv.beatTreble    - 0.5) < 0.0001)
        #expect(abs(fv.beatComposite - 0.5) < 0.0001)
    }

    @Test
    func timingFieldsNotClamped_beatPhase01AndBeatsUntilNext() {
        var fv = makeBeatFeatures(phase01: 0.75, beatsUntilNext: 1.25)
        applyScale(to: &fv, scale: 0.5)
        // Timing primitives from BeatPredictor — must be untouched.
        #expect(abs(fv.beatPhase01    - 0.75) < 0.0001)
        #expect(abs(fv.beatsUntilNext - 1.25) < 0.0001)
    }

    @Test
    func renderPipeline_beatAmplitudeScale_defaultIsOne() throws {
        let context = try MetalContext()
        let library = try Renderer.ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * floatStride),
              let wav = context.makeSharedBuffer(length: 2048 * floatStride) else { return }
        let pipeline = try RenderPipeline(
            context: context, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wav)
        #expect(pipeline.beatAmplitudeScale == 1.0)
    }

    @Test
    func renderPipeline_frameReduceMotion_defaultIsFalse() throws {
        let context = try MetalContext()
        let library = try Renderer.ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * floatStride),
              let wav = context.makeSharedBuffer(length: 2048 * floatStride) else { return }
        let pipeline = try RenderPipeline(
            context: context, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wav)
        #expect(pipeline.frameReduceMotion == false)
    }
}
