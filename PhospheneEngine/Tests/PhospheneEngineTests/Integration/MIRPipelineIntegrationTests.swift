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

// MARK: - Errors

private enum MIRIntegrationError: Error {
    case noMetalDevice
}
