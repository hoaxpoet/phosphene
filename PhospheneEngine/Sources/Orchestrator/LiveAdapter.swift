// LiveAdapter — Real-time plan adaptation during playback (Increment 4.5, D-035).
//
// Receives the pre-planned PlannedSession, a live MIR snapshot, and decides
// whether to reschedule a transition or override the current track's preset.
//
// Conservative by design: at most one adaptation per call; boundary reschedule
// wins when both triggers fire simultaneously.
//
// QR.2/D-080: DefaultLiveAdapter is now a final class (not struct) to carry
// per-track mood-override cooldown state (NSLock-guarded, analysis-queue safe).

import Foundation
import Presets
import Session
import Shared
import os.log

private let logger = Logging.orchestrator

// MARK: - AdaptationEvent

/// A logged event produced when `DefaultLiveAdapter.adapt` makes (or declines) an adaptation.
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

/// The result of a single `DefaultLiveAdapter.adapt` call.
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

// MARK: - DefaultLiveAdapter

/// The live adapter (PUB.4: its single-conformer ceremony protocol
/// `LiveAdapting` was deleted — wire this concrete type directly). `adapt`
/// must not access mutable external state — all state arrives via arguments.
///
/// **Priority:** boundary reschedule (structural) → mood-driven preset override.
///
/// **Boundary rescheduling** fires when `liveBoundary.confidence ≥ 0.5` and the
/// live prediction differs from the planned transition time by more than 5 s.
///
/// **Mood override** fires only when all four conditions are true:
/// 1. Live mood diverges from the pre-analyzed mood
///    (`|Δvalence| > 0.4` or `|Δarousal| > 0.4`).
/// 2. Less than 40 % of the track has elapsed.
/// 3. A catalog preset scores more than 0.15 higher than the current preset
///    when rescored with live mood.
/// 4. At least `moodOverrideCooldown` seconds have elapsed since the last override
///    on this track (prevents re-patching `livePlan` at ~94 Hz, QR.2/D-080).
///
/// If mood diverges but the override conditions are not all met, a
/// `.moodDivergenceDetected` event is returned for logging — no plan change.
///
/// See D-035 for design rationale.
public final class DefaultLiveAdapter: @unchecked Sendable {
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

    /// Minimum seconds between mood overrides for the same track (QR.2/D-080).
    /// Prevents re-patching `livePlan` at the analysis-queue frame rate (~94 Hz).
    public static let moodOverrideCooldown: TimeInterval = 30.0

    // MARK: - Dependencies

    let scorer: any PresetScoring
    private let transitionPolicy: any TransitionDeciding

    // MARK: - Per-track cooldown state (QR.2/D-080)

    private let cooldownLock = NSLock()
    /// Maps `PlannedTrack.track` → `elapsedTrackTime` when the last override was applied.
    nonisolated(unsafe) private var lastOverrideTimePerTrack: [TrackIdentity: TimeInterval] = [:]

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

        // Suppress override within cooldown window (QR.2/D-080).
        let trackID = plannedTrack.track
        if let blocked = cooldownAdaptation(
            for: trackID,
            at: elapsedTrackTime,
            trackIndex: currentTrackIndex,
            valenceDiff: valenceDiff,
            arousalDiff: arousalDiff
        ) { return blocked }

        var liveMoodProfile = plannedTrack.trackProfile
        liveMoodProfile.mood = liveMood
        let elapsedSession = plannedTrack.plannedStartTime + elapsedTrackTime

        let result = applyOverrideIfBetter(
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
        if result.events.contains(where: { $0.kind == .presetOverrideTriggered }) {
            recordOverride(for: trackID, at: elapsedTrackTime)
        }
        return result
    }

    // MARK: - Cooldown Helper

    /// Returns a suppression `LiveAdaptation` if the mood-override cooldown is active,
    /// otherwise returns `nil` (caller may proceed with override evaluation).
    fileprivate func cooldownAdaptation(
        for trackID: TrackIdentity,
        at elapsedTrackTime: TimeInterval,
        trackIndex: Int,
        valenceDiff: Float,
        arousalDiff: Float
    ) -> LiveAdaptation? {
        let last = cooldownLock.withLock { lastOverrideTimePerTrack[trackID] }
        guard let last else { return nil }
        // CLEAN.3.3: a negative delta means the per-track clock went backwards — the
        // track was replayed or a new session reset it — so the stored timestamp is
        // stale and the cooldown is NOT active (`recordOverride` refreshes it on the
        // next fire). Before this guard a replay read e.g. `2 - 20 = -18 < 30` and kept
        // the override suppressed for the whole 2nd play (a 30 s preview clip never
        // re-passes the stale mark, so mood override was permanently dead from play 2).
        let sinceOverride = elapsedTrackTime - last
        guard sinceOverride >= 0, sinceOverride < Self.moodOverrideCooldown else { return nil }
        return LiveAdaptation(events: [AdaptationEvent(
            kind: .moodDivergenceDetected,
            trackIndex: trackIndex,
            message: "Mood diverging "
                + "(|Δv|=\(String(format: "%.2f", valenceDiff)), "
                + "|Δa|=\(String(format: "%.2f", arousalDiff))) "
                + "but cooldown active "
                + "(\(String(format: "%.0f", elapsedTrackTime - last))s / "
                + "\(Int(Self.moodOverrideCooldown))s)."
        )])
    }

    fileprivate func recordOverride(for trackID: TrackIdentity, at elapsedTrackTime: TimeInterval) {
        cooldownLock.withLock { lastOverrideTimePerTrack[trackID] = elapsedTrackTime }
    }
}
