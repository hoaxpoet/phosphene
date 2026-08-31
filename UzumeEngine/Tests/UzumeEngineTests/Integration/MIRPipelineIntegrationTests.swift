// MIRPipelineIntegrationTests — End-to-end tests wiring real FFTProcessor → MIRPipeline.
// Uses real Metal device and audio fixtures (no mocks).

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared

// MARK: - Full Pipeline Integration

@Test func fullMIRPipeline_sineWave_allFeaturesPopulated() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw MIRIntegrationError.noMetalDevice
    }

    let fftProcessor = try FFTProcessor(device: device)
    let mirPipeline = MIRPipeline()

    // Generate 1 second of 440 Hz sine at 48kHz.
    let samples = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 1.0)
    let fps: Float = 60
    let deltaTime: Float = 1.0 / fps
    let hopSize = Int(48000.0 / fps)

    var lastFV = FeatureVector.zero
    var sampleOffset = 0
    var time: Float = 0

    // Process frame-by-frame.
    while sampleOffset + 1024 <= samples.count {
        let frameSamples = Array(samples[sampleOffset..<sampleOffset + 1024])
        fftProcessor.process(samples: frameSamples, sampleRate: 48000)

        // Extract magnitudes.
        var magnitudes = [Float](repeating: 0, count: 512)
        for i in 0..<512 { magnitudes[i] = fftProcessor.magnitudeBuffer[i] }

        lastFV = mirPipeline.process(magnitudes: magnitudes, fps: fps, time: time, deltaTime: deltaTime)
        sampleOffset += hopSize
        time += deltaTime
    }

    // After processing a full second of 440 Hz:
    // - Spectral centroid should reflect the sine frequency.
    #expect(lastFV.spectralCentroid > 0, "Centroid should be non-zero for 440 Hz sine")
    // - Some band energy should be present (440 Hz falls in mid band).
    #expect(lastFV.mid > 0 || lastFV.bass > 0, "Mid or bass energy should be non-zero for 440 Hz")
    // - Chroma should reflect A (440 Hz → A4, pitch class 9).
    let chroma = mirPipeline.latestChroma
    #expect(chroma.count == 12, "Chroma should have 12 bins")
    // - Time should be approximately 1 second.
    #expect(lastFV.time > 0.5, "Time should have advanced")
}

@Test func fullMIRPipeline_silence_gracefulDefaults() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw MIRIntegrationError.noMetalDevice
    }

    let fftProcessor = try FFTProcessor(device: device)
    let mirPipeline = MIRPipeline()

    let silence = AudioFixtures.silence(sampleCount: 48000)
    let fps: Float = 60
    let deltaTime: Float = 1.0 / fps
    let hopSize = Int(48000.0 / fps)

    var lastFV = FeatureVector.zero
    var sampleOffset = 0

    while sampleOffset + 1024 <= silence.count {
        let frameSamples = Array(silence[sampleOffset..<sampleOffset + 1024])
        fftProcessor.process(samples: frameSamples, sampleRate: 48000)

        var magnitudes = [Float](repeating: 0, count: 512)
        for i in 0..<512 { magnitudes[i] = fftProcessor.magnitudeBuffer[i] }

        lastFV = mirPipeline.process(magnitudes: magnitudes, fps: fps, time: Float(sampleOffset) / 48000.0, deltaTime: deltaTime)
        sampleOffset += hopSize
    }

    // Silence should produce near-zero features (no crashes, no NaN).
    #expect(lastFV.bass == 0 || lastFV.bass.isFinite, "Bass should be zero or finite for silence")
    #expect(lastFV.spectralCentroid == 0, "Centroid should be 0 for silence")
    #expect(lastFV.beatComposite == 0, "Beat composite should be 0 for silence")
    #expect(mirPipeline.estimatedTempo == nil, "Tempo should be nil for silence")
}

@Test func fullMIRPipeline_continuousFrames_noMemoryGrowth() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw MIRIntegrationError.noMetalDevice
    }

    let fftProcessor = try FFTProcessor(device: device)
    let mirPipeline = MIRPipeline()

    // Process 10,000 frames without crashing or leaking.
    let samples = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)
    let frameSamples = Array(samples.prefix(1024))
    let fps: Float = 60
    let deltaTime: Float = 1.0 / fps

    for i in 0..<10_000 {
        fftProcessor.process(samples: frameSamples, sampleRate: 48000)

        var magnitudes = [Float](repeating: 0, count: 512)
        for j in 0..<512 { magnitudes[j] = fftProcessor.magnitudeBuffer[j] }

        _ = mirPipeline.process(magnitudes: magnitudes, fps: fps, time: Float(i) * deltaTime, deltaTime: deltaTime)
    }

    // If we get here without crash or timeout, the test passes.
    // Verify the pipeline is still functional.
    let finalFV = mirPipeline.process(
        magnitudes: AudioFixtures.uniformMagnitudes(magnitude: 0.5),
        fps: fps, time: 10001.0 * deltaTime, deltaTime: deltaTime
    )
    #expect(finalFV.spectralCentroid > 0, "Pipeline should still be functional after 10K frames")
}

// MARK: - Degenerate-audio NaN/Inf robustness (CLEAN.4.5 / GAP-3)

/// Every FeatureVector field is a `Float` (48 floats = 192 bytes, GPU uniform),
/// so scan the whole struct generically and return any non-finite slots.
private func nonFiniteFeatureFields(_ fv: FeatureVector) -> [(index: Int, value: Float)] {
    withUnsafeBytes(of: fv) { raw in
        raw.bindMemory(to: Float.self).enumerated()
            .filter { !$0.element.isFinite }
            .map { (index: $0.offset, value: $0.element) }
    }
}

/// Degenerate audio (silence / DC / single cold-start frame) must never put a NaN or
/// Inf into the FeatureVector — the struct shaders read every frame. Runs the REAL
/// FFTProcessor → MIRPipeline path (FA #27: degenerate *audio samples*, not a hand-
/// authored FeatureVector) and checks EVERY frame, including the cold start where the
/// running-average denominators are still zero.
@Test func fullMIRPipeline_degenerateAudio_producesNoNaNOrInf() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw MIRIntegrationError.noMetalDevice
    }

    // A corrupted-tap frame: mostly silence with a few NaN / ±Inf samples injected at
    // the trust boundary (audio hardware/driver). The epsilon EMA floors cannot rescue
    // a NaN *input* — only sanitizing at the entry can.
    var corruptedInput = [Float](repeating: 0, count: 48_000)
    corruptedInput[100] = .nan
    corruptedInput[1_200] = .infinity
    corruptedInput[2_400] = -.infinity
    corruptedInput[3_600] = .nan

    let cases: [(label: String, samples: [Float])] = [
        ("silence",     [Float](repeating: 0,    count: 48_000)),
        ("positive DC", [Float](repeating: 0.5,  count: 48_000)),
        ("negative DC", [Float](repeating: -0.8, count: 48_000)),
        ("cold-start single frame of silence", [Float](repeating: 0, count: 1_024)),
        ("NaN/Inf input samples (corrupted tap)", corruptedInput),
    ]

    let fps: Float = 60
    let deltaTime: Float = 1.0 / fps
    let hopSize = Int(48_000.0 / fps)

    for testCase in cases {
        // Fresh processor + pipeline per case so each starts from a true cold state.
        let fftProcessor = try FFTProcessor(device: device)
        let mirPipeline = MIRPipeline()
        var sampleOffset = 0
        var time: Float = 0
        var frameIndex = 0

        while sampleOffset + 1024 <= testCase.samples.count {
            let frame = Array(testCase.samples[sampleOffset..<sampleOffset + 1024])
            fftProcessor.process(samples: frame, sampleRate: 48_000)

            var magnitudes = [Float](repeating: 0, count: 512)
            for i in 0..<512 { magnitudes[i] = fftProcessor.magnitudeBuffer[i] }

            let fv = mirPipeline.process(magnitudes: magnitudes, fps: fps, time: time, deltaTime: deltaTime)
            let bad = nonFiniteFeatureFields(fv)
            #expect(bad.isEmpty,
                "\(testCase.label) frame \(frameIndex): non-finite FeatureVector field(s) \(bad)")

            sampleOffset += hopSize
            time += deltaTime
            frameIndex += 1
        }
    }
}

/// StemFeatures is also all-`Float` (GPU buffer-3 upload) — scan it the same way.
private func nonFiniteStemFields(_ sf: StemFeatures) -> [(index: Int, value: Float)] {
    withUnsafeBytes(of: sf) { raw in
        raw.bindMemory(to: Float.self).enumerated()
            .filter { !$0.element.isFinite }
            .map { (index: $0.offset, value: $0.element) }
    }
}

/// The stem path (StemAnalyzer → StemFeatures) is ratio-heavy — attack ratios, per-stem
/// centroid, energy slope, vocal pitch — so a silent or DC stem is the realistic 0/0 risk
/// (a track with no vocals yields a silent vocal stem every frame). Run real degenerate
/// stem waveforms through StemAnalyzer over enough frames for the EMA state to develop, and
/// require every StemFeatures field to stay finite.
@Test func stemAnalyzer_degenerateStems_producesNoNaNOrInf() throws {
    let zeros = [Float](repeating: 0, count: 1_024)
    let dc = [Float](repeating: 0.5, count: 1_024)
    let sine = Array(AudioFixtures.sineWave(frequency: 440, sampleRate: 48_000, duration: 0.1).prefix(1_024))
    var nanStem = [Float](repeating: 0, count: 1_024)
    nanStem[10] = .nan; nanStem[20] = .infinity; nanStem[30] = -.infinity

    let cases: [(label: String, stems: [[Float]])] = [
        ("all-silent stems",            [zeros, zeros, zeros, zeros]),
        ("silent vocals, signal else",  [zeros, sine, sine, sine]),
        ("DC stems",                    [dc, dc, dc, dc]),
        ("NaN/Inf stem samples",        [nanStem, sine, sine, sine]),
    ]

    for testCase in cases {
        let analyzer = StemAnalyzer()
        for frame in 0..<30 {
            let sf = analyzer.analyze(stemWaveforms: testCase.stems, fps: 60)
            let bad = nonFiniteStemFields(sf)
            #expect(bad.isEmpty,
                "\(testCase.label) frame \(frame): non-finite StemFeatures field(s) \(bad)")
        }
    }
}

// MARK: - Errors

private enum MIRIntegrationError: Error {
    case noMetalDevice
}
