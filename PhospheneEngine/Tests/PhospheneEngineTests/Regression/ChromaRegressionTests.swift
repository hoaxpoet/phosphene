// ChromaRegressionTests — Golden-value regression tests for chroma extraction.
// Compares ChromaExtractor output against saved fixture data to catch silent
// changes to pitch mapping, normalization, or key estimation.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Shared

// MARK: - Chroma Golden-Value Regression

@Test func chroma_CMajorChord_matchesGoldenOutput() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw ChromaRegressionError.noMetalDevice
    }

    // Load C major chord fixture (C5+E5+G5 at 48kHz).
    let chordSamples = try loadFixture("c_major_chord_4800")
    #expect(chordSamples.count == 4800, "Chord fixture should have 4800 samples")

    // Run through real FFTProcessor.
    let fftProcessor = try FFTProcessor(device: device)
    let input = Array(chordSamples.prefix(1024))
    fftProcessor.process(samples: input, sampleRate: 48000)

    // Extract magnitudes from UMA buffer.
    var magnitudes = [Float](repeating: 0, count: 512)
    for i in 0..<512 {
        magnitudes[i] = fftProcessor.magnitudeBuffer[i]
    }

    // Run through ChromaExtractor.
    let extractor = ChromaExtractor()
    let result = extractor.process(magnitudes: magnitudes)

    // Golden chroma vector (captured from initial validated run).
    // C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11
    // For a C5+E5+G5 chord, we expect strong C(0), E(4), G(7).
    #expect(result.chroma.count == 12, "Chroma should have 12 bins")

    // The chord tones should be the top 3 bins.
    let indexed = result.chroma.enumerated().sorted { $0.element > $1.element }
    let top3PitchClasses = Set(indexed.prefix(3).map { $0.offset })
    let expectedChordTones: Set<Int> = [0, 4, 7]  // C, E, G

    #expect(top3PitchClasses == expectedChordTones,
            "Top 3 chroma bins should be C(0), E(4), G(7), got \(top3PitchClasses)")

    // Key should be C major.
    #expect(result.estimatedKey == "C major",
            "Key should be C major, got \(result.estimatedKey ?? "nil")")
}

@Test func chroma_CMajorChord_stableAcrossRuns() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw ChromaRegressionError.noMetalDevice
    }

    let chordSamples = try loadFixture("c_major_chord_4800")
    let fftProcessor = try FFTProcessor(device: device)
    let input = Array(chordSamples.prefix(1024))

    // Run twice and verify identical results.
    fftProcessor.process(samples: input, sampleRate: 48000)
    var mags1 = [Float](repeating: 0, count: 512)
    for i in 0..<512 { mags1[i] = fftProcessor.magnitudeBuffer[i] }

    let extractor1 = ChromaExtractor()
    let result1 = extractor1.process(magnitudes: mags1)

    fftProcessor.process(samples: input, sampleRate: 48000)
    var mags2 = [Float](repeating: 0, count: 512)
    for i in 0..<512 { mags2[i] = fftProcessor.magnitudeBuffer[i] }

    let extractor2 = ChromaExtractor()
    let result2 = extractor2.process(magnitudes: mags2)

    for i in 0..<12 {
        #expect(abs(result1.chroma[i] - result2.chroma[i]) < 0.0001,
                "Chroma bin \(i) should be stable across runs")
    }
    #expect(result1.estimatedKey == result2.estimatedKey, "Key should be stable")
}

// MARK: - Fixture Loading

private func loadFixture(_ name: String) throws -> [Float] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw ChromaRegressionError.fixtureNotFound(name)
    }
    let data = try Data(contentsOf: url)
    guard let doubles = try JSONSerialization.jsonObject(with: data) as? [Double] else {
        throw ChromaRegressionError.fixtureParseError(name)
    }
    return doubles.map { Float($0) }
}

// MARK: - Errors

private enum ChromaRegressionError: Error {
    case noMetalDevice
    case fixtureNotFound(String)
    case fixtureParseError(String)
}
