// MoodClassifierTests — Unit tests for DEAM-trained CoreML mood classification.
// Tests model loading, output validity and range, emotional quadrant mapping
// for known feature vectors, and protocol conformance.

import Testing
import Foundation
import CoreML
@testable import ML
@testable import Audio
@testable import Shared

// MARK: - MoodClassifier Unit Tests

@Test func test_init_loadsModel() throws {
    _ = try MoodClassifier()
}

@Test func test_classify_validFeatureVector_returnsEmotionalState() throws {
    let classifier = try MoodClassifier()

    // DEAM-mean features (should produce near-neutral output).
    let features: [Float] = [
        0.127, 0.212, 0.121, 0.031, 0.007, 0.002,  // 6-band energy (DEAM means)
        0.081,                                         // centroid (normalized by Nyquist)
        0.127,                                         // flux (with 2/N FFT normalization)
        0.476, 0.480                                   // major/minor correlations
    ]
    let state = try classifier.classify(features: features)

    #expect(state.valence.isFinite, "Valence should be finite, got \(state.valence)")
    #expect(state.arousal.isFinite, "Arousal should be finite, got \(state.arousal)")
}

@Test func test_classify_valenceInRange_minus1To1() throws {
    let classifier = try MoodClassifier()

    // Test with varied feature vectors.
    let testCases: [[Float]] = [
        [0.20, 0.25, 0.15, 0.05, 0.01, 0.003, 0.12, 0.25, 0.70, 0.40],   // energetic major
        [0.05, 0.10, 0.05, 0.01, 0.003, 0.001, 0.04, 0.03, 0.30, 0.60],   // quiet minor
        [0.15, 0.22, 0.12, 0.03, 0.007, 0.002, 0.08, 0.13, 0.50, 0.50],   // average
    ]
    for features in testCases {
        let state = try classifier.classify(features: features)
        #expect(state.valence >= -1.0 && state.valence <= 1.0,
                "Valence should be in [-1,1], got \(state.valence)")
    }
}

@Test func test_classify_arousalInRange_minus1To1() throws {
    let classifier = try MoodClassifier()

    let testCases: [[Float]] = [
        [0.20, 0.25, 0.15, 0.05, 0.01, 0.003, 0.12, 0.25, 0.70, 0.40],
        [0.05, 0.10, 0.05, 0.01, 0.003, 0.001, 0.04, 20.0, 0.30, 0.60],
        [0.15, 0.22, 0.12, 0.03, 0.007, 0.002, 0.08, 65.0, 0.50, 0.50],
    ]
    for features in testCases {
        let state = try classifier.classify(features: features)
        #expect(state.arousal >= -1.0 && state.arousal <= 1.0,
                "Arousal should be in [-1,1], got \(state.arousal)")
    }
}

@Test func test_classify_highEnergyMajorKey_positiveValence() throws {
    let classifier = try MoodClassifier()

    // High energy, bright timbre, strong major key — DEAM-calibrated.
    // Flux uses 2/N FFT normalization (same scale as live pipeline).
    let features: [Float] = [
        0.20, 0.26, 0.18, 0.06, 0.015, 0.004,  // above-average energy
        0.12,                                      // bright centroid
        0.30,                                      // high flux (2/N normalized)
        0.70, 0.35                                 // strong major lean
    ]

    // Classify multiple times to overcome EMA smoothing.
    var state = EmotionalState.neutral
    for _ in 0..<50 {
        state = try classifier.classify(features: features)
    }

    #expect(state.valence > 0,
            "Major-key bright signal should have positive valence, got \(state.valence)")
}

@Test func test_classify_lowEnergyMinorKey_negativeValence() throws {
    let classifier = try MoodClassifier()

    // Low energy, dark timbre, strong minor key — DEAM-calibrated.
    let features: [Float] = [
        0.06, 0.15, 0.06, 0.015, 0.003, 0.001,  // below-average energy
        0.04,                                       // dark centroid
        0.03,                                       // low flux (2/N normalized)
        0.30, 0.65                                  // strong minor lean
    ]

    var state = EmotionalState.neutral
    for _ in 0..<50 {
        state = try classifier.classify(features: features)
    }

    #expect(state.valence < 0,
            "Minor-key dark signal should have negative valence, got \(state.valence)")
}

@Test func test_conformsToMoodClassifying() throws {
    let classifier = try MoodClassifier()

    let proto: any MoodClassifying = classifier
    #expect(proto.currentState == EmotionalState.neutral,
            "Initial state should be neutral")
}
