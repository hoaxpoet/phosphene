// LiveAdapter+Patching — Controlled mutation path for PlannedSession (Increment 4.5).
//
// PlannedSession has an internal memberwise init — "always build via DefaultSessionPlanner.plan()".
// This extension is in the same Orchestrator module, so it can use the internal inits.
// It is the only supported way to apply a LiveAdaptation to a live plan outside
// of the initial planning pass. See D-035 for rationale.

import Foundation
import Presets
import Session

// MARK: - PlannedSession + Applying

public extension PlannedSession {

    /// Returns a new `PlannedSession` with the `LiveAdaptation` applied at `trackIndex`.
    ///
    /// - Boundary reschedule: replaces `incomingTransition` on `tracks[trackIndex + 1]`.
    /// - Preset override: replaces `preset` and `presetScore` on `tracks[trackIndex]`.
    /// - When `adaptation` carries no changes, returns `self` unchanged.
    ///
    /// This is the only controlled mutation path for a `PlannedSession` outside of
    /// `DefaultSessionPlanner.plan()`. The internal memberwise init is intentionally hidden;
    /// use this extension to apply `LiveAdapter` results.
    func applying(_ adaptation: LiveAdaptation, at trackIndex: Int) -> PlannedSession {
        guard trackIndex < tracks.count else { return self }
        var updatedTracks = tracks

        if let rescheduled = adaptation.updatedTransition {
            let nextIndex = trackIndex + 1
            guard nextIndex < updatedTracks.count else { return self }
            let next = updatedTracks[nextIndex]
            updatedTracks[nextIndex] = PlannedTrack(
                track: next.track,
                trackProfile: next.trackProfile,
                preset: next.preset,
                presetScore: next.presetScore,
                scoreBreakdown: next.scoreBreakdown,
                plannedStartTime: next.plannedStartTime,
                plannedEndTime: next.plannedEndTime,
                incomingTransition: rescheduled
            )
        }

        if let override = adaptation.presetOverride {
            let current = updatedTracks[trackIndex]
            updatedTracks[trackIndex] = PlannedTrack(
                track: current.track,
                trackProfile: current.trackProfile,
                preset: override.preset,
                presetScore: override.score,
                scoreBreakdown: current.scoreBreakdown,
                plannedStartTime: current.plannedStartTime,
                plannedEndTime: current.plannedEndTime,
                incomingTransition: current.incomingTransition
            )
        }

        return PlannedSession(
            deviceTier: deviceTier,
            tracks: updatedTracks,
            totalDuration: totalDuration,
            warnings: warnings
        )
    }

    /// Returns a new `PlannedSession` with every track in `overrides` having its preset replaced.
    ///
    /// Used by `regeneratePlan(lockedTracks:lockedPresets:)` to preserve manually locked picks
    /// after a seed-randomised re-plan. Tracks not in `overrides` are unchanged.
    func applying(overrides: [TrackIdentity: PresetDescriptor]) -> PlannedSession {
        guard !overrides.isEmpty else { return self }
        let updatedTracks = tracks.map { planned -> PlannedTrack in
            guard let override = overrides[planned.track] else { return planned }
            return PlannedTrack(
                track: planned.track,
                trackProfile: planned.trackProfile,
                preset: override,
                presetScore: planned.presetScore,
                scoreBreakdown: planned.scoreBreakdown,
                plannedStartTime: planned.plannedStartTime,
                plannedEndTime: planned.plannedEndTime,
                incomingTransition: planned.incomingTransition
            )
        }
        return PlannedSession(
            deviceTier: deviceTier,
            tracks: updatedTracks,
            totalDuration: totalDuration,
            warnings: warnings
        )
    }
}
