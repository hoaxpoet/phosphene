// ChromaExtractorTests — Unit tests for chroma vector extraction and key estimation.
// Uses synthetic magnitude arrays with known pitch content.
//
// NOTE: At 48kHz/1024-point FFT, bin resolution is 46.875 Hz. Below ~500 Hz,
// bin centers don't align well with musical pitches. Tests use higher octaves
// (C5+, 523+ Hz) where bin-to-pitch mapping is accurate.

import Testing
import Foundation
@testable import DSP

// MARK: - Helpers

/// Create a magnitude array with peaks at bins closest to given frequencies.
/// Automatically maps frequency → bin index for 48kHz/1024 FFT.
private func magnitudesForFrequencies(_ freqs: [(freq: Float, mag: Float)]) -> [Float] {
    let binResolution: Float = 48000.0 / 1024.0
    let peaks = freqs.map { pair -> (bin: Int, magnitude: Float) in
        let bin = Int(roundf(pair.freq / binResolution))
        return (bin: bin, magnitude: pair.mag)
    }
    return AudioFixtures.syntheticMagnitudes(peaks: peaks)
}

// MARK: - Chroma Tests

@Test func chroma_CMajorChord_peakAtCEG() {
    let extractor = ChromaExtractor()
    // Use higher octaves where bin resolution maps accurately to pitch classes.
    // C5=523.2→bin11→C(0), E5=659.3→bin14→E(4), G5=784→bin17→G(7)
    // C6=1046.5→bin22→C(0), E6=1318.5→bin28→E(4), G6=1568→bin33→G(7)
    let magnitudes = magnitudesForFrequencies([
        (523.2, 1.0), (1046.5, 1.0), (2093.0, 0.8),  // C
        (659.3, 1.0), (1318.5, 0.8),                   // E
        (784.0, 1.0), (1568.0, 0.8),                   // G
    ])
    let result = extractor.process(magnitudes: magnitudes)

    // Pitch classes: C=0, E=4, G=7
    let cEnergy = result.chroma[0]
    let eEnergy = result.chroma[4]
    let gEnergy = result.chroma[7]

    // These three should be the highest.
    for i in 0..<12 where ![0, 4, 7].contains(i) {
        #expect(cEnergy > result.chroma[i],
                "C (chroma[0]=\(cEnergy)) should exceed chroma[\(i)]=\(result.chroma[i])")
    }
    #expect(eEnergy > 0.3, "E should have meaningful energy, got \(eEnergy)")
    #expect(gEnergy > 0.3, "G should have meaningful energy, got \(gEnergy)")
}

@Test func chroma_AMinorChord_peakAtACE() {
    let extractor = ChromaExtractor()
    // A4=440→bin9→G#?... Use A5=880→bin19→A(9), C5=523.2→bin11→C(0), E5=659.3→bin14→E(4)
    let magnitudes = magnitudesForFrequencies([
        (880.0, 1.0), (1760.0, 0.8),                   // A
        (523.2, 1.0), (1046.5, 0.8),                   // C
        (659.3, 1.0), (1318.5, 0.8),                   // E
    ])
    let result = extractor.process(magnitudes: magnitudes)

    // Pitch classes: A=9, C=0, E=4
    let aEnergy = result.chroma[9]
    let cEnergy = result.chroma[0]
    let eEnergy = result.chroma[4]

    let nonChordMax = result.chroma.enumerated()
        .filter { ![9, 0, 4].contains($0.offset) }
        .map { $0.element }
        .max() ?? 0

    #expect(aEnergy > nonChordMax, "A should be stronger than non-chord tones, got \(aEnergy) vs \(nonChordMax)")
    #expect(cEnergy > nonChordMax, "C should be stronger than non-chord tones, got \(cEnergy) vs \(nonChordMax)")
    #expect(eEnergy > nonChordMax, "E should be stronger than non-chord tones, got \(eEnergy) vs \(nonChordMax)")
}

@Test func chroma_silence_allBinsNearZero() {
    let extractor = ChromaExtractor()
    let magnitudes = [Float](repeating: 0, count: 512)
    let result = extractor.process(magnitudes: magnitudes)

    for i in 0..<12 {
        #expect(result.chroma[i] < 0.001,
                "Chroma bin \(i) should be near zero for silence, got \(result.chroma[i])")
    }
}

// MARK: - Key Estimation Tests

@Test func keyEstimation_CMajorChord_returnsC() {
    let extractor = ChromaExtractor()
    // Strong C major triad in higher octaves.
    let magnitudes = magnitudesForFrequencies([
        (523.2, 1.0), (1046.5, 1.0), (2093.0, 0.8),  // C (strong root)
        (659.3, 0.7), (1318.5, 0.5),                   // E
        (784.0, 0.7), (1568.0, 0.5),                   // G
    ])
    let result = extractor.process(magnitudes: magnitudes)

    #expect(result.estimatedKey != nil, "Key estimation should return a value for a clear chord")
    if let key = result.estimatedKey {
        // C major is the expected strongest match.
        #expect(key == "C major", "Key should be C major, got \(key)")
    }
}

@Test func keyEstimation_AMinorScale_returnsAm() {
    let extractor = ChromaExtractor()
    // A minor: strong A triad (A, C, E) with weaker scale tones.
    // Use octave 5+ for reliable bin-to-pitch mapping.
    let magnitudes = magnitudesForFrequencies([
        (880.0, 1.0), (1760.0, 0.9),                   // A (strong root)
        (523.2, 0.7), (1046.5, 0.6),                   // C (minor third)
        (659.3, 0.7), (1318.5, 0.6),                   // E (fifth)
        (587.3, 0.3),                                    // D
        (698.5, 0.3),                                    // F
        (784.0, 0.3),                                    // G
        (493.9, 0.2),                                    // B
    ])
    let result = extractor.process(magnitudes: magnitudes)

    #expect(result.estimatedKey != nil, "Key should be estimated for a clear scale")
    if let key = result.estimatedKey {
        // Accept A minor or C major (relative major — they share the same pitch set).
        let acceptable = key == "A minor" || key == "C major"
        #expect(acceptable, "Key should be A minor or C major, got \(key)")
    }
}

// MARK: - Determinism

@Test func chroma_deterministic() {
    let magnitudes = magnitudesForFrequencies([
        (880.0, 1.0), (1760.0, 0.5), (1318.5, 0.7),
    ])

    let extractor1 = ChromaExtractor()
    let result1 = extractor1.process(magnitudes: magnitudes)

    let extractor2 = ChromaExtractor()
    let result2 = extractor2.process(magnitudes: magnitudes)

    for i in 0..<12 {
        #expect(result1.chroma[i] == result2.chroma[i],
                "Chroma bin \(i) should be deterministic")
    }
    #expect(result1.estimatedKey == result2.estimatedKey, "Key estimation should be deterministic")
}
