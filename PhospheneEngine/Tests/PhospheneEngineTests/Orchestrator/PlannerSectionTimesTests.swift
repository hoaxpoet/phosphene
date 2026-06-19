// PlannerSectionTimesTests — LFPLAN.5 real-section segmentation.
//
// makeSections must land segment boundaries on the detected section times when they
// span the track (local-file full-track analysis), and fall back to the prior
// equal-slice behaviour for nil/empty times (old cached profiles) or preview-scale
// times that don't span the track (streaming 30 s previews).

import Foundation
import Testing
@testable import Orchestrator
import Session
import Shared

@Suite("PlannerSectionTimes (LFPLAN.5)")
struct PlannerSectionTimesTests {

    @Test("section times spanning the track drive the segment boundaries")
    func realTimesDriveSections() {
        // 200 s track; interior boundaries 20/60/120/160 (last 160 = 0.8 of span).
        let profile = TrackProfile(estimatedSectionCount: 5, sectionStartTimes: [20, 60, 120, 160])
        let sections = DefaultSessionPlanner.makeSections(trackStart: 0, trackEnd: 200, profile: profile)
        #expect(sections.map { $0.start } == [0, 20, 60, 120, 160])
        #expect(sections.map { $0.end } == [20, 60, 120, 160, 200])
    }

    @Test("boundaries are track-relative; trackStart offsets them")
    func boundariesAreTrackRelative() {
        // Plan times are session-relative; boundaries are track-relative offsets.
        let profile = TrackProfile(estimatedSectionCount: 3, sectionStartTimes: [30, 90])
        let sections = DefaultSessionPlanner.makeSections(trackStart: 500, trackEnd: 650, profile: profile)
        #expect(sections.map { $0.start } == [500, 530, 590])
        #expect(sections.map { $0.end } == [530, 590, 650])
    }

    @Test("preview-scale boundaries fall back to equal slices (coverage gate)")
    func previewScaleFallsBack() {
        // 240 s track, boundaries only at 10/22 — last 22 < 0.4 × 240 = 96 → equal slices.
        let profile = TrackProfile(estimatedSectionCount: 3, sectionStartTimes: [10, 22])
        let sections = DefaultSessionPlanner.makeSections(trackStart: 0, trackEnd: 240, profile: profile)
        #expect(sections.count == 3)
        #expect(sections.map { $0.start } == [0, 80, 160])
    }

    @Test("nil section times → equal slices (back-compat with old cached profiles)")
    func nilFallsBackToEqualSlices() {
        let profile = TrackProfile(estimatedSectionCount: 4)   // sectionStartTimes nil
        let sections = DefaultSessionPlanner.makeSections(trackStart: 0, trackEnd: 200, profile: profile)
        #expect(sections.map { $0.start } == [0, 50, 100, 150])
        #expect(sections.map { $0.end } == [50, 100, 150, 200])
    }

    @Test("boundaries closer than the section floor are merged (no tiny segment)")
    func closeBoundariesMerged() {
        // 40 and 44 are 4 s apart (< 8 s floor) → 44 dropped.
        let profile = TrackProfile(estimatedSectionCount: 4, sectionStartTimes: [40, 44, 120])
        let sections = DefaultSessionPlanner.makeSections(trackStart: 0, trackEnd: 200, profile: profile)
        #expect(sections.map { $0.start } == [0, 40, 120])
        #expect(sections.allSatisfy { $0.end - $0.start >= 8.0 })
    }

    @Test("real SMTS detector output segments on its sections, not equal slices")
    func realSMTSSectionsAligned() {
        // The exact offline detector output for Smells Like Teen Spirit (301 s),
        // session 2026-06-19T21-44-30Z. Guards the live-observed case end to end.
        let profile = TrackProfile(
            estimatedSectionCount: 11,
            sectionStartTimes: [7.3, 24.7, 46.1, 46.1, 92.1, 111.5, 124.3, 205.5, 228.0, 287.3]
        )
        let sections = DefaultSessionPlanner.makeSections(trackStart: 0, trackEnd: 301, profile: profile)
        let starts = sections.map { Int($0.start.rounded()) }
        // 7.3 intro merged (< 8 s floor), 46.1 duplicate dropped → boundaries land on sections.
        #expect(starts == [0, 25, 46, 92, 112, 124, 206, 228, 287])
    }

    @Test("a near-track-end boundary is excluded so the final section isn't sub-floor")
    func nearEndBoundaryExcluded() {
        // 200 s track; boundary at 196 is within the 8 s floor of the end → excluded,
        // so the final section runs 80→200 instead of leaving a 4 s tail.
        let profile = TrackProfile(estimatedSectionCount: 3, sectionStartTimes: [80, 196])
        let sections = DefaultSessionPlanner.makeSections(trackStart: 0, trackEnd: 200, profile: profile)
        #expect(sections.map { $0.start } == [0, 80])
        #expect(sections.map { $0.end } == [80, 200])
    }
}
