// StubMoodClassifier — Test double for MoodClassifying protocol.
// Returns a configurable canned EmotionalState for orchestrator testing.

import Foundation
@testable import Audio
@testable import Shared

final class StubMoodClassifier: MoodClassifying, @unchecked Sendable {

    // MARK: - Tracking

    /// Number of times classify() was called.
    private(set) var classifyCallCount = 0

    /// Last feature array received.
    private(set) var lastFeatures: [Float]?

    // MARK: - Configurable Output

    /// The emotional state returned by classify(). Defaults to neutral.
    var cannedState: EmotionalState = .neutral

    /// If set, classify() throws this error instead of returning cannedState.
    var errorToThrow: MoodClassificationError?

    // MARK: - MoodClassifying

    private(set) var currentState: EmotionalState = .neutral

    func classify(features: [Float]) throws -> EmotionalState {
        classifyCallCount += 1
        lastFeatures = features

        if let error = errorToThrow {
            throw error
        }

        currentState = cannedState
        return cannedState
    }
}
