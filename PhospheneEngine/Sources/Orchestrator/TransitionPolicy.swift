// TransitionPolicy — decides when and how to transition between presets.
// Per D-014: decision is fully inspectable (trigger, timing, style, duration,
// confidence, rationale). No black boxes.
//
// Inputs:  current PresetDescriptor + elapsed time, StructuralPrediction,
//          energy level, capture-clock timestamp.
// Output:  TransitionDecision? — nil means "not yet".
//
// Priority: structural boundary (when confidence is sufficient) beats the
// timer fallback. The timer fires only when no reliable boundary is predicted.

import Foundation
import Shared
import Presets

// MARK: - TransitionContext

/// Immutable snapshot of the state the policy evaluates each frame.
///
/// `captureTime` is in the same coordinate system as
/// `StructuralPrediction.predictedNextBoundary` — seconds since capture start.
public struct TransitionContext: Sendable {

    /// The currently playing preset.
    public let currentPreset: PresetDescriptor

    /// Seconds this preset has been playing.
    public let elapsedPresetTime: TimeInterval

    /// Latest structural-analysis prediction for the active track.
    public let prediction: StructuralPrediction

    /// Normalized energy in [0, 1]. Higher values produce shorter crossfades
    /// and a preference for cuts over crossfades.
    public let energy: Float

    /// Current time in seconds since capture start. Shared coordinate system
    /// with `StructuralPrediction` timestamps.
    public let captureTime: Float

    public init(
        currentPreset: PresetDescriptor,
        elapsedPresetTime: TimeInterval,
        prediction: StructuralPrediction,
        energy: Float,
        captureTime: Float
    ) {
        self.currentPreset = currentPreset
        self.elapsedPresetTime = elapsedPresetTime
        self.prediction = prediction
        self.energy = energy
        self.captureTime = captureTime
    }
}

// MARK: - TransitionDecision

/// A fully-inspectable transition directive from `TransitionDeciding`.
public struct TransitionDecision: Sendable, Equatable {

    // MARK: Trigger

    /// What caused the transition to be scheduled.
    public enum Trigger: String, Sendable, Equatable {
        /// A `StructuralPrediction` boundary with sufficient confidence is imminent.
        case structuralBoundary
        /// The preset has played past its declared `duration`; timer fallback.
        case durationExpired
    }

    // MARK: Fields

    /// What caused this decision.
    public let trigger: Trigger

    /// When to begin the transition, in seconds since capture start.
    ///
    /// For crossfade/morph, this is offset *before* the boundary so the
    /// crossfade completes at the boundary. For cut, this equals the boundary.
    public let scheduledAt: Float

    /// Visual transition style to use.
    public let style: TransitionAffordance

    /// Duration of the transition in seconds. Always 0 for `.cut`.
    public let duration: TimeInterval

    /// Confidence in this decision [0, 1]. Mirrors `StructuralPrediction.confidence`
    /// for structural triggers; 1.0 for timer-based triggers.
    public let confidence: Float

    /// Human-readable explanation for logging and debugging.
    public let rationale: String
}

// MARK: - TransitionDeciding

/// Protocol for transition policy implementations.
///
/// Conforming types must be `Sendable`. Returning `nil` means "no transition yet";
/// return a `TransitionDecision` to signal that a transition should be scheduled.
public protocol TransitionDeciding: Sendable {
    /// Evaluate the current state and return a transition decision, or nil if
    /// no transition should be scheduled now.
    func evaluate(context: TransitionContext) -> TransitionDecision?
}

// MARK: - DefaultTransitionPolicy

/// Concrete transition policy.
///
/// **Priority:** structural boundary (preferred) → duration-expired fallback.
///
/// Structural trigger fires when `StructuralPrediction.confidence` exceeds
/// `structuralConfidenceThreshold` and the predicted boundary is within
/// `lookaheadWindow` seconds.
///
/// Style is negotiated from the current preset's `transitionAffordances`:
/// - High energy (> `cutEnergyThreshold`): prefers `.cut` → `.crossfade` → first afforded.
/// - Low energy: prefers `.crossfade` → `.morph` → first afforded.
/// - Fallback when the preset declares no affordances: `.crossfade`.
///
/// Crossfade duration scales linearly from `baseCrossfadeDuration` (energy=0)
/// down to `minCrossfadeDuration` (energy=1).
public struct DefaultTransitionPolicy: TransitionDeciding {

    // MARK: Tuning constants

    /// Minimum `StructuralPrediction.confidence` required to trigger a structural
    /// boundary transition. Values below this fall through to the timer fallback.
    public static let structuralConfidenceThreshold: Float = 0.5

    /// How far ahead (seconds) the policy looks for an imminent boundary.
    /// Matches the `LookaheadBuffer` delay of 2.5 s.
    public static let lookaheadWindow: Float = 2.5

    /// Crossfade/morph duration at zero energy (slowest, most relaxed).
    public static let baseCrossfadeDuration: TimeInterval = 2.0

    /// Crossfade/morph duration at peak energy (fastest).
    public static let minCrossfadeDuration: TimeInterval = 0.5

    /// Energy level above which the policy prefers a `.cut` over a `.crossfade`.
    /// Raised from 0.7 → 0.85 (QR.2/D-080): 0.70 fired on moderately-busy sections where
    /// a cut felt abrupt; 0.85 reserves hard cuts for peak-energy climax moments only.
    public static let cutEnergyThreshold: Float = 0.85

    // MARK: TransitionDeciding

    public init() {}

    public func evaluate(context: TransitionContext) -> TransitionDecision? {
        if let decision = structuralBoundaryDecision(context: context) {
            return decision
        }
        return durationExpiredDecision(context: context)
    }

    // MARK: - Private helpers

    private func structuralBoundaryDecision(context: TransitionContext) -> TransitionDecision? {
        let prediction = context.prediction
        guard prediction.confidence >= Self.structuralConfidenceThreshold else { return nil }

        let timeUntilBoundary = prediction.predictedNextBoundary - context.captureTime
        guard timeUntilBoundary >= 0, timeUntilBoundary <= Self.lookaheadWindow else { return nil }

        let style = preferredStyle(
            affordances: context.currentPreset.transitionAffordances,
            energy: context.energy
        )
        let xfadeDuration = crossfadeDuration(energy: context.energy, style: style)

        // For fades start before the boundary so the blend completes exactly at it.
        // For cut, schedule at the boundary itself (no lead-in needed).
        let leadIn = style == .cut ? 0.0 : Float(xfadeDuration)
        let scheduledAt = context.captureTime + max(0, timeUntilBoundary - leadIn)

        return TransitionDecision(
            trigger: .structuralBoundary,
            scheduledAt: scheduledAt,
            style: style,
            duration: xfadeDuration,
            confidence: prediction.confidence,
            rationale: "Structural boundary in \(String(format: "%.2f", timeUntilBoundary))s "
                     + "(confidence \(String(format: "%.2f", prediction.confidence))); "
                     + "section \(prediction.sectionIndex) → \(prediction.sectionIndex + 1)"
        )
    }

    private func durationExpiredDecision(context: TransitionContext) -> TransitionDecision? {
        guard context.elapsedPresetTime >= TimeInterval(context.currentPreset.duration) else {
            return nil
        }

        let style = preferredStyle(
            affordances: context.currentPreset.transitionAffordances,
            energy: context.energy
        )
        let xfadeDuration = crossfadeDuration(energy: context.energy, style: style)

        return TransitionDecision(
            trigger: .durationExpired,
            scheduledAt: context.captureTime,
            style: style,
            duration: xfadeDuration,
            confidence: 1.0,
            rationale: "Preset \"\(context.currentPreset.name)\" reached declared duration "
                     + "(\(context.currentPreset.duration)s)"
        )
    }

    // MARK: - Style selection

    /// Returns the best afforded style for the given energy level.
    ///
    /// High energy → `.cut` preferred.
    /// Low energy  → `.crossfade` preferred.
    /// Falls back to `.crossfade` when the preset declares no affordances.
    private func preferredStyle(
        affordances: [TransitionAffordance],
        energy: Float
    ) -> TransitionAffordance {
        guard !affordances.isEmpty else { return .crossfade }

        if energy > Self.cutEnergyThreshold {
            return affordances.first(where: { $0 == .cut })
                ?? affordances.first(where: { $0 == .crossfade })
                ?? affordances[0]
        } else {
            return affordances.first(where: { $0 == .crossfade })
                ?? affordances.first(where: { $0 == .morph })
                ?? affordances[0]
        }
    }

    // MARK: - Duration scaling

    /// Linearly interpolates between `baseCrossfadeDuration` (energy=0) and
    /// `minCrossfadeDuration` (energy=1). Returns 0 for `.cut`.
    private func crossfadeDuration(energy: Float, style: TransitionAffordance) -> TimeInterval {
        guard style != .cut else { return 0 }
        let energyNorm = Double(min(1.0, max(0.0, energy)))
        return Self.baseCrossfadeDuration * (1.0 - energyNorm) + Self.minCrossfadeDuration * energyNorm
    }
}
