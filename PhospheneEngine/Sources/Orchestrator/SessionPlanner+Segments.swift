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

    /// LFPLAN.5: minimum planned section length. Matches the StructuralAnalyzer's 8 s
    /// section floor (`minPeakDistance` 16 × 0.5 s buckets). Detected boundaries closer
    /// than this — intro/outro fragments — are merged so the planner never emits a
    /// sub-perception flash.
    static let minSectionSeconds: TimeInterval = 8.0

    /// LFPLAN.5: detected boundaries must span at least this fraction of the track to be
    /// used (else equal slices). Separates full-track analysis (local files, final
    /// boundary lands deep in the track) from 30 s-preview analysis (streaming, boundaries
    /// bunch in the first ~30 s of a multi-minute track).
    static let minSectionCoverageFraction: Double = 0.4

    /// Produces the section list for a track.
    ///
    /// LFPLAN.5: when the profile carries detected section-boundary times that span the
    /// track (local-file full-track analysis), segments land on the real sections. Falls
    /// back to equal slices from `estimatedSectionCount` for nil/empty times (old cached
    /// profiles), or preview-scale times that don't span the track (streaming previews).
    static func makeSections(
        trackStart: TimeInterval,
        trackEnd: TimeInterval,
        profile: TrackProfile
    ) -> [TrackSection] {
        let span = trackEnd - trackStart
        guard span > 0 else {
            return [TrackSection(start: trackStart, end: trackEnd, section: nil, isRealSection: false)]
        }

        if let real = realSections(trackStart: trackStart, trackEnd: trackEnd, span: span, profile: profile) {
            return real
        }

        // Equal-slice fallback (unchanged behaviour).
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

    /// LFPLAN.5: build a section list from `profile.sectionStartTimes` (track-relative
    /// boundary offsets, not including 0). Returns `nil` — caller falls back to equal
    /// slices — when there are no usable boundaries or they don't span enough of the track.
    static func realSections(
        trackStart: TimeInterval,
        trackEnd: TimeInterval,
        span: TimeInterval,
        profile: TrackProfile
    ) -> [TrackSection]? {
        guard let rawTimes = profile.sectionStartTimes, !rawTimes.isEmpty else { return nil }

        // Interior boundaries only — the filter drops any within the section floor of the
        // track start (short intro) or end (short outro), so those fragments are absorbed
        // into the neighbouring section. Sorted ascending.
        let interior = rawTimes
            .filter { $0 > minSectionSeconds && $0 < span - minSectionSeconds }
            .sorted()
        guard let last = interior.last, last >= span * minSectionCoverageFraction else { return nil }

        // Section starts = track start + each boundary kept ≥ minSection from the previous
        // (drops close-together boundaries). The interior filter already guarantees the
        // final section runs ≥ minSection to trackEnd.
        var starts: [TimeInterval] = [trackStart]
        for time in interior {
            let absolute = trackStart + time
            if absolute - (starts.last ?? trackStart) >= minSectionSeconds { starts.append(absolute) }
        }
        guard starts.count > 1 else { return nil }

        var sections: [TrackSection] = []
        sections.reserveCapacity(starts.count)
        for (idx, secStart) in starts.enumerated() {
            let secEnd = (idx == starts.count - 1) ? trackEnd : starts[idx + 1]
            sections.append(TrackSection(start: secStart, end: secEnd, section: nil, isRealSection: true))
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
