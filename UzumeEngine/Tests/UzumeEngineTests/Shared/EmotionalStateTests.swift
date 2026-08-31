// EmotionalStateTests — Unit tests for EmotionalState quadrant classification.
// Verifies the computed quadrant property maps valence/arousal coordinates
// to the correct emotional quadrant in Russell's circumplex model.

import Testing
@testable import Shared

// MARK: - EmotionalState Quadrant Tests

@Test func test_quadrant_highValenceHighArousal_isHappy() {
    let state = EmotionalState(valence: 0.7, arousal: 0.8)
    #expect(state.quadrant == .happy,
            "Positive valence + positive arousal should be happy, got \(state.quadrant)")
}

@Test func test_quadrant_lowValenceLowArousal_isSad() {
    let state = EmotionalState(valence: -0.5, arousal: -0.6)
    #expect(state.quadrant == .sad,
            "Negative valence + negative arousal should be sad, got \(state.quadrant)")
}

@Test func test_quadrant_lowValenceHighArousal_isTense() {
    let state = EmotionalState(valence: -0.4, arousal: 0.9)
    #expect(state.quadrant == .tense,
            "Negative valence + positive arousal should be tense, got \(state.quadrant)")
}

@Test func test_quadrant_highValenceLowArousal_isCalm() {
    let state = EmotionalState(valence: 0.3, arousal: -0.2)
    #expect(state.quadrant == .calm,
            "Positive valence + negative arousal should be calm, got \(state.quadrant)")
}
