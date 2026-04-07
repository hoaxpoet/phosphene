// MoodClassifierTests — Unit tests for live-pipeline-trained CoreML mood classification.

import Testing
import Foundation
import CoreML
@testable import ML
@testable import Audio
@testable import Shared

@Test func test_init_loadsModel() throws {
    _ = try MoodClassifier()
}

@Test func test_classify_validFeatureVector_returnsEmotionalState() throws {
    let classifier = try MoodClassifier()
    let features: [Float] = [
        0.127, 0.206, 0.125, 0.038, 0.011, 0.005,
        0.118, 0.252, 0.531, 0.509
    ]
    let state = try classifier.classify(features: features)
    #expect(state.valence.isFinite)
    #expect(state.arousal.isFinite)
}

@Test func test_classify_valenceInRange_minus1To1() throws {
    let classifier = try MoodClassifier()
    let testCases: [[Float]] = [
        [0.20, 0.25, 0.15, 0.05, 0.02, 0.005, 0.17, 0.43, 0.48, 0.46],
        [0.07, 0.23, 0.19, 0.02, 0.001, 0.0002, 0.04, 0.09, 0.52, 0.48],
        [0.13, 0.21, 0.12, 0.04, 0.01, 0.005, 0.12, 0.25, 0.53, 0.51],
    ]
    for features in testCases {
        let state = try classifier.classify(features: features)
        #expect(state.valence >= -1.0 && state.valence <= 1.0)
    }
}

@Test func test_classify_arousalInRange_minus1To1() throws {
    let classifier = try MoodClassifier()
    let testCases: [[Float]] = [
        [0.20, 0.25, 0.15, 0.05, 0.02, 0.005, 0.17, 0.43, 0.48, 0.46],
        [0.07, 0.23, 0.19, 0.02, 0.001, 0.0002, 0.04, 0.09, 0.52, 0.48],
        [0.13, 0.21, 0.12, 0.04, 0.01, 0.005, 0.12, 0.25, 0.53, 0.51],
    ]
    for features in testCases {
        let state = try classifier.classify(features: features)
        #expect(state.arousal >= -1.0 && state.arousal <= 1.0)
    }
}

@Test func test_classify_partyRock_positiveValence() throws {
    let classifier = try MoodClassifier()
    // Love Shack average features (V=+0.8, A=+0.5).
    let features: [Float] = [
        0.1561, 0.1622, 0.1164, 0.0531, 0.0174, 0.0054,
        0.1655, 0.4259, 0.4841, 0.4598
    ]
    var state = EmotionalState.neutral
    for _ in 0..<50 { state = try classifier.classify(features: features) }
    #expect(state.valence > 0,
            "Party rock should have positive valence, got \(state.valence)")
}

@Test func test_classify_darkHaunting_negativeValence() throws {
    let classifier = try MoodClassifier()
    // Pyramid Song average features (V=-0.5, A=-0.7).
    let features: [Float] = [
        0.0749, 0.2286, 0.1892, 0.0157, 0.0009, 0.0002,
        0.0366, 0.0867, 0.5244, 0.4832
    ]
    var state = EmotionalState.neutral
    for _ in 0..<50 { state = try classifier.classify(features: features) }
    #expect(state.valence < 0,
            "Dark haunting track should have negative valence, got \(state.valence)")
}

@Test func test_conformsToMoodClassifying() throws {
    let classifier = try MoodClassifier()
    let proto: any MoodClassifying = classifier
    #expect(proto.currentState == EmotionalState.neutral)
}
