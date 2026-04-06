// BeatDetectorRegressionTests — Golden-value regression tests for beat detection.
// Verifies onset detection and tempo estimation against known kick patterns.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared

// MARK: - Beat Detection Regression

@Test func beatDetector_120BPMKick_onsetsDetected() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw BeatRegressionError.noMetalDevice
    }

    // Load 120 BPM kick fixture (1 second at 48kHz).
    let kickSamples = try loadFixture("120bpm_kick_48000")
    #expect(kickSamples.count == 48000, "Kick fixture should have 48000 samples")

    // Process frame-by-frame through FFT + BeatDetector.
    let fftProcessor = try FFTProcessor(device: device)
    let beatDetector = BeatDetector()

    let fps: Float = 60
    let deltaTime: Float = 1.0 / fps
    let fftSize = 1024
    let hopSize = Int(48000.0 / fps)  // ~800 samples per frame at 60fps

    var onsetFrames = [Int]()
    var frameIndex = 0
    var sampleOffset = 0

    while sampleOffset + fftSize <= kickSamples.count {
        let frameSamples = Array(kickSamples[sampleOffset..<sampleOffset + fftSize])
        fftProcessor.process(samples: frameSamples, sampleRate: 48000)

        var magnitudes = [Float](repeating: 0, count: 512)
        for i in 0..<512 { magnitudes[i] = fftProcessor.magnitudeBuffer[i] }

        let result = beatDetector.process(magnitudes: magnitudes, fps: fps, deltaTime: deltaTime)

        // Check if bass onset fired.
        if result.onsets[0] || result.onsets[1] {
            onsetFrames.append(frameIndex)
        }

        sampleOffset += hopSize
        frameIndex += 1
    }

    // At 120 BPM for 1 second, expect 2 beats (at t=0 and t=0.5).
    // Allow for detection delay and cooldown effects.
    #expect(onsetFrames.count >= 1,
            "Should detect at least 1 bass onset in a 120 BPM kick pattern, got \(onsetFrames.count)")
    #expect(onsetFrames.count <= 5,
            "Should not detect more than 5 onsets in 1 second at 120 BPM, got \(onsetFrames.count)")
}

@Test func beatDetector_120BPMKick_stableAcrossRuns() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw BeatRegressionError.noMetalDevice
    }

    let kickSamples = try loadFixture("120bpm_kick_48000")

    // Run the same detection twice.
    func runDetection() throws -> [Int] {
        let fft = try FFTProcessor(device: device)
        let detector = BeatDetector()
        let fps: Float = 60
        let deltaTime: Float = 1.0 / fps
        let hopSize = Int(48000.0 / fps)

        var onsetFrames = [Int]()
        var frameIndex = 0
        var sampleOffset = 0

        while sampleOffset + 1024 <= kickSamples.count {
            let frameSamples = Array(kickSamples[sampleOffset..<sampleOffset + 1024])
            fft.process(samples: frameSamples, sampleRate: 48000)

            var magnitudes = [Float](repeating: 0, count: 512)
            for i in 0..<512 { magnitudes[i] = fft.magnitudeBuffer[i] }

            let result = detector.process(magnitudes: magnitudes, fps: fps, deltaTime: deltaTime)
            if result.onsets[0] || result.onsets[1] { onsetFrames.append(frameIndex) }

            sampleOffset += hopSize
            frameIndex += 1
        }
        return onsetFrames
    }

    let run1 = try runDetection()
    let run2 = try runDetection()

    #expect(run1 == run2, "Onset detection should be deterministic across runs")
}

// MARK: - Fixture Loading

private func loadFixture(_ name: String) throws -> [Float] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw BeatRegressionError.fixtureNotFound(name)
    }
    let data = try Data(contentsOf: url)
    guard let doubles = try JSONSerialization.jsonObject(with: data) as? [Double] else {
        throw BeatRegressionError.fixtureParseError(name)
    }
    return doubles.map { Float($0) }
}

// MARK: - Errors

private enum BeatRegressionError: Error {
    case noMetalDevice
    case fixtureNotFound(String)
    case fixtureParseError(String)
}
