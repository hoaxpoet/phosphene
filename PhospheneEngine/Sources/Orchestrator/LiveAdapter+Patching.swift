// LiveAdapter+Patching — Controlled mutation path for PlannedSession (Increment 4.5).
//
// PlannedSession has an internal memberwise init — "always build via DefaultSessionPlanner.plan()".
// This extension is in the same Orchestrator module, so it can use the internal inits.
// It is the only supported way to apply a LiveAdaptation to a live plan outside
// of the initial planning pass. See D-035 for rationale.
//
// V.7.6.2: segment-aware. `applying(_:at:)` patches the *active segment* (not the
// track-level legacy fields) when applying a preset override. `boundary reschedule`
// updates the next segment's incomingTransition.

import Foundation
import Presets
import Session

// MARK: - PlannedSession + Applying

public extension PlannedSession {

    /// Returns a new `PlannedSession` with the `LiveAdaptation` applied at `trackIndex`.
    ///
    /// - Boundary reschedule: replaces `incomingTransition` on the *first segment* of
    ///   `tracks[trackIndex + 1]`.
    /// - Preset override: replaces `preset` and `presetScore` on the active segment of
    ///   `tracks[trackIndex]`. The active segment is the first whose
    ///   `[plannedStartTime, plannedEndTime)` window covers the track's mid-point — for
    ///   single-segment tracks (the default for non-Arachne presets) this is segments[0].
    ///
    /// V.7.6.2: previously this patched the track-level preset; backward-compat is
    /// preserved because single-segment tracks have exactly one segment.
    func applying(_ adaptation: LiveAdaptation, at trackIndex: Int) -> PlannedSession {
        guard trackIndex < tracks.count else { return self }
        var updatedTracks = tracks

        if let rescheduled = adaptation.updatedTransition {
            let nextIndex = trackIndex + 1
            guard nextIndex < updatedTracks.count else { return self }
            let next = updatedTracks[nextIndex]
            // Replace incomingTransition on segments[0] (the segment that opens the next track).
            var nextSegments = next.segments
            let firstSeg = nextSegments[0]
            nextSegments[0] = PlannedPresetSegment(
                preset: firstSeg.preset,
                presetScore: firstSeg.presetScore,
                scoreBreakdown: firstSeg.scoreBreakdown,
                plannedStartTime: firstSeg.plannedStartTime,
                plannedEndTime: firstSeg.plannedEndTime,
                incomingTransition: rescheduled,
                terminationReason: firstSeg.terminationReason
            )
            updatedTracks[nextIndex] = PlannedTrack(
                track: next.track,
                trackProfile: next.trackProfile,
                segments: nextSegments,
                plannedStartTime: next.plannedStartTime,
                plannedEndTime: next.plannedEndTime
            )
        }

        if let override = adaptation.presetOverride {
            let current = updatedTracks[trackIndex]
            // Patch the first segment — this preserves D-035 single-segment behaviour for
            // every existing preset and is the deterministic choice for multi-segment tracks
            // where LiveAdapter does not currently track the active segment index.
            var segments = current.segments
            let first = segments[0]
            segments[0] = PlannedPresetSegment(
                preset: override.preset,
                presetScore: override.score,
                scoreBreakdown: first.scoreBreakdown,
                plannedStartTime: first.plannedStartTime,
                plannedEndTime: first.plannedEndTime,
                incomingTransition: first.incomingTransition,
                terminationReason: first.terminationReason
            )
            updatedTracks[trackIndex] = PlannedTrack(
                track: current.track,
                trackProfile: current.trackProfile,
                segments: segments,
                plannedStartTime: current.plannedStartTime,
                plannedEndTime: current.plannedEndTime
            )
        }

        return PlannedSession(
            deviceTier: deviceTier,
            tracks: updatedTracks,
            totalDuration: totalDuration,
            warnings: warnings
        )
    }

    /// Returns a new `PlannedSession` with the current track's end time extended by `seconds`.
    ///
    /// All subsequent track start/end times shift forward by the same amount so session
    /// timing remains internally consistent. Used by `moreLikeThis()` (U.6b).
    ///
    /// V.7.6.2: extends the *last segment* of the active track (so the user-visible "current
    /// preset" is the one that gets longer). Earlier segments are unchanged.
    ///
    /// - Parameters:
    ///   - seconds: Amount to extend the current track's planned duration.
    ///   - sessionTime: Current session time used to identify the active track.
    /// - Returns: Patched session, or `self` if no track is active at `sessionTime`.
    func extendingCurrentPreset(by seconds: TimeInterval, at sessionTime: TimeInterval) -> PlannedSession {
        guard let activeTrack = track(at: sessionTime),
              let trackIndex = tracks.firstIndex(where: { $0.track == activeTrack.track })
        else { return self }

        var updatedTracks = tracks
        let current = updatedTracks[trackIndex]

        // Extend the last segment by `seconds`.
        var segments = current.segments
        let lastIdx = segments.count - 1
        let lastSeg = segments[lastIdx]
        segments[lastIdx] = PlannedPresetSegment(
            preset: lastSeg.preset,
            presetScore: lastSeg.presetScore,
            scoreBreakdown: lastSeg.scoreBreakdown,
            plannedStartTime: lastSeg.plannedStartTime,
            plannedEndTime: lastSeg.plannedEndTime + seconds,
            incomingTransition: lastSeg.incomingTransition,
            terminationReason: lastSeg.terminationReason
        )
        updatedTracks[trackIndex] = PlannedTrack(
            track: current.track,
            trackProfile: current.trackProfile,
            segments: segments,
            plannedStartTime: current.plannedStartTime,
            plannedEndTime: current.plannedEndTime + seconds
        )

        // Shift all subsequent tracks forward by `seconds`.
        for idx in (trackIndex + 1)..<updatedTracks.count {
            let entry = updatedTracks[idx]
            let shift = seconds
            let newStart = entry.plannedStartTime + shift
            let newEnd = entry.plannedEndTime + shift
            let shiftedSegments = entry.segments.map { seg -> PlannedPresetSegment in
                let newIncoming = seg.incomingTransition.map { transition in
                    PlannedTransition(
                        fromPreset: transition.fromPreset,
                        toPreset: transition.toPreset,
                        style: transition.style,
                        duration: transition.duration,
                        scheduledAt: transition.scheduledAt + shift,
                        reason: transition.reason
                    )
                }
                return PlannedPresetSegment(
                    preset: seg.preset,
                    presetScore: seg.presetScore,
                    scoreBreakdown: seg.scoreBreakdown,
                    plannedStartTime: seg.plannedStartTime + shift,
                    plannedEndTime: seg.plannedEndTime + shift,
                    incomingTransition: newIncoming,
                    terminationReason: seg.terminationReason
                )
            }
            updatedTracks[idx] = PlannedTrack(
                track: entry.track,
                trackProfile: entry.trackProfile,
                segments: shiftedSegments,
                plannedStartTime: newStart,
                plannedEndTime: newEnd
            )
        }

        return PlannedSession(
            deviceTier: deviceTier,
            tracks: updatedTracks,
            totalDuration: totalDuration + seconds,
            warnings: warnings
        )
    }

    /// Returns a new `PlannedSession` with every track in `overrides` having its preset replaced.
    ///
    /// Used by `regeneratePlan(lockedTracks:lockedPresets:)` to preserve manually locked picks
    /// after a seed-randomised re-plan. Tracks not in `overrides` are unchanged.
    ///
    /// V.7.6.2: replaces the preset on segments[0] (the user-locked pick).
    func applying(overrides: [TrackIdentity: PresetDescriptor]) -> PlannedSession {
        guard !overrides.isEmpty else { return self }
        let updatedTracks = tracks.map { planned -> PlannedTrack in
            guard let override = overrides[planned.track] else { return planned }
            var segments = planned.segments
            let first = segments[0]
            segments[0] = PlannedPresetSegment(
                preset: override,
                presetScore: first.presetScore,
                scoreBreakdown: first.scoreBreakdown,
                plannedStartTime: first.plannedStartTime,
                plannedEndTime: first.plannedEndTime,
                incomingTransition: first.incomingTransition,
                terminationReason: first.terminationReason
            )
            return PlannedTrack(
                track: planned.track,
                trackProfile: planned.trackProfile,
                segments: segments,
                plannedStartTime: planned.plannedStartTime,
                plannedEndTime: planned.plannedEndTime
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
