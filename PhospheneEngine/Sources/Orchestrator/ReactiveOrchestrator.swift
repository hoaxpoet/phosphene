// ReactiveOrchestrator — Ad-hoc reactive mode: stateless preset selection from live MIR data.
//
// Used when no pre-planned session exists (user launched without a connected playlist).
// evaluate() is a pure function — all state lives in VisualizerEngine+Orchestrator.
//
// Accumulation states gate confidence to prevent premature switches before enough MIR
// data has accumulated. See D-036 for design rationale.

import Foundation
import Presets
import Session
import Shared

// MARK: - ReactiveAccumulationState

/// Confidence tier derived from elapsed session time.
///
/// Governs whether `DefaultReactiveOrchestrator.evaluate()` may suggest a preset switch.
public enum ReactiveAccumulationState: String, Sendable, Hashable, Codable {
    /// 0–15 s: not enough MIR data. `evaluate()` always returns a hold.
    case listening
    /// 15–30 s: partial signal. Suggestions are made with reduced confidence (0.3–1.0 ramp).
    case ramping
    /// 30 s+: full-confidence scoring.
    case full

    /// Derive the accumulation state from elapsed session time.
    public init(elapsedTime: TimeInterval) {
        if elapsedTime < DefaultReactiveOrchestrator.listeningDuration {
            self = .listening
        } else if elapsedTime < DefaultReactiveOrchestrator.fullConfidenceDuration {
            self = .ramping
        } else {
            self = .full
        }
    }
}

// MARK: - ReactiveDecision

/// A suggestion returned by `ReactiveOrchestrating.evaluate()` for a single call.
public struct ReactiveDecision: Sendable {
    /// Preset to switch to, or nil when the orchestrator recommends holding the current preset.
    public let suggestedPreset: PresetDescriptor?
    /// Session-relative time to schedule the transition, or nil when no switch is pending.
    public let scheduleTransitionAt: TimeInterval?
    /// Current accumulation tier at time of evaluation.
    public let accumulationState: ReactiveAccumulationState
    /// Confidence in the suggestion (0–1); ramps up over the first 30 s of the session.
    public let confidence: Float
    /// Human-readable explanation for logging.
    public let reason: String

    public init(
        suggestedPreset: PresetDescriptor?,
        scheduleTransitionAt: TimeInterval?,
        accumulationState: ReactiveAccumulationState,
        confidence: Float,
        reason: String
    ) {
        self.suggestedPreset = suggestedPreset
        self.scheduleTransitionAt = scheduleTransitionAt
        self.accumulationState = accumulationState
        self.confidence = confidence
        self.reason = reason
    }
}

// MARK: - ReactiveOrchestrating

/// Protocol for reactive orchestrator implementations.
///
/// Conforming types must be `Sendable`. `evaluate()` must be a pure function:
/// no `Date.now()`, no randomness, no external mutable state reads.
public protocol ReactiveOrchestrating: Sendable {

    // swiftlint:disable function_parameter_count
    /// Evaluate live MIR data and suggest a preset switch if warranted.
    ///
    /// - Parameters:
    ///   - liveMood: Current `EmotionalState` from the live mood classifier.
    ///   - liveBoundary: Latest `StructuralPrediction` from the live MIR pipeline.
    ///   - elapsedSessionTime: Seconds since the reactive session began (wall-clock).
    ///   - currentPreset: Currently displayed preset, or nil if none has been set.
    ///   - catalog: Full preset catalog to score against.
    ///   - deviceTier: Apple Silicon generation for complexity-cost exclusion gating.
    ///   - includeUncertifiedPresets: When `true`, uncertified presets are eligible for
    ///     selection. Mirrors `SettingsStore.showUncertifiedPresets`. Default `false`.
    ///   - liveStemFeatures: Live `StemFeatures` snapshot from the real-time stem analyzer.
    ///     Pass `nil` until the analyzer has converged (~10 s). When non-nil, stem deviation
    ///     fields are used for scoring, making stem-affinity-bearing presets eligible
    ///     for selection in reactive mode (QR.2/D-080).
    /// - Returns: A `ReactiveDecision` — `suggestedPreset` is nil when holding.
    func evaluate(
        liveMood: EmotionalState,
        liveBoundary: StructuralPrediction,
        elapsedSessionTime: TimeInterval,
        currentPreset: PresetDescriptor?,
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        includeUncertifiedPresets: Bool,
        liveStemFeatures: StemFeatures?
    ) -> ReactiveDecision
    // swiftlint:enable function_parameter_count
}

// MARK: - DefaultReactiveOrchestrator

/// Concrete `ReactiveOrchestrating` implementation.
///
/// **Accumulation gating:** the first 15 s (`.listening`) always hold.
/// Confidence ramps 0 → 0.3 during 0–15 s and 0.3 → 1.0 during 15–30 s;
/// full confidence from 30 s onward.
///
/// **Switch conditions (past `.listening`):**
/// 1. Score gap: best-catalog-score − current-preset-score > `minScoreGapForSwitch`.
/// 2. Structural boundary: `liveBoundary.confidence ≥ boundaryConfidenceThreshold`.
/// Either condition alone is sufficient to suggest a switch.
///
/// **`currentPreset == nil`:** always suggest the top-ranked preset once past `.listening`,
/// regardless of score gap, since there is nothing to compare against.
///
/// See D-036 for design rationale.
public struct DefaultReactiveOrchestrator: ReactiveOrchestrating {

    // MARK: - Tuning constants

    /// Sessions shorter than this are in the `.listening` state — no suggestions.
    public static let listeningDuration: TimeInterval = 15.0

    /// Sessions shorter than this are in the `.ramping` state; beyond is `.full`.
    public static let fullConfidenceDuration: TimeInterval = 30.0

    /// Minimum score advantage over the current preset to suggest a switch.
    /// Higher than `LiveAdapter`'s 0.15 because reactive scoring is based on mood
    /// only (no BPM, stems, or section data), warranting a more decisive threshold.
    public static let minScoreGapForSwitch: Float = 0.20

    /// Minimum `StructuralPrediction.confidence` to treat a boundary as actionable.
    public static let boundaryConfidenceThreshold: Float = 0.5

    /// Minimum score advantage required for a boundary-only switch (QR.2/D-080).
    /// The original gate (`boundaryFired` alone) allowed random structural boundaries
    /// to force switches even when the current preset scored better than any alternative.
    public static let minBoundaryScoreGap: Float = 0.05

    // MARK: - Dependencies

    private let scorer: any PresetScoring

    // MARK: - Init

    public init(scorer: any PresetScoring = DefaultPresetScorer()) {
        self.scorer = scorer
    }

    // MARK: - ReactiveOrchestrating

    // swiftlint:disable function_parameter_count
    public func evaluate(
        liveMood: EmotionalState,
        liveBoundary: StructuralPrediction,
        elapsedSessionTime: TimeInterval,
        currentPreset: PresetDescriptor?,
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        includeUncertifiedPresets: Bool = false,
        liveStemFeatures: StemFeatures? = nil
    ) -> ReactiveDecision {
        let state = ReactiveAccumulationState(elapsedTime: elapsedSessionTime)
        let confidence = Self.computeConfidence(elapsed: elapsedSessionTime)

        if state == .listening {
            let remaining = Self.listeningDuration - elapsedSessionTime
            let reason = "Accumulating: \(String(format: "%.0f", remaining))s of "
                + "\(Int(Self.listeningDuration))s needed."
            return holdDecision(state: state, confidence: confidence, reason: reason)
        }

        guard !catalog.isEmpty else {
            return holdDecision(
                state: state,
                confidence: confidence,
                reason: "Reactive [\(state.rawValue)]: empty catalog — holding."
            )
        }

        // Build live profile: mood always live; stem balance from live analyzer once converged
        // (QR.2/D-080 — avoids adversarial TrackProfile.empty penalising stem-affinity presets).
        var liveProfile = TrackProfile.empty
        liveProfile.mood = liveMood
        if let stems = liveStemFeatures {
            liveProfile.stemEnergyBalance = stems
        }

        let altCtx = PresetScoringContext(
            deviceTier: deviceTier,
            recentHistory: [],
            currentPreset: currentPreset,
            elapsedSessionTime: elapsedSessionTime,
            includeUncertifiedPresets: includeUncertifiedPresets
        )
        let ranked = scorer.rank(presets: catalog, track: liveProfile, context: altCtx)

        // V.7.6.D: defensive filter — Scorer returns total 0 for diagnostics, but a
        // catalog-only-of-diagnostics (or scoring tie) could otherwise elevate one.
        // Per D-074, diagnostics are categorically auto-selection-ineligible.
        guard let (topPreset, topScore) = ranked.first(where: { !$0.0.isDiagnostic }) else {
            return holdDecision(
                state: state,
                confidence: confidence,
                reason: "Reactive [\(state.rawValue)]: no eligible preset — holding."
            )
        }

        guard let current = currentPreset else {
            let at = scheduleTime(elapsedSessionTime: elapsedSessionTime, liveBoundary: liveBoundary)
            let msg = "Reactive [\(state.rawValue)]: no current preset — "
                + "selecting '\(topPreset.name)' (\(String(format: "%.2f", topScore)))."
            return suggestDecision(
                preset: topPreset,
                scheduledAt: at,
                state: state,
                confidence: confidence,
                reason: msg
            )
        }

        return compareAndDecide(
            current: current,
            topPreset: topPreset,
            topScore: topScore,
            liveProfile: liveProfile,
            liveBoundary: liveBoundary,
            elapsedSessionTime: elapsedSessionTime,
            state: state,
            confidence: confidence,
            deviceTier: deviceTier,
            includeUncertifiedPresets: includeUncertifiedPresets
        )
    }
    // swiftlint:enable function_parameter_count

    // MARK: - Helpers

    // swiftlint:disable function_parameter_count
    /// Compare current preset score against the best alternative and return a decision.
    private func compareAndDecide(
        current: PresetDescriptor,
        topPreset: PresetDescriptor,
        topScore: Float,
        liveProfile: TrackProfile,
        liveBoundary: StructuralPrediction,
        elapsedSessionTime: TimeInterval,
        state: ReactiveAccumulationState,
        confidence: Float,
        deviceTier: DeviceTier,
        includeUncertifiedPresets: Bool = false
    ) -> ReactiveDecision {
        let currentCtx = PresetScoringContext(
            deviceTier: deviceTier,
            recentHistory: [],
            currentPreset: nil,
            elapsedSessionTime: elapsedSessionTime,
            includeUncertifiedPresets: includeUncertifiedPresets
        )
        let currentScore = scorer.score(preset: current, track: liveProfile, context: currentCtx)
        let scoreGap = topScore - currentScore
        let scoreGapMet = scoreGap > Self.minScoreGapForSwitch
        // Boundary-only switches still require a small positive score advantage (QR.2/D-080):
        // confidence ≥ 0.5 alone previously forced switches even when the current preset
        // scored equally or better than any alternative.
        let boundaryFired = liveBoundary.confidence >= Self.boundaryConfidenceThreshold
                         && scoreGap > Self.minBoundaryScoreGap

        guard scoreGapMet || boundaryFired else {
            let reason = "Reactive [\(state.rawValue)]: holding '\(current.name)' — "
                + "gap \(String(format: "%.2f", scoreGap)) < "
                + "\(String(format: "%.2f", Self.minScoreGapForSwitch)), "
                + "boundary confidence \(String(format: "%.2f", liveBoundary.confidence)) "
                + "(min gap \(String(format: "%.2f", Self.minBoundaryScoreGap)) for boundary switch)."
            return holdDecision(state: state, confidence: confidence, reason: reason)
        }

        let at = scheduleTime(elapsedSessionTime: elapsedSessionTime, liveBoundary: liveBoundary)
        let trigger = boundaryFired && !scoreGapMet ? "boundary" : "score gap"
        let msg = "Reactive [\(state.rawValue)]: '\(topPreset.name)' "
            + "(\(String(format: "%.2f", topScore))) replaces "
            + "'\(current.name)' (\(String(format: "%.2f", currentScore))); "
            + "Δ\(String(format: "%.2f", topScore - currentScore)) "
            + "at \(String(format: "%.0f", elapsedSessionTime))s (\(trigger))."
        return suggestDecision(preset: topPreset, scheduledAt: at, state: state, confidence: confidence, reason: msg)
    }
    // swiftlint:enable function_parameter_count

    /// Ramp: 0→0.3 over [0, 15s], 0.3→1.0 over [15s, 30s], 1.0 after.
    static func computeConfidence(elapsed: TimeInterval) -> Float {
        if elapsed >= fullConfidenceDuration {
            return 1.0
        } else if elapsed >= listeningDuration {
            return 0.3 + Float((elapsed - listeningDuration) / listeningDuration) * 0.7
        } else {
            return Float(elapsed / listeningDuration) * 0.3
        }
    }

    /// Session-relative time to schedule the transition.
    ///
    /// Uses the live boundary prediction if confidence is sufficient;
    /// otherwise schedules 2 s from now.
    private func scheduleTime(
        elapsedSessionTime: TimeInterval,
        liveBoundary: StructuralPrediction
    ) -> TimeInterval {
        if liveBoundary.confidence >= Self.boundaryConfidenceThreshold {
            return TimeInterval(liveBoundary.predictedNextBoundary) + elapsedSessionTime
        }
        return elapsedSessionTime + 2.0
    }

    /// Build a "hold current preset" decision.
    private func holdDecision(
        state: ReactiveAccumulationState,
        confidence: Float,
        reason: String
    ) -> ReactiveDecision {
        ReactiveDecision(
            suggestedPreset: nil,
            scheduleTransitionAt: nil,
            accumulationState: state,
            confidence: confidence,
            reason: reason
        )
    }

    /// Build a "switch to this preset" decision, scheduling via `scheduleTime`.
    private func suggestDecision(
        preset: PresetDescriptor,
        scheduledAt: TimeInterval,
        state: ReactiveAccumulationState,
        confidence: Float,
        reason: String
    ) -> ReactiveDecision {
        ReactiveDecision(
            suggestedPreset: preset,
            scheduleTransitionAt: scheduledAt,
            accumulationState: state,
            confidence: confidence,
            reason: reason
        )
    }
}
