// TransitionPolicyTests — unit tests for DefaultTransitionPolicy (Increment 4.2).
//
// All tests use hand-built TransitionContext values — no real audio data or
// preset JSON files loaded. Fixture builders at the bottom keep tests compact.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Shared

// MARK: - Test Suite

@Suite("DefaultTransitionPolicy")
struct TransitionPolicyTests {

    private let policy = DefaultTransitionPolicy()

    // MARK: 1 — No decision when preset is fresh and confidence is low

    @Test("Returns nil when preset is fresh and structural confidence is below threshold")
    func noDecision_whenFreshPresetAndLowConfidence() {
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: 0.2,
            timeUntilBoundary: 1.5
        )
        #expect(policy.evaluate(context: ctx) == nil)
    }

    // MARK: 2 — No decision when boundary is too far ahead

    @Test("Returns nil when next boundary is beyond the lookahead window")
    func noDecision_whenBoundaryTooFar() {
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: 0.8,
            timeUntilBoundary: DefaultTransitionPolicy.lookaheadWindow + 0.1
        )
        #expect(policy.evaluate(context: ctx) == nil)
    }

    // MARK: 3 — No decision when boundary is in the past

    @Test("Returns nil when predicted boundary has already passed")
    func noDecision_whenBoundaryPast() {
        let captureTime: Float = 100.0
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: 0.8,
            captureTime: captureTime,
            predictedNextBoundary: captureTime - 0.5  // in the past
        )
        #expect(policy.evaluate(context: ctx) == nil)
    }

    // MARK: 4 — Structural boundary fires when confidence is high and boundary is near

    @Test("Returns structuralBoundary decision when confidence exceeds threshold and boundary is within window")
    func structuralBoundary_whenHighConfidenceAndBoundaryNear() {
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: 0.8,
            timeUntilBoundary: 2.0
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision != nil)
        #expect(decision?.trigger == .structuralBoundary)
    }

    // MARK: 5 — Confidence propagated from prediction to decision

    @Test("Decision confidence mirrors StructuralPrediction.confidence")
    func structuralDecision_confidencePropagated() {
        let predictionConfidence: Float = 0.73
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: predictionConfidence,
            timeUntilBoundary: 1.0
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision?.confidence == predictionConfidence)
    }

    // MARK: 6 — Duration expired fires timer fallback

    @Test("Returns durationExpired when elapsed time equals or exceeds declared duration")
    func durationExpired_whenElapsedExceedsDeclaredDuration() {
        let ctx = makeContext(
            elapsedPresetTime: 31,
            duration: 30,
            confidence: 0.0,          // no structural signal
            timeUntilBoundary: 999    // boundary far away
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision != nil)
        #expect(decision?.trigger == .durationExpired)
    }

    // MARK: 7 — Structural boundary beats duration expired when both are true

    @Test("Structural boundary trigger takes priority over duration-expired fallback")
    func structuralBoundary_preferredOverDurationExpired() {
        let ctx = makeContext(
            elapsedPresetTime: 35,    // past the declared 30 s duration
            duration: 30,
            confidence: 0.8,          // also a valid structural signal
            timeUntilBoundary: 1.0
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision?.trigger == .structuralBoundary)
    }

    // MARK: 8 — Crossfade duration scales with energy

    @Test("Higher energy produces a shorter crossfade duration")
    func crossfadeDuration_higherEnergyMeansShorter() {
        let ctxLow = makeContext(
            elapsedPresetTime: 5, duration: 30,
            confidence: 0.8, timeUntilBoundary: 2.0,
            energy: 0.1
        )
        let ctxHigh = makeContext(
            elapsedPresetTime: 5, duration: 30,
            confidence: 0.8, timeUntilBoundary: 2.0,
            energy: 0.9
        )
        let durationLow  = policy.evaluate(context: ctxLow)?.duration  ?? 0
        let durationHigh = policy.evaluate(context: ctxHigh)?.duration ?? 0
        // Both must be crossfades (default affordance) so duration is non-zero
        #expect(durationLow > durationHigh)
    }

    // MARK: 9 — Cut style selected at high energy when preset affords it

    @Test("Selects cut style when energy is high and cut is an afforded transition")
    func cutStyle_atHighEnergyWithCutAffordance() {
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: 0.8,
            timeUntilBoundary: 0.5,
            energy: Float(DefaultTransitionPolicy.cutEnergyThreshold) + 0.1,
            affordances: [.cut, .crossfade]
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision?.style == .cut)
        #expect(decision?.duration == 0)
    }

    // MARK: 10 — Crossfade fallback when cut is not afforded

    @Test("Falls back to crossfade when energy is high but cut is not in affordances")
    func crossfadeFallback_whenCutNotAfforded() {
        let ctx = makeContext(
            elapsedPresetTime: 5,
            duration: 30,
            confidence: 0.8,
            timeUntilBoundary: 0.5,
            energy: Float(DefaultTransitionPolicy.cutEnergyThreshold) + 0.1,
            affordances: [.crossfade]
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision?.style == .crossfade)
    }

    // MARK: 11 — Duration-expired decision scheduled at capture time

    @Test("Duration-expired decision has scheduledAt equal to captureTime")
    func durationExpired_scheduledAtCaptureTime() {
        let captureTime: Float = 87.5
        let ctx = makeContext(
            elapsedPresetTime: 31,
            duration: 30,
            confidence: 0.0,
            captureTime: captureTime,
            predictedNextBoundary: captureTime + 999  // far away — forces timer path
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision?.trigger == .durationExpired)
        #expect(decision?.scheduledAt == captureTime)
    }

    // MARK: 12 — Timer fallback confidence is always 1.0

    @Test("Duration-expired decision always reports confidence 1.0")
    func durationExpired_confidenceIsAlwaysOne() {
        let ctx = makeContext(
            elapsedPresetTime: 31,
            duration: 30,
            confidence: 0.0,
            timeUntilBoundary: 999
        )
        let decision = policy.evaluate(context: ctx)
        #expect(decision?.confidence == 1.0)
    }
}

// MARK: - Fixture Builders

/// Makes a `TransitionContext` using `timeUntilBoundary` relative to `captureTime`.
/// Use the `captureTime` + `predictedNextBoundary` overload for absolute-coordinate tests.
private func makeContext(
    elapsedPresetTime: TimeInterval = 5,
    duration: Int = 30,
    confidence: Float = 0.0,
    captureTime: Float = 100.0,
    timeUntilBoundary: Float = 999,    // large default = no boundary near
    energy: Float = 0.3,
    affordances: [TransitionAffordance] = [.crossfade]
) -> TransitionContext {
    let prediction = StructuralPrediction(
        sectionIndex: 1,
        sectionStartTime: captureTime - 10,
        predictedNextBoundary: captureTime + timeUntilBoundary,
        confidence: confidence
    )
    return TransitionContext(
        currentPreset: makePreset(duration: duration, affordances: affordances),
        elapsedPresetTime: elapsedPresetTime,
        prediction: prediction,
        energy: energy,
        captureTime: captureTime
    )
}

/// Overload for tests that need to specify `predictedNextBoundary` in absolute coordinates.
private func makeContext(
    elapsedPresetTime: TimeInterval = 5,
    duration: Int = 30,
    confidence: Float = 0.0,
    captureTime: Float,
    predictedNextBoundary: Float,
    energy: Float = 0.3,
    affordances: [TransitionAffordance] = [.crossfade]
) -> TransitionContext {
    let prediction = StructuralPrediction(
        sectionIndex: 1,
        sectionStartTime: captureTime - 10,
        predictedNextBoundary: predictedNextBoundary,
        confidence: confidence
    )
    return TransitionContext(
        currentPreset: makePreset(duration: duration, affordances: affordances),
        elapsedPresetTime: elapsedPresetTime,
        prediction: prediction,
        energy: energy,
        captureTime: captureTime
    )
}

private func makePreset(
    name: String = "TestPreset",
    duration: Int = 30,
    affordances: [TransitionAffordance] = [.crossfade]
) -> PresetDescriptor {
    let affordancesJSON = affordances
        .map { "\"\($0.rawValue)\"" }
        .joined(separator: ", ")
    let json = """
    {
        "name": "\(name)",
        "family": "abstract",
        "duration": \(duration),
        "transition_affordances": [\(affordancesJSON)],
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}
