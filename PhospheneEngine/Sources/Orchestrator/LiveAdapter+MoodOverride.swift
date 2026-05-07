// LiveAdapter+MoodOverride — Preset-substitution logic extracted for file-length compliance.
// Companion to LiveAdapter.swift. See D-035, QR.2/D-080 for design context.

import Foundation
import Presets
import Session
import Shared
import os.log

private let moodLogger = Logging.orchestrator

extension DefaultLiveAdapter {

    // swiftlint:disable:next function_parameter_count
    func applyOverrideIfBetter(
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

        guard let (topPreset, topScore) = ranked.first, !topPreset.isDiagnostic, // V.7.6.D D-074
              topScore - currentScore > Self.overrideScoreGap else {
            moodLogger.info("""
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

        moodLogger.info("LiveAdapter: preset override at track \(trackIndex): \(reason)")

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
