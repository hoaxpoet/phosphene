// MultiSegmentSmokeTest — V.7.6.2 done-when smoke check.
//
// Loads the production preset catalog, builds a 600 s synthetic playlist, plans
// it, and walks every segment transition asserting:
// - No NaN / zero-duration segments.
// - No segment exceeds its preset's maxDuration(forSection:).
// - Every segment's [start, end) covers a positive interval.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

private func loadProductionCatalog() throws -> [PresetDescriptor] {
    guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
        return []
    }
    let contents = try FileManager.default.contentsOfDirectory(
        at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )
    let jsonFiles = contents.filter { $0.pathExtension == "json" }
    let decoder = JSONDecoder()
    return try jsonFiles.map { try decoder.decode(PresetDescriptor.self, from: try Data(contentsOf: $0)) }
}

@Suite("MultiSegmentSmokeTest")
struct MultiSegmentSmokeTest {

    @Test("600 s synthetic playlist plans cleanly across full production catalog")
    func smokePlanFullCatalog() throws {
        let catalog = try loadProductionCatalog()
        guard !catalog.isEmpty else { return }
        #expect(catalog.count >= 13, "Expected ≥ 13 production preset sidecars")

        // Build a 600 s synthetic playlist: 4 tracks × 150 s each, varied moods so
        // the scorer has reason to pick different presets and transition styles.
        let identities: [TrackIdentity] = [
            TrackIdentity(title: "Smoke 1", artist: "A", duration: 150),
            TrackIdentity(title: "Smoke 2", artist: "A", duration: 150),
            TrackIdentity(title: "Smoke 3", artist: "A", duration: 150),
            TrackIdentity(title: "Smoke 4", artist: "A", duration: 150)
        ]
        let profiles: [TrackProfile] = [
            TrackProfile(bpm: 130, mood: EmotionalState(valence: 0.7, arousal: 0.8), estimatedSectionCount: 1),
            TrackProfile(bpm: 90,  mood: EmotionalState(valence: 0.2, arousal: -0.3), estimatedSectionCount: 2),
            TrackProfile(bpm: 110, mood: EmotionalState(valence: 0.5, arousal: 0.5), estimatedSectionCount: 3),
            TrackProfile(bpm: 140, mood: EmotionalState(valence: 0.6, arousal: 0.7), estimatedSectionCount: 1)
        ]
        let tracks = Array(zip(identities, profiles))

        let planner = DefaultSessionPlanner()
        let plan = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)

        // Walk every segment, asserting invariants.
        var totalSegments = 0
        for plannedTrack in plan.tracks {
            #expect(!plannedTrack.segments.isEmpty)
            for seg in plannedTrack.segments {
                totalSegments += 1
                let span = seg.plannedEndTime - seg.plannedStartTime

                // No NaN.
                #expect(!seg.plannedStartTime.isNaN)
                #expect(!seg.plannedEndTime.isNaN)
                // Positive duration.
                #expect(span > 0, "Segment for \(seg.preset.name) has zero or negative duration: \(span)")
                // Ceiling: segment never exceeds preset.maxDuration.
                let ceiling = seg.preset.maxDuration(forSection: nil)
                // Ceiling check is plus a small epsilon for the section-context lookup
                // mismatch (planner uses currentSection=nil here too).
                #expect(span <= ceiling + 0.001,
                    "\(seg.preset.name) segment span \(span) exceeds maxDuration \(ceiling)")
            }
        }
        #expect(totalSegments >= 4, "Expected at least one segment per track")
    }
}
