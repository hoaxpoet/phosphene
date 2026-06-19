// PlannerSectionCountScalingTests — guards the BUG-042 ↔ local-file-planning link.
//
// The planner divides each track into `profile.estimatedSectionCount` slices
// (SessionPlanner+Segments.makeSections) and emits ≥1 PlannedPresetSegment per
// slice. `estimatedSectionCount` is `mir.latestStructuralPrediction.sectionIndex + 1`
// (SessionPreparer+Analysis), i.e. the StructuralAnalyzer's boundary count.
//
// The 2026-05-28 local-file-planning revert (VisualizerEngine+LocalFilePlayback)
// disabled `buildPlan()` for local files because the orchestrator "cycled through
// every preset … one every ~5 s." This test pins the mechanism: a note-scale
// (pre-BUG-042) section count explodes the segment count, while a section-scale
// (post-BUG-042) count keeps it sane — so BUG-042's fix is a load-bearing
// precondition for re-enabling local-file planning.

import Testing
import Foundation
@testable import Orchestrator
import Presets
import Session
import Shared

struct PlannerSectionCountScalingTests {

    @Test("Planner segment count tracks estimatedSectionCount — BUG-042 keeps LF planning sane")
    func planner_segmentCount_tracksSectionCount() throws {
        let planner = DefaultSessionPlanner()
        let catalog = Self.makeCatalog()

        func segmentCount(forSectionCount n: Int) throws -> Int {
            let identity = TrackIdentity(title: "Smells Like Teen Spirit", artist: "Nirvana", duration: 298)
            let profile = TrackProfile(
                bpm: 116,
                mood: EmotionalState(valence: -0.2, arousal: 0.75),   // driving rock
                stemEnergyBalance: Self.rockBalance,
                estimatedSectionCount: n)
            let session = try planner.plan(tracks: [(identity, profile)], catalog: catalog, deviceTier: .tier2)
            return session.tracks[0].segments.count
        }

        let sane = try segmentCount(forSectionCount: 9)     // post-BUG-042: SLTS live ≈ 9 sections
        let junk = try segmentCount(forSectionCount: 180)   // pre-BUG-042: note-scale junk on a 5-min track

        print("Planner segments on a 298 s track: sectionCount=9 → \(sane);  sectionCount=180 → \(junk)")

        #expect(sane <= 12,
                "Post-BUG-042 section count (9) should yield a sane segment count, got \(sane).")
        #expect(junk >= 30,
                "Pre-BUG-042 junk section count (180) should explode the segment count (the 2026-05-28 cycling), got \(junk).")
        #expect(junk > sane * 3,
                "The junk count must dominate — that gap is the cycling BUG-042 removes (\(junk) vs \(sane)).")
    }

    // MARK: - Fixtures

    private static let rockBalance: StemFeatures = {
        var s = StemFeatures()
        s.drumsEnergy = 0.8; s.bassEnergy = 0.7; s.otherEnergy = 0.7; s.vocalsEnergy = 0.5
        return s
    }()

    /// Seven differentiated presets (varied families so the family-repeat penalty
    /// has room to pick variety, not walk a tie). Only scoring-relevant fields set.
    private static func makeCatalog() -> [PresetDescriptor] {
        [
            makePreset(name: "Waveform", family: "waveform", motion: 0.6, density: 0.3),
            makePreset(name: "Plasma", family: "hypnotic", motion: 0.7, density: 0.7),
            makePreset(name: "Ferrofluid Ocean", family: "geometric", motion: 0.45, density: 0.75),
            makePreset(name: "Murmuration", family: "particles", motion: 0.85, density: 0.8),
            makePreset(name: "Membrane", family: "reaction", motion: 0.5, density: 0.6),
            makePreset(name: "Lumen Mosaic", family: "fractal", motion: 0.4, density: 0.65),
            makePreset(name: "Dragon Bloom", family: "painterly", motion: 0.7, density: 0.85),
        ]
    }

    private static func makePreset(name: String, family: String, motion: Float, density: Float) -> PresetDescriptor {
        let json = """
        {"name":"\(name)","family":"\(family)",
         "visual_density":\(density),"motion_intensity":\(motion),
         "color_temperature_range":[0.2,0.8],"fatigue_risk":"medium",
         "section_suitability":["ambient","buildup","peak","bridge","comedown"],
         "stem_affinity":{},"complexity_cost":{"tier1":1.0,"tier2":0.6},
         "transition_affordances":["crossfade"],"is_diagnostic":false,"certified":true}
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }
}
