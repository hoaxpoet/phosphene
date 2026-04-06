// MoodClassifierTests — Unit tests for CoreML mood classification pipeline.
// Tests model loading, compute unit configuration, output validity and range,
// emotional quadrant mapping for known inputs, and protocol conformance.

import Testing
import Foundation
import CoreML
@testable import ML
@testable import Audio
@testable import Shared

// MARK: - MoodClassifier Unit Tests

@Test func test_init_loadsModel() throws {
    // Should not throw — model is bundled as a resource.
    _ = try MoodClassifier()
}

@Test func test_classify_validFeatureVector_returnsEmotionalState() throws {
    let classifier = try MoodClassifier()

    // Mid-range features (all 0.5).
    let features = [Float](repeating: 0.5, count: MoodClassifier.featureCount)
    let state = try classifier.classify(features: features)

    #expect(state.valence.isFinite, "Valence should be finite, got \(state.valence)")
    #expect(state.arousal.isFinite, "Arousal should be finite, got \(state.arousal)")
}

@Test func test_classify_valenceInRange_minus1To1() throws {
    let classifier = try MoodClassifier()

    // Run 50 random inputs through repeated classification to build up EMA state.
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<50 {
        var features = [Float](repeating: 0, count: MoodClassifier.featureCount)
        for j in 0..<features.count {
            features[j] = Float.random(in: 0...1, using: &rng)
        }
        let state = try classifier.classify(features: features)
        #expect(state.valence >= -1.0 && state.valence <= 1.0,
                "Valence should be in [-1,1], got \(state.valence)")
    }
}

@Test func test_classify_arousalInRange_minus1To1() throws {
    let classifier = try MoodClassifier()

    var rng = SystemRandomNumberGenerator()
    for _ in 0..<50 {
        var features = [Float](repeating: 0, count: MoodClassifier.featureCount)
        for j in 0..<features.count {
            features[j] = Float.random(in: 0...1, using: &rng)
        }
        let state = try classifier.classify(features: features)
        #expect(state.arousal >= -1.0 && state.arousal <= 1.0,
                "Arousal should be in [-1,1], got \(state.arousal)")
    }
}

@Test func test_classify_highEnergyMajorKey_happyQuadrant() throws {
    let classifier = try MoodClassifier()

    var features = [Float](repeating: 0, count: MoodClassifier.featureCount)

    // High energy across all 6 bands.
    for i in 0..<6 { features[i] = 0.7 }

    // Bright timbre.
    features[6] = 0.6   // spectralCentroid
    features[7] = 0.5   // spectralFlux

    // Strong major key correlation.
    features[8] = 0.85  // majorKeyCorrelation
    features[9] = 0.25  // minorKeyCorrelation

    // Classify multiple times to overcome EMA smoothing toward neutral.
    var state = EmotionalState.neutral
    for _ in 0..<30 {
        state = try classifier.classify(features: features)
    }

    #expect(state.valence > 0,
            "Major-key high-energy should have positive valence, got \(state.valence)")
    #expect(state.arousal > 0,
            "Major-key high-energy should have positive arousal, got \(state.arousal)")
    #expect(state.quadrant == .happy,
            "Should be in happy quadrant, got \(state.quadrant)")
}

@Test func test_classify_lowEnergyMinorKey_sadQuadrant() throws {
    let classifier = try MoodClassifier()

    var features = [Float](repeating: 0, count: MoodClassifier.featureCount)

    // Low energy.
    for i in 0..<6 { features[i] = 0.15 }

    // Dark timbre.
    features[6] = 0.15   // spectralCentroid
    features[7] = 0.1    // spectralFlux

    // Strong minor key correlation.
    features[8] = 0.20   // majorKeyCorrelation
    features[9] = 0.80   // minorKeyCorrelation

    // Classify multiple times to overcome EMA smoothing.
    var state = EmotionalState.neutral
    for _ in 0..<30 {
        state = try classifier.classify(features: features)
    }

    #expect(state.valence < 0,
            "Minor-key low-energy should have negative valence, got \(state.valence)")
    #expect(state.arousal < 0,
            "Minor-key low-energy should have negative arousal, got \(state.arousal)")
    #expect(state.quadrant == .sad,
            "Should be in sad quadrant, got \(state.quadrant)")
}

@Test func test_conformsToMoodClassifying() throws {
    let classifier = try MoodClassifier()

    // Verify protocol conformance by assigning to protocol-typed variable.
    let proto: any MoodClassifying = classifier
    #expect(proto.currentState == EmotionalState.neutral,
            "Initial state should be neutral")
}
