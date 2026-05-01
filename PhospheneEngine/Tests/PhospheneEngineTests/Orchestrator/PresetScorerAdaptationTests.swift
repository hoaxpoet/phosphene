// PresetScorerAdaptationTests — Unit tests for U.6b adaptation fields in DefaultPresetScorer.
//
// Verifies that familyBoosts, temporarilyExcludedFamilies, and sessionExcludedPresets
// each work independently in the scorer, following D-053 additive-defaults pattern.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

// MARK: - Suite

@Suite("DefaultPresetScorer — U.6b Adaptation Fields")
struct PresetScorerAdaptationTests {

    private let scorer = DefaultPresetScorer()

    // MARK: 1 — Family boost raises score additively

    @Test("familyBoosts adds +0.3 to family's final score, clamped at 1.0")
    func familyBoostRaisesScore() {
        let preset  = makePreset(name: "Fluid1", family: .fluid)
        let track   = makeTrack()
        let baseCtx = makeContext()
        let boostCtx = makeContext(familyBoosts: [.fluid: 0.3])

        let baseScore  = scorer.score(preset: preset, track: track, context: baseCtx)
        let boostScore = scorer.score(preset: preset, track: track, context: boostCtx)
        let breakdown  = scorer.breakdown(preset: preset, track: track, context: boostCtx)

        #expect(boostScore > baseScore, "boost should raise score (base=\(baseScore) boosted=\(boostScore))")
        #expect(boostScore <= 1.0, "score must not exceed 1.0 after boost")
        #expect(breakdown.familyBoost == 0.3)
    }

    // MARK: 2 — Family boost does not affect other families

    @Test("familyBoost for .fluid does not change score for .geometric preset")
    func familyBoostDoesNotCrossContaminate() {
        let geometric = makePreset(name: "Geo1", family: .geometric)
        let track     = makeTrack()
        let baseCtx  = makeContext()
        let boostCtx = makeContext(familyBoosts: [.fluid: 0.3])

        let baseScore  = scorer.score(preset: geometric, track: track, context: baseCtx)
        let boostScore = scorer.score(preset: geometric, track: track, context: boostCtx)

        #expect(baseScore == boostScore,
                "boost for .fluid must not affect .geometric score (\(baseScore) vs \(boostScore))")
    }

    // MARK: 3 — Temporarily excluded family is hard-excluded

    @Test("temporarilyExcludedFamilies hard-excludes the preset")
    func temporarilyExcludedFamilyIsExcluded() {
        let preset  = makePreset(name: "Geo2", family: .geometric)
        let track   = makeTrack()
        let ctx = makeContext(temporarilyExcludedFamilies: [.geometric])

        let bd = scorer.breakdown(preset: preset, track: track, context: ctx)

        #expect(bd.excluded == true)
        #expect(bd.total == 0)
        #expect(bd.exclusionReason?.contains("temporarily excluded") == true)
    }

    // MARK: 4 — sessionExcludedPresets hard-excludes by preset ID

    @Test("sessionExcludedPresets hard-excludes a preset by ID")
    func sessionExcludedPresetIsExcluded() {
        let preset  = makePreset(name: "Fractal1", family: .fractal)
        let track   = makeTrack()
        let ctx = makeContext(sessionExcludedPresets: ["Fractal1"])

        let bd = scorer.breakdown(preset: preset, track: track, context: ctx)

        #expect(bd.excluded == true)
        #expect(bd.total == 0)
        #expect(bd.exclusionReason?.contains("excluded by user") == true)
    }

    // MARK: 5 — All three fields are independent: boost for family A doesn't unblock excluded B

    @Test("sessionExcluded preset stays excluded even when its family has a boost")
    func exclusionBeatsBoost() {
        let preset  = makePreset(name: "Fluid2", family: .fluid)
        let track   = makeTrack()
        let ctx = makeContext(
            familyBoosts: [.fluid: 0.3],
            sessionExcludedPresets: ["Fluid2"]
        )

        let bd = scorer.breakdown(preset: preset, track: track, context: ctx)

        #expect(bd.excluded == true, "session-excluded preset must stay excluded even with family boost")
    }

    // MARK: 6 — Default empty fields match existing behaviour (backward compat)

    @Test("Empty adaptation fields produce byte-identical scores to baseline context")
    func emptyAdaptationFieldsMatchBaseline() {
        let preset  = makePreset(name: "Abstract1", family: .abstract)
        let track   = makeTrack(bpm: 120, valence: 0.3, arousal: 0.4)

        let baseline = makeContext()
        let withEmptyFields = makeContext(
            familyBoosts: [:],
            temporarilyExcludedFamilies: [],
            sessionExcludedPresets: []
        )

        let s1 = scorer.score(preset: preset, track: track, context: baseline)
        let s2 = scorer.score(preset: preset, track: track, context: withEmptyFields)

        #expect(s1 == s2, "empty adaptation fields must not change score (s1=\(s1), s2=\(s2))")
    }
}

// MARK: - Fixture Builders

private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .abstract,
    motionIntensity: Float = 0.5,
    colorTemperatureRange: SIMD2<Float> = SIMD2(0.3, 0.7)
) -> PresetDescriptor {
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "visual_density": 0.5,
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTemperatureRange.x), \(colorTemperatureRange.y)],
        "fatigue_risk": "medium",
        "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func makeTrack(
    bpm: Float? = nil,
    valence: Float = 0.0,
    arousal: Float = 0.0
) -> TrackProfile {
    TrackProfile(bpm: bpm, mood: EmotionalState(valence: valence, arousal: arousal), stemEnergyBalance: .zero)
}

private func makeContext(
    deviceTier: DeviceTier = .tier1,
    familyBoosts: [PresetCategory: Float] = [:],
    temporarilyExcludedFamilies: Set<PresetCategory> = [],
    sessionExcludedPresets: Set<String> = []
) -> PresetScoringContext {
    PresetScoringContext(
        deviceTier: deviceTier,
        familyBoosts: familyBoosts,
        temporarilyExcludedFamilies: temporarilyExcludedFamilies,
        sessionExcludedPresets: sessionExcludedPresets
    )
}
