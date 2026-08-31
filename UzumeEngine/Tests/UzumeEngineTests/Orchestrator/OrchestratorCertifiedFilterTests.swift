// OrchestratorCertifiedFilterTests — V.6 orchestrator certification gate.
//
// Tests:
//   1. Uncertified preset excluded when includeUncertifiedPresets == false (default).
//   2. Uncertified preset included when includeUncertifiedPresets == true.
//   3. Certified preset always included regardless of toggle.
//   4. All-uncertified catalog: planner emits noEligiblePresets warning and falls back.
//   5. Mixed catalog: certified preset scores > 0, uncertified scores 0 when toggle off.

import Testing
import Foundation
@testable import Orchestrator
@testable import Presets
@testable import Shared
import Session

// MARK: - Fixture Helpers

private func makeDescriptor(name: String, certified: Bool, family: PresetCategory = .geometric) -> PresetDescriptor {
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "certified": \(certified ? "true" : "false"),
        "visual_density": 0.5,
        "motion_intensity": 0.5,
        "complexity_cost": { "tier1": 1.0, "tier2": 1.0 }
    }
    """
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func makeTrackProfile() -> TrackProfile {
    TrackProfile(
        bpm: 120,
        key: "C",
        mood: EmotionalState(valence: 0.0, arousal: 0.0),
        spectralCentroidAvg: 2000,
        genreTags: [],
        stemEnergyBalance: StemFeatures(),
        estimatedSectionCount: 4
    )
}

private func makeContext(includeUncertified: Bool) -> PresetScoringContext {
    PresetScoringContext(
        deviceTier: .tier2,
        includeUncertifiedPresets: includeUncertified
    )
}

// MARK: - Suite

@Suite("Orchestrator Certified Filter Tests")
struct OrchestratorCertifiedFilterTests {

    let scorer = DefaultPresetScorer()
    let track = makeTrackProfile()

    // MARK: - 1. Uncertified excluded when toggle off (default)

    @Test func uncertifiedPresetExcludedWhenToggleOff() {
        let preset = makeDescriptor(name: "Uncertified", certified: false)
        let context = makeContext(includeUncertified: false)

        let bd = scorer.breakdown(preset: preset, track: track, context: context)
        #expect(bd.excluded == true)
        #expect(bd.excludedReason == "uncertified")
        #expect(bd.total == 0)
    }

    // MARK: - 2. Uncertified included when toggle on

    @Test func uncertifiedPresetIncludedWhenToggleOn() {
        let preset = makeDescriptor(name: "Uncertified", certified: false)
        let context = makeContext(includeUncertified: true)

        let bd = scorer.breakdown(preset: preset, track: track, context: context)
        #expect(bd.excluded == false)
        #expect(bd.excludedReason == nil)
        #expect(bd.total > 0)
    }

    // MARK: - 3. Certified preset always included

    @Test func certifiedPresetAlwaysIncluded() {
        let preset = makeDescriptor(name: "Certified", certified: true)

        for includeUncertified in [false, true] {
            let context = makeContext(includeUncertified: includeUncertified)
            let bd = scorer.breakdown(preset: preset, track: track, context: context)
            #expect(bd.excluded == false, "certified preset must not be excluded (toggle=\(includeUncertified))")
            #expect(bd.total > 0)
        }
    }

    // MARK: - 4. All-uncertified catalog: planner falls back gracefully

    @Test func allUncertifiedCatalogFallsBackGracefully() throws {
        let catalog = [
            makeDescriptor(name: "Alpha", certified: false),
            makeDescriptor(name: "Beta", certified: false),
        ]
        let identity = TrackIdentity(title: "Test Track", artist: "Test", album: "", duration: 180)
        let profile = makeTrackProfile()

        // The planner builds its own PresetScoringContext with includeUncertifiedPresets: false (default).
        // All presets score 0 → noEligiblePresets warning → cheapest fallback.
        let planner = DefaultSessionPlanner()
        let result = try planner.plan(
            tracks: [(identity, profile)],
            catalog: catalog,
            deviceTier: .tier2
        )

        let hasNoEligibleWarning = result.warnings.contains { $0.kind == .noEligiblePresets }
        #expect(hasNoEligibleWarning, "Expected noEligiblePresets warning when all presets are uncertified")
        // Planner must still produce a plan (fallback selection).
        #expect(result.tracks.count == 1)
    }

    // MARK: - 5. Mixed catalog: certified scores above zero, uncertified scores zero

    @Test func mixedCatalogCertifiedOutscoresUncertified() {
        let certified   = makeDescriptor(name: "Certified",   certified: true)
        let uncertified = makeDescriptor(name: "Uncertified", certified: false)
        let context = makeContext(includeUncertified: false)

        let certScore   = scorer.score(preset: certified,   track: track, context: context)
        let uncertScore = scorer.score(preset: uncertified, track: track, context: context)

        #expect(certScore > 0,         "certified preset must score > 0")
        #expect(uncertScore == 0,      "uncertified preset must score 0 when toggle off")
        #expect(certScore > uncertScore)
    }
}
