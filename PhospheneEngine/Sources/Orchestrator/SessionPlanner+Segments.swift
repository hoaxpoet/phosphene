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
    }

    /// Produces the section list for a track from its `estimatedSectionCount`.
    static func makeSections(
        trackStart: TimeInterval,
        trackEnd: TimeInterval,
        profile: TrackProfile
    ) -> [TrackSection] {
        let count = max(1, profile.estimatedSectionCount)
        let span = trackEnd - trackStart
        guard span > 0 else {
            return [TrackSection(start: trackStart, end: trackEnd, section: nil)]
        }
        let perSection = span / Double(count)
        var sections: [TrackSection] = []
        sections.reserveCapacity(count)
        for idx in 0..<count {
            let secStart = trackStart + Double(idx) * perSection
            let secEnd = (idx == count - 1) ? trackEnd : trackStart + Double(idx + 1) * perSection
            sections.append(TrackSection(start: secStart, end: secEnd, section: nil))
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

        for (sectionIdx, sectionEntry) in sections.enumerated() {
            let isLastSection = sectionIdx == sections.count - 1
            var sectionClock = sectionEntry.start

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
                firstSegmentEmitted = true
                if result.segment.plannedEndTime <= sectionClock - 0.001 { break }
                if !result.advanced { break }
            }
        }

        // Defensive: every track must have at least one segment.
        if segments.isEmpty, let preset = catalog.first {
            let breakdown = scorer.breakdown(
                preset: preset,
                track: profile,
                context: PresetScoringContext(
                    deviceTier: deviceTier,
                    elapsedSessionTime: trackStart,
                    includeUncertifiedPresets: includeUncertifiedPresets
                )
            )
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

        let remainingInSection = sectionEntry.end - sectionClock
        let maxByPreset = chosen.maxDuration(forSection: sectionEntry.section)
        let segLen = max(1.0, min(remainingInSection, maxByPreset))
        let actualLen = min(segLen, remainingInSection)
        let segStart = sectionClock
        let segEnd = sectionClock + actualLen

        let isLastSegmentOfTrack = isLastSection && segEnd >= trackEnd - 0.001
        let terminationReason: SegmentTerminationReason
        if isLastSegmentOfTrack {
            terminationReason = .trackEnded
        } else if maxByPreset < remainingInSection {
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
