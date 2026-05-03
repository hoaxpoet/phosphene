// SessionPlannerMultiSegmentTests — V.7.6.2 §3.3 verification.
//
// Confirms:
// - Short tracks emit single segments.
// - Long tracks (track length > preset.maxDuration) emit ≥ 2 segments.
// - Section boundaries are respected (segment endTimes line up with section ends).
// - Determinism preserved with a fixed seed.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

// MARK: - Fixture builders

private func makeIdentity(title: String, duration: TimeInterval) -> TrackIdentity {
    TrackIdentity(title: title, artist: "MultiSegArtist", duration: duration)
}

private func makeProfile(sectionCount: Int = 1) -> TrackProfile {
    TrackProfile(estimatedSectionCount: sectionCount)
}

/// Build a small synthetic catalog of two distinct presets with controlled maxDurations.
/// LongPreset uses motion=0.5, density=0.5, fatigue=low → baseMax=90 → maxDuration=90 s.
/// ShortPreset uses motion=0.5, density=0.5, fatigue=high → baseMax=30 → maxDuration=30 s.
private func makeSyntheticCatalog() throws -> [PresetDescriptor] {
    let long = """
    {"name":"LongPreset","family":"organic",
     "motion_intensity":0.5,"visual_density":0.5,"fatigue_risk":"low",
     "transition_affordances":["crossfade"]}
    """
    let short = """
    {"name":"ShortPreset","family":"fluid",
     "motion_intensity":0.5,"visual_density":0.5,"fatigue_risk":"high",
     "transition_affordances":["crossfade"]}
    """
    let decoder = JSONDecoder()
    return [
        try decoder.decode(PresetDescriptor.self, from: Data(long.utf8)),
        try decoder.decode(PresetDescriptor.self, from: Data(short.utf8))
    ]
}

@Suite("SessionPlannerMultiSegment")
struct SessionPlannerMultiSegmentTests {

    @Test("Short track (20 s) emits one segment, terminationReason=trackEnded")
    func shortTrackSingleSegment() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "ShortTrack", duration: 20), makeProfile())
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        #expect(plan.tracks.count == 1)
        #expect(plan.tracks[0].segments.count == 1)
        #expect(plan.tracks[0].segments[0].terminationReason == .trackEnded)
        #expect(plan.tracks[0].segments[0].plannedStartTime == 0)
        #expect(plan.tracks[0].segments[0].plannedEndTime == 20)
    }

    @Test("Long track (300 s, 1 section) emits ≥ 2 segments, mid-segment termination=maxDurationReached")
    func longTrackMultiSegment() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "LongTrack", duration: 300), makeProfile(sectionCount: 1))
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let segments = plan.tracks[0].segments
        #expect(segments.count >= 2, "300 s track should split into ≥ 2 segments")
        // Every non-final segment terminates by maxDurationReached (single section).
        for seg in segments.dropLast() {
            #expect(seg.terminationReason == .maxDurationReached,
                "Mid-segment of single-section track should terminate by maxDurationReached")
        }
        #expect(segments.last?.terminationReason == .trackEnded)
        // Times are contiguous, no gaps.
        for i in 1..<segments.count {
            #expect(abs(segments[i].plannedStartTime - segments[i - 1].plannedEndTime) < 0.001)
        }
        // Total span equals track duration.
        #expect(abs(segments.last!.plannedEndTime - 300) < 0.001) // swiftlint:disable:this force_unwrapping
    }

    @Test("Section boundaries land within ±1 s of even split for multi-section track")
    func sectionBoundariesRespected() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try makeSyntheticCatalog()
        // 90 s / 3 sections = 30 s per section. Each section is shorter than LongPreset's
        // 90 s ceiling — so each section produces exactly one segment, all distinct due
        // to family-repeat rotation. Segment boundaries match section boundaries.
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "ThreeSection", duration: 90), makeProfile(sectionCount: 3))
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let segments = plan.tracks[0].segments
        #expect(segments.count == 3)
        let expectedBoundaries: [Double] = [30, 60, 90]
        for (idx, seg) in segments.enumerated() {
            #expect(abs(seg.plannedEndTime - expectedBoundaries[idx]) < 0.001)
        }
    }

    @Test("Determinism: same inputs + same seed → identical segment sequence")
    func multiSegmentDeterminism() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "T1", duration: 300), makeProfile(sectionCount: 1)),
            (makeIdentity(title: "T2", duration: 240), makeProfile(sectionCount: 2))
        ]
        let p1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let p2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)

        for (track1, track2) in zip(p1.tracks, p2.tracks) {
            #expect(track1.segments.count == track2.segments.count)
            for (s1, s2) in zip(track1.segments, track2.segments) {
                #expect(s1.preset.id == s2.preset.id)
                #expect(s1.plannedStartTime == s2.plannedStartTime)
                #expect(s1.plannedEndTime == s2.plannedEndTime)
                #expect(s1.terminationReason == s2.terminationReason)
            }
        }
    }

    @Test("PlannedSession.segment(at:) returns the segment covering that session time")
    func segmentAtAccessor() throws {
        let planner = DefaultSessionPlanner()
        let catalog = try makeSyntheticCatalog()
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "T1", duration: 300), makeProfile(sectionCount: 1))
        ]
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)

        // Sample several timestamps and confirm the returned segment covers them.
        for t in [10.0, 50.0, 100.0, 200.0, 290.0] {
            let seg = plan.segment(at: t)
            #expect(seg != nil, "Expected segment at t=\(t)")
            if let seg = seg {
                #expect(t >= seg.plannedStartTime && t < seg.plannedEndTime)
            }
        }
    }
}
