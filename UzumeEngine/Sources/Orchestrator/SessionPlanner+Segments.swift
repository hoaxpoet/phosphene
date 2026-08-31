// SessionPlanner+Segments — Multi-segment walk for V.7.6.2.
//
// Extracted from SessionPlanner.swift to keep the core planner under the
// SwiftLint file-length / type-body-length / function-body-length limits.

import Foundation
import Presets
import Session
import Shared

// MARK: - DefaultSessionPlanner segment helpers

extension DefaultSessionPlanner {

    /// Section-list shape for a single track.
    ///
    /// Sections divide the track into equal-length spans with a default `nil` section type
    /// (which maps to `defaultSectionDynamicRange = 0.5` inside `maxDuration(forSection:)`).
    /// Once `TrackProfile` carries explicit per-section types (V.7.6.C+), the planner can
    /// pass them through.
    struct TrackSection {
        let start: TimeInterval
        let end: TimeInterval
        let section: SongSection?
        /// LFPLAN.7: true when this section came from real detected boundaries (LFPLAN.5),
        /// so `planSegments` runs one preset for the whole section instead of capping at the
        /// preset's `maxDuration` (Matt: "one visual per section"). False for equal slices.
        let isRealSection: Bool
    }

    /// Produces the section list for a track: equal slices from `estimatedSectionCount`.
    static func makeSections(
        trackStart: TimeInterval,
        trackEnd: TimeInterval,
        profile: TrackProfile
    ) -> [TrackSection] {
        let span = trackEnd - trackStart
        guard span > 0 else {
            return [TrackSection(start: trackStart, end: trackEnd, section: nil, isRealSection: false)]
        }

        let count = max(1, profile.estimatedSectionCount)
        let perSection = span / Double(count)
        var sections: [TrackSection] = []
        sections.reserveCapacity(count)
        for idx in 0..<count {
            let secStart = trackStart + Double(idx) * perSection
            let secEnd = (idx == count - 1) ? trackEnd : trackStart + Double(idx + 1) * perSection
            sections.append(TrackSection(start: secStart, end: secEnd, section: nil, isRealSection: false))
        }
        return sections
    }

    // swiftlint:disable function_parameter_count
    /// Walk a single track's section list emitting one or more `PlannedPresetSegment`.
    ///
    /// Per V.7.6.2 §3.3:
    /// - For each section, score eligible presets and pick the best.
    /// - Constrain segment to `min(remainingInSection, preset.maxDuration(forSection:))`.
    /// - If the section is longer than maxDuration, insert a mid-section transition to a
    ///   different preset (subject to the family-repeat penalty inside the scorer).
    ///
    /// Returns `(segments, lastPresetUsed)` so the outer loop can update history.
    func planSegments(
        trackStart: TimeInterval,
        trackEnd: TimeInterval,
        identity: TrackIdentity,
        profile: TrackProfile,
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        includeUncertifiedPresets: Bool,
        seed: UInt64,
        trackIndex: Int,
        history: inout [PresetHistoryEntry],
        currentPreset: inout PresetDescriptor?,
        warnings: inout [PlanningWarning]
    ) -> ([PlannedPresetSegment], PresetDescriptor?) {

        var segments: [PlannedPresetSegment] = []
        let sections = Self.makeSections(trackStart: trackStart, trackEnd: trackEnd, profile: profile)
        var firstSegmentEmitted = false
        // BUG-037: a `wait_for_completion_event` segment can span past its own section,
        // so a later section it already covers must not re-emit a segment.
        var coveredUntil = trackStart

        for (sectionIdx, sectionEntry) in sections.enumerated() {
            let isLastSection = sectionIdx == sections.count - 1
            var sectionClock = max(sectionEntry.start, coveredUntil)

            while sectionClock < sectionEntry.end {
                let result = planOneSegment(
                    sectionEntry: sectionEntry,
                    isLastSection: isLastSection,
                    sectionClock: sectionClock,
                    trackEnd: trackEnd,
                    identity: identity,
                    profile: profile,
                    catalog: catalog,
                    deviceTier: deviceTier,
                    includeUncertifiedPresets: includeUncertifiedPresets,
                    seed: seed,
                    trackIndex: trackIndex,
                    firstSegmentEmitted: firstSegmentEmitted,
                    history: &history,
                    currentPreset: &currentPreset,
                    warnings: &warnings
                )
                segments.append(result.segment)
                sectionClock = result.segment.plannedEndTime
                coveredUntil = max(coveredUntil, result.segment.plannedEndTime)
                firstSegmentEmitted = true
                if result.segment.plannedEndTime <= sectionClock - 0.001 { break }
                if !result.advanced { break }
            }
        }

        // Defensive: every track must have at least one segment (a zero-duration or
        // section-degenerate track emits none above). Never fall back to a raw
        // `catalog.first` — array/alphabetical order can put a diagnostic (D-074) or a
        // beat-locked preset (D-154) there, bypassing every exclusion gate. Pick the
        // best *eligible* preset (score > 0); only a fully degenerate catalog renders
        // something categorical, matching `cheapestFallback` (CLEAN.3.2).
        if segments.isEmpty {
            let context = PresetScoringContext(
                deviceTier: deviceTier,
                elapsedSessionTime: trackStart,
                includeUncertifiedPresets: includeUncertifiedPresets
            )
            let pool = categoricallyEligiblePool(catalog, onIrregularBeat: profile.beatIrregular == true)
            let ranked = scorer.rank(presets: pool, track: profile, context: context)
            if let preset = ranked.first(where: { $0.1 > 0 })?.0 ?? pool.first {
                let breakdown = scorer.breakdown(preset: preset, track: profile, context: context)
                segments.append(PlannedPresetSegment(
                    preset: preset,
                    presetScore: breakdown.total,
                    scoreBreakdown: breakdown,
                    plannedStartTime: trackStart,
                    plannedEndTime: trackEnd,
                    incomingTransition: nil,
                    terminationReason: .trackEnded
                ))
                currentPreset = preset
            }
        }

        return (segments, currentPreset)
    }
    // swiftlint:enable function_parameter_count

    // swiftlint:disable function_parameter_count function_body_length
    /// Build a single segment within a section.
    private func planOneSegment(
        sectionEntry: TrackSection,
        isLastSection: Bool,
        sectionClock: TimeInterval,
        trackEnd: TimeInterval,
        identity: TrackIdentity,
        profile: TrackProfile,
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        includeUncertifiedPresets: Bool,
        seed: UInt64,
        trackIndex: Int,
        firstSegmentEmitted: Bool,
        history: inout [PresetHistoryEntry],
        currentPreset: inout PresetDescriptor?,
        warnings: inout [PlanningWarning]
    ) -> (segment: PlannedPresetSegment, advanced: Bool) {
        let remainingInSection = sectionEntry.end - sectionClock
        let ctx = PresetScoringContext(
            deviceTier: deviceTier,
            recentHistory: history,
            currentPreset: currentPreset,
            elapsedSessionTime: sectionClock,
            currentSection: sectionEntry.section,
            includeUncertifiedPresets: includeUncertifiedPresets
        )
        let (chosen, breakdown) = selectPreset(
            catalog: catalog,
            profile: profile,
            context: ctx,
            trackRef: (trackIndex, identity.title),
            seed: seed,
            warnings: &warnings
        )

        let maxByPreset = chosen.maxDuration(forSection: sectionEntry.section)
        let segStart = sectionClock

        // BUG-037: a completion-gated preset (`wait_for_completion_event`) runs until its
        // `PresetSignaling.presetCompletionEvent` — the live path transitions on that
        // event. Reserve a generous span (its natural cycle) so a section boundary can't
        // cut a long build short and force a `.stable` pop mid-reveal (Arachne's ~92 s
        // weave outlived a ~38 s section). The live completion event ends the segment
        // earlier when the build actually finishes; this `plannedEndTime` is the ceiling.
        let segEnd: TimeInterval
        if chosen.waitForCompletionEvent {
            let span = TimeInterval(chosen.naturalCycleSeconds ?? Float(chosen.duration))
            segEnd = min(trackEnd, segStart + max(span, remainingInSection))
        } else if sectionEntry.isRealSection {
            // LFPLAN.7: one preset per real (detected) section — run to the section boundary,
            // not the preset's maxDuration cap (Matt: "one visual per section"). The cap still
            // governs equal-slice sections (old cached profiles / streaming previews).
            segEnd = segStart + remainingInSection
        } else {
            let segLen = max(1.0, min(remainingInSection, maxByPreset))
            segEnd = segStart + min(segLen, remainingInSection)
        }
        let actualLen = segEnd - segStart

        // A segment that reaches the track end is the last one regardless of which
        // section it started in (a completion-gated span can reach it from an earlier
        // section). `isLastSection` is retained for the call-site contract.
        _ = isLastSection
        let isLastSegmentOfTrack = segEnd >= trackEnd - 0.001
        let terminationReason: SegmentTerminationReason
        if isLastSegmentOfTrack {
            terminationReason = .trackEnded
        } else if chosen.waitForCompletionEvent
            || (!sectionEntry.isRealSection && maxByPreset < remainingInSection) {
            terminationReason = .maxDurationReached
        } else {
            terminationReason = .sectionBoundary
        }

        let incomingTransition: PlannedTransition?
        if let prior = currentPreset {
            incomingTransition = buildTransition(
                from: prior,
                to: chosen,
                profile: profile,
                at: segStart,
                lastEntry: history.last
            )
        } else if firstSegmentEmitted, let prior = currentPreset {
            // (Unreachable given the outer guard, but kept for clarity.)
            incomingTransition = buildTransition(
                from: prior,
                to: chosen,
                profile: profile,
                at: segStart,
                lastEntry: history.last
            )
        } else {
            incomingTransition = nil
        }

        let segment = PlannedPresetSegment(
            preset: chosen,
            presetScore: breakdown.total,
            scoreBreakdown: breakdown,
            plannedStartTime: segStart,
            plannedEndTime: segEnd,
            incomingTransition: incomingTransition,
            terminationReason: terminationReason
        )
        history.append(PresetHistoryEntry(
            presetID: chosen.id,
            family: chosen.family,
            startTime: segStart,
            endTime: segEnd
        ))
        if history.count > 50 { history.removeFirst(history.count - 50) }
        currentPreset = chosen
        return (segment, actualLen > 0)
    }
    // swiftlint:enable function_parameter_count function_body_length
}
