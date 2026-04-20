// LiveAdapter — Real-time plan adaptation during playback (Increment 4.5, D-035).
//
// Receives the pre-planned PlannedSession, a live MIR snapshot, and decides
// whether to reschedule a transition or override the current track's preset.
//
// Conservative by design: at most one adaptation per call; boundary reschedule
// wins when both triggers fire simultaneously.
//
// Pure function: no Date.now(), no randomness, no external state reads inside
// DefaultLiveAdapter. All state is passed in as arguments.

import Foundation
import Presets
import Session
import Shared
import os.log

private let logger = Logging.orchestrator

// MARK: - AdaptationEvent

/// A logged event produced when `LiveAdapting.adapt` makes (or declines) an adaptation.
public struct AdaptationEvent: Sendable, Hashable, Codable {

    // MARK: Kind

    /// The outcome category of one `adapt` call.
    public enum Kind: String, Sendable, Hashable, Codable {
        /// A planned transition was rescheduled to align with a live structural boundary.
        case boundaryRescheduled
        /// Live mood diverged significantly from the pre-analyzed mood.
        case moodDivergenceDetected
        /// A better-suited preset was substituted mid-track.
        case presetOverrideTriggered
        /// No adaptation was warranted; plan unchanged.
        case noAdaptation
    }

    // MARK: Fields

    /// What outcome occurred.
    public let kind: Kind
    /// 0-based playlist position of the affected track.
    public let trackIndex: Int
    /// Human-readable explanation for logging and testing.
    public let message: String

    public init(kind: Kind, trackIndex: Int, message: String) {
        self.kind = kind
        self.trackIndex = trackIndex
        self.message = message
    }
}

// MARK: - LiveAdaptation

/// The result of a single `LiveAdapting.adapt` call.
///
/// At most one of `updatedTransition` and `presetOverride` will be non-nil
/// per call — boundary reschedule takes priority when both conditions are met.
public struct LiveAdaptation: Sendable {

    /// Revised outgoing transition for the current track (`scheduledAt` updated).
    /// Non-nil only when `events` contains `.boundaryRescheduled`.
    public let updatedTransition: PlannedTransition?

    /// Replacement preset for the current track (mid-track override).
    /// Non-nil only when `events` contains `.presetOverrideTriggered`.
    public let presetOverride: PresetOverride?

    /// Diagnostic events for logging and testing.
    public let events: [AdaptationEvent]

    /// Replacement preset bundle produced by a mood-divergence override.
    public struct PresetOverride: Sendable {
        public let preset: PresetDescriptor
        public let score: Float
        public let reason: String

        public init(preset: PresetDescriptor, score: Float, reason: String) {
            self.preset = preset
            self.score = score
            self.reason = reason
        }
    }

    public init(
        updatedTransition: PlannedTransition? = nil,
        presetOverride: PresetOverride? = nil,
        events: [AdaptationEvent]
    ) {
        self.updatedTransition = updatedTransition
        self.presetOverride = presetOverride
        self.events = events
    }
}

// MARK: - LiveAdapting

/// Protocol for live adaptation implementations.
///
/// Conforming types must be `Sendable` and must not access mutable external
/// state — all state must arrive via the function arguments.
public protocol LiveAdapting: Sendable {

    // swiftlint:disable function_parameter_count
    /// Evaluate live MIR data against the current plan and return any adaptation.
    ///
    /// - Parameters:
    ///   - plan: The pre-planned session (from `DefaultSessionPlanner`).
    ///   - currentTrackIndex: 0-based index into `plan.tracks`.
    ///   - elapsedTrackTime: Seconds since the current track started playing.
    ///   - liveBoundary: Latest structural prediction from the live MIR pipeline.
    ///   - liveMood: Current valence/arousal from the live mood classifier.
    ///   - catalog: Full preset catalog for alternative scoring.
    /// - Returns: A `LiveAdaptation` value — `noAdaptation` when nothing fires.
    func adapt(
        plan: PlannedSession,
        currentTrackIndex: Int,
        elapsedTrackTime: TimeInterval,
        liveBoundary: StructuralPrediction,
        liveMood: EmotionalState,
        catalog: [PresetDescriptor]
    ) -> LiveAdaptation
    // swiftlint:enable function_parameter_count
}

// MARK: - DefaultLiveAdapter

/// Concrete `LiveAdapting` implementation.
///
/// **Priority:** boundary reschedule (structural) → mood-driven preset override.
///
/// **Boundary rescheduling** fires when `liveBoundary.confidence ≥ 0.5` and the
/// live prediction differs from the planned transition time by more than 5 s.
///
/// **Mood override** fires only when all three conditions are true:
/// 1. Live mood diverges from the pre-analyzed mood
///    (`|Δvalence| > 0.4` or `|Δarousal| > 0.4`).
/// 2. Less than 40 % of the track has elapsed.
/// 3. A catalog preset scores more than 0.15 higher than the current preset
///    when rescored with live mood.
///
/// If mood diverges but the override conditions are not all met, a
/// `.moodDivergenceDetected` event is returned for logging — no plan change.
///
/// See D-035 for design rationale.
public struct DefaultLiveAdapter: LiveAdapting {
    // MARK: - Tuning constants

    /// Minimum `StructuralPrediction.confidence` required to consider rescheduling.
    public static let boundaryConfidenceThreshold: Float = 0.5

    /// Minimum deviation (seconds) between live and planned transition times before
    /// a reschedule is triggered.
    public static let boundaryRescheduleThreshold: TimeInterval = 5.0

    /// |Δvalence| or |Δarousal| that constitutes "diverging" mood.
    public static let moodDivergenceThreshold: Float = 0.4

    /// Maximum elapsed fraction of track before mood override is suppressed.
    public static let overrideElapsedFractionCap: TimeInterval = 0.4

    /// Minimum score advantage a replacement preset must have to justify an override.
    public static let overrideScoreGap: Float = 0.15

    // MARK: - Dependencies

    private let scorer: any PresetScoring
    private let transitionPolicy: any TransitionDeciding
    // MARK: - Init

    public init(
        scorer: any PresetScoring = DefaultPresetScorer(),
        transitionPolicy: any TransitionDeciding = DefaultTransitionPolicy()
    ) {
        self.scorer = scorer
        self.transitionPolicy = transitionPolicy
    }

    // MARK: - LiveAdapting

    // swiftlint:disable:next function_parameter_count
    public func adapt(
        plan: PlannedSession,
        currentTrackIndex: Int,
        elapsedTrackTime: TimeInterval,
        liveBoundary: StructuralPrediction,
        liveMood: EmotionalState,
        catalog: [PresetDescriptor]
    ) -> LiveAdaptation {
        guard currentTrackIndex < plan.tracks.count else {
            return LiveAdaptation(events: [AdaptationEvent(
                kind: .noAdaptation,
                trackIndex: currentTrackIndex,
                message: "Track index \(currentTrackIndex) out of range (plan has \(plan.tracks.count) tracks)."
            )])
        }

        // Boundary reschedule takes priority — check it first.
        if let reschedule = evaluateBoundaryReschedule(
            plan: plan,
            currentTrackIndex: currentTrackIndex,
            liveBoundary: liveBoundary
        ) {
            return reschedule
        }

        // Mood override — only fires when no boundary reschedule triggered.
        return evaluateMoodOverride(
            plan: plan,
            currentTrackIndex: currentTrackIndex,
            elapsedTrackTime: elapsedTrackTime,
            liveMood: liveMood,
            catalog: catalog
        )
    }

    // MARK: - Boundary Rescheduling

    private func evaluateBoundaryReschedule(
        plan: PlannedSession,
        currentTrackIndex: Int,
        liveBoundary: StructuralPrediction
    ) -> LiveAdaptation? {
        guard liveBoundary.confidence >= Self.boundaryConfidenceThreshold else { return nil }

        // Outgoing transition is stored as the incomingTransition of the next track.
        let nextIndex = currentTrackIndex + 1
        guard nextIndex < plan.tracks.count,
              let plannedTransition = plan.tracks[nextIndex].incomingTransition else {
            return nil
        }

        // Convert capture-relative boundary time to session-relative.
        let trackStart = plan.tracks[currentTrackIndex].plannedStartTime
        let liveSessionBoundary = TimeInterval(liveBoundary.predictedNextBoundary) + trackStart

        let deviation = abs(liveSessionBoundary - plannedTransition.scheduledAt)
        guard deviation > Self.boundaryRescheduleThreshold else { return nil }

        let rescheduled = PlannedTransition(
            fromPreset: plannedTransition.fromPreset,
            toPreset: plannedTransition.toPreset,
            style: plannedTransition.style,
            duration: plannedTransition.duration,
            scheduledAt: liveSessionBoundary,
            reason: "Live boundary rescheduled: "
                + "\(String(format: "%.1f", plannedTransition.scheduledAt))s → "
                + "\(String(format: "%.1f", liveSessionBoundary))s "
                + "(Δ\(String(format: "%.1f", deviation))s, "
                + "confidence \(String(format: "%.2f", liveBoundary.confidence)))."
        )

        logger.info("""
            LiveAdapter: boundary rescheduled track \(currentTrackIndex): \
            \(String(format: "%.1f", plannedTransition.scheduledAt))s → \
            \(String(format: "%.1f", liveSessionBoundary))s
            """)

        return LiveAdaptation(
            updatedTransition: rescheduled,
            events: [AdaptationEvent(
                kind: .boundaryRescheduled,
                trackIndex: currentTrackIndex,
                message: rescheduled.reason
            )]
        )
    }

    // MARK: - Mood Override

    private func evaluateMoodOverride(
        plan: PlannedSession,
        currentTrackIndex: Int,
        elapsedTrackTime: TimeInterval,
        liveMood: EmotionalState,
        catalog: [PresetDescriptor]
    ) -> LiveAdaptation {
        let plannedTrack = plan.tracks[currentTrackIndex]
        let plannedMood = plannedTrack.trackProfile.mood

        let valenceDiff = abs(liveMood.valence - plannedMood.valence)
        let arousalDiff = abs(liveMood.arousal - plannedMood.arousal)
        let isDiverging = valenceDiff > Self.moodDivergenceThreshold
                       || arousalDiff > Self.moodDivergenceThreshold

        guard isDiverging else {
            return LiveAdaptation(events: [AdaptationEvent(
                kind: .noAdaptation,
                trackIndex: currentTrackIndex,
                message: "Mood stable "
                    + "(|Δv|=\(String(format: "%.2f", valenceDiff)), "
                    + "|Δa|=\(String(format: "%.2f", arousalDiff)))."
            )])
        }

        // Suppress override if more than 40 % of the track has elapsed.
        let trackDuration = plannedTrack.plannedEndTime - plannedTrack.plannedStartTime
        let elapsedFraction = trackDuration > 0 ? elapsedTrackTime / trackDuration : 1.0

        guard elapsedFraction < Self.overrideElapsedFractionCap else {
            return LiveAdaptation(events: [AdaptationEvent(
                kind: .moodDivergenceDetected,
                trackIndex: currentTrackIndex,
                message: "Mood diverging "
                    + "(|Δv|=\(String(format: "%.2f", valenceDiff)), "
                    + "|Δa|=\(String(format: "%.2f", arousalDiff))) "
                    + "but \(String(format: "%.0f", elapsedFraction * 100))% elapsed — "
                    + "too late to override."
            )])
        }

        var liveMoodProfile = plannedTrack.trackProfile
        liveMoodProfile.mood = liveMood
        let elapsedSession = plannedTrack.plannedStartTime + elapsedTrackTime

        return applyOverrideIfBetter(
            plannedTrack: plannedTrack,
            liveMoodProfile: liveMoodProfile,
            elapsedSession: elapsedSession,
            deviceTier: plan.deviceTier,
            catalog: catalog,
            trackIndex: currentTrackIndex,
            valenceDiff: valenceDiff,
            arousalDiff: arousalDiff,
            elapsedFraction: elapsedFraction
        )
    }

    // swiftlint:disable:next function_parameter_count
    private func applyOverrideIfBetter(
        plannedTrack: PlannedTrack,
        liveMoodProfile: TrackProfile,
        elapsedSession: TimeInterval,
        deviceTier: DeviceTier,
        catalog: [PresetDescriptor],
        trackIndex: Int,
        valenceDiff: Float,
        arousalDiff: Float,
        elapsedFraction: Double
    ) -> LiveAdaptation {
        let currentPreset = plannedTrack.preset
        let baseCtx = PresetScoringContext(
            deviceTier: deviceTier,
            recentHistory: [],
            currentPreset: nil,
            elapsedSessionTime: elapsedSession
        )
        let currentScore = scorer.score(preset: currentPreset, track: liveMoodProfile, context: baseCtx)

        let altCtx = PresetScoringContext(
            deviceTier: deviceTier,
            recentHistory: [],
            currentPreset: currentPreset,
            elapsedSessionTime: elapsedSession
        )
        let ranked = scorer.rank(presets: catalog, track: liveMoodProfile, context: altCtx)

        guard let (topPreset, topScore) = ranked.first,
              topScore - currentScore > Self.overrideScoreGap else {
            logger.info("""
                LiveAdapter: mood diverging at track \(trackIndex) \
                but no preset scores >\(Self.overrideScoreGap) higher
                """)
            return LiveAdaptation(events: [AdaptationEvent(
                kind: .moodDivergenceDetected,
                trackIndex: trackIndex,
                message: "Mood diverging "
                    + "(|Δv|=\(String(format: "%.2f", valenceDiff)), "
                    + "|Δa|=\(String(format: "%.2f", arousalDiff))) "
                    + "but no preset scores "
                    + ">\(String(format: "%.2f", Self.overrideScoreGap)) higher."
            )])
        }

        let reason = "Mood override: '\(topPreset.name)' "
            + "(\(String(format: "%.2f", topScore))) replaces "
            + "'\(currentPreset.name)' "
            + "(\(String(format: "%.2f", currentScore))); "
            + "|Δv|=\(String(format: "%.2f", valenceDiff)), "
            + "|Δa|=\(String(format: "%.2f", arousalDiff)) "
            + "at \(String(format: "%.0f", elapsedFraction * 100))% elapsed."

        logger.info("LiveAdapter: preset override at track \(trackIndex): \(reason)")

        return LiveAdaptation(
            presetOverride: LiveAdaptation.PresetOverride(
                preset: topPreset,
                score: topScore,
                reason: reason
            ),
            events: [AdaptationEvent(
                kind: .presetOverrideTriggered,
                trackIndex: trackIndex,
                message: reason
            )]
        )
    }
}
