// MIRPipelineUnitTests — Unit tests for the MIR pipeline coordinator.
// Verifies FeatureVector assembly, SIMD alignment, and CPU-side property updates.

import Testing
import Foundation
@testable import DSP
@testable import Shared

// MARK: - Feature Population

@Test func mirPipeline_nonTrivialInput_allFeaturesPopulated() {
    let pipeline = MIRPipeline()

    // Feed a few frames of non-trivial input to get past AGC warmup.
    let magnitudes = AudioFixtures.uniformMagnitudes(magnitude: 0.5)
    for _ in 0..<120 {
        _ = pipeline.process(magnitudes: magnitudes, fps: 60, time: 1.0, deltaTime: 1.0 / 60.0)
    }

    // Now process one more frame and check the output.
    let fv = pipeline.process(magnitudes: magnitudes, fps: 60, time: 2.0, deltaTime: 1.0 / 60.0)

    // Band energies should be non-zero after AGC stabilization.
    #expect(fv.bass > 0, "Bass should be non-zero")
    #expect(fv.mid > 0, "Mid should be non-zero")
    #expect(fv.treble > 0, "Treble should be non-zero")

    // Spectral centroid should be non-zero for uniform input.
    #expect(fv.spectralCentroid > 0, "Spectral centroid should be non-zero for non-silent input")

    // Time should be set.
    #expect(fv.time == 2.0, "Time should be passed through")
    #expect(fv.deltaTime > 0, "DeltaTime should be passed through")

    // Valence/arousal should be zero (ML module responsibility).
    #expect(fv.valence == 0, "Valence should be 0 (not set by DSP)")
    #expect(fv.arousal == 0, "Arousal should be 0 (not set by DSP)")
}

// MARK: - SIMD Alignment

@Test func mirPipeline_featureVector_simdAligned() {
    // FeatureVector is 192 bytes (48 × 4) after MV-1, 16-byte aligned.
    #expect(MemoryLayout<FeatureVector>.size == 192,
            "FeatureVector should be 192 bytes, got \(MemoryLayout<FeatureVector>.size)")
    #expect(MemoryLayout<FeatureVector>.alignment <= 16,
            "FeatureVector alignment (\(MemoryLayout<FeatureVector>.alignment)) should be ≤ 16 for GPU upload")
}

// MARK: - Defaults

@Test func mirPipeline_silence_approximatesZero() {
    let pipeline = MIRPipeline()
    let silence = [Float](repeating: 0, count: 512)

    let fv = pipeline.process(magnitudes: silence, fps: 60, time: 0.5, deltaTime: 1.0 / 60.0)

    #expect(fv.bass == 0, "Bass should be 0 for silence")
    #expect(fv.spectralCentroid == 0, "Centroid should be 0 for silence")
    #expect(fv.beatBass == 0, "BeatBass should be 0 for silence")
    #expect(fv.time == 0.5, "Time should still be set")
}

// MARK: - CPU-Side Properties

@Test func mirPipeline_cpuProperties_updated() {
    let pipeline = MIRPipeline()

    // Feed non-silent input with clear pitch content (C5 harmonics).
    let magnitudes = AudioFixtures.syntheticMagnitudes(peaks: [
        (bin: 11, magnitude: 1.0),  // ~515 Hz ≈ C5
        (bin: 22, magnitude: 0.8),  // ~1031 Hz ≈ C6
        (bin: 14, magnitude: 0.6),  // ~656 Hz ≈ E5
    ])
    _ = pipeline.process(magnitudes: magnitudes, fps: 60, time: 1.0, deltaTime: 1.0 / 60.0)

    // Chroma should be updated.
    #expect(pipeline.latestChroma.count == 12, "Chroma should have 12 elements")
    let maxChroma = pipeline.latestChroma.max() ?? 0
    #expect(maxChroma > 0, "Chroma should be non-zero for pitched input")

    // Spectral rolloff should be updated.
    #expect(pipeline.spectralRolloff > 0, "Rolloff should be non-zero for non-silent input")
}
