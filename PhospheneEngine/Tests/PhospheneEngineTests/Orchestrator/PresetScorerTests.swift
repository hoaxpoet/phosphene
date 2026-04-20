// PresetScorerTests — unit tests for DefaultPresetScorer (Increment 4.1).
//
// All tests use hand-built fixture values — no real preset JSON loaded.
// Fixture builders at the bottom keep tests compact and readable.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

// MARK: - Test Suite

@Suite("DefaultPresetScorer")
struct PresetScorerTests {

    private let scorer = DefaultPresetScorer()

    // MARK: 1 — Determinism

    @Test("Same inputs produce identical scores")
    func determinism() {
        let preset  = makePreset(name: "A", family: .fluid)
        let track   = makeTrack(bpm: 120, valence: 0.3, arousal: 0.4)
        let context = makeContext()

        let score1 = scorer.score(preset: preset, track: track, context: context)
        let score2 = scorer.score(preset: preset, track: track, context: context)

        #expect(score1 == score2)
    }

    // MARK: 2 — High-energy track ranks high-motion preset first

    @Test("140 BPM high-arousal track ranks high-motion preset above low-motion")
    func highEnergyTrackRanksHighMotionFirst() {
        let highMotion = makePreset(name: "Fast", family: .geometric, motionIntensity: 0.85)
        let lowMotion  = makePreset(name: "Slow", family: .abstract,  motionIntensity: 0.3)
        let track      = makeTrack(bpm: 140, valence: 0.5, arousal: 0.9)
        let context    = makeContext()

        let ranked = scorer.rank(presets: [lowMotion, highMotion], track: track, context: context)

        #expect(ranked.count == 2)
        #expect(ranked[0].0.name == "Fast",
                "High-motion preset should rank first for a 140 BPM high-arousal track")
    }

    // MARK: 3 — Mood mismatch penalized

    @Test("Sad track (valence -0.8) scores higher against cool-palette preset")
    func moodMismatchPenalized() {
        // target_temp = 0.5 + 0.4 * (-0.8) = 0.18 (cool)
        let warmPreset = makePreset(name: "Warm", family: .fluid,
                                    colorTemperatureRange: SIMD2(0.7, 0.95))
        let coolPreset = makePreset(name: "Cool", family: .fractal,
                                    colorTemperatureRange: SIMD2(0.1, 0.3))
        let track   = makeTrack(bpm: 90, valence: -0.8, arousal: 0.0)
        let context = makeContext()

        let warmScore = scorer.score(preset: warmPreset, track: track, context: context)
        let coolScore = scorer.score(preset: coolPreset, track: track, context: context)

        #expect(coolScore > warmScore, "Cool palette should win against a sad (low-valence) track")
    }

    // MARK: 4 — Same-family repeat penalized ≥ 3×

    @Test("Same-family consecutive repeat penalized; different family wins by ≥ 3×")
    func sameFamilyRepeatPenalized() {
        let fluidA    = makePreset(name: "FluidA", family: .fluid)
        let geometric = makePreset(name: "GeoB",  family: .geometric)
        let track     = makeTrack(bpm: 120, valence: 0.0, arousal: 0.0)
        // Current preset is fluid — fluidA will be penalized 0.2×
        let currentFluid = makePreset(name: "FluidCurrent", family: .fluid)
        let context = makeContext(currentPreset: currentFluid)

        let fluidScore = scorer.score(preset: fluidA,    track: track, context: context)
        let geoScore   = scorer.score(preset: geometric, track: track, context: context)

        #expect(geoScore >= fluidScore * 3,
                "Geometric preset should outscore repeated-fluid by ≥ 3× (got fluid=\(fluidScore), geo=\(geoScore))")
    }

    // MARK: 5 — Tier 1 excludes expensive preset

    @Test("Preset exceeding tier1 frame budget is excluded")
    func tier1ExcludesExpensivePreset() {
        let expensivePreset = makePreset(name: "Heavy",
                                         complexityCost: ComplexityCost(tier1: 20.0, tier2: 8.0))
        let context = PresetScoringContext.initial(deviceTier: .tier1)
        let track   = makeTrack()

        let bd = scorer.breakdown(preset: expensivePreset, track: track, context: context)

        #expect(bd.excluded == true)
        #expect(bd.total == 0)
        #expect(bd.exclusionReason != nil)
    }

    // MARK: 6 — Tier 2 accepts same expensive preset

    @Test("Same preset passes tier2 frame budget check")
    func tier2AcceptsExpensivePreset() {
        let expensivePreset = makePreset(name: "Heavy",
                                         complexityCost: ComplexityCost(tier1: 20.0, tier2: 8.0))
        let context = PresetScoringContext.initial(deviceTier: .tier2)
        let track   = makeTrack()

        let bd = scorer.breakdown(preset: expensivePreset, track: track, context: context)

        #expect(bd.excluded == false)
        #expect(bd.total > 0)
    }

    // MARK: 7 — Stem affinity match boosts score

    @Test("Drum-heavy track scores higher stemAffinity for drum-responsive preset")
    func stemAffinityMatchBoostsScore() {
        let drumPreset    = makePreset(name: "DrumResp", stemAffinity: ["drums": "beat_pulse"])
        let neutralPreset = makePreset(name: "Neutral",  stemAffinity: [:])
        let track = makeTrack(stemBalance: StemFeatures(
            drumsEnergy: 0.6
        ))
        let context = makeContext()

        let drumBD    = scorer.breakdown(preset: drumPreset,    track: track, context: context)
        let neutralBD = scorer.breakdown(preset: neutralPreset, track: track, context: context)

        #expect(drumBD.stemAffinity > neutralBD.stemAffinity,
                "Drum-responsive preset should score higher stemAffinity on a drum-heavy track")
    }

    // MARK: 8 — Empty stem_affinity is exactly neutral (0.5)

    @Test("Empty stem_affinity yields stemAffinity = 0.5")
    func emptyStemAffinityIsNeutral() {
        let preset  = makePreset(name: "NoAffinity", stemAffinity: [:])
        let track   = makeTrack(stemBalance: StemFeatures(drumsEnergy: 0.9))
        let context = makeContext()

        let bd = scorer.breakdown(preset: preset, track: track, context: context)

        #expect(bd.stemAffinity == 0.5)
    }

    // MARK: 9 — Fatigue cooldown

    @Test("Fatigue multiplier near 0 when family used 10s ago (.low cooldown), near 1.0 when 120s ago")
    func fatigueCooldown() {
        let preset  = makePreset(name: "Fluid", family: .fluid, fatigueRisk: .low)
        let track   = makeTrack()

        // Used 10 seconds ago — cooldown window is 60s → smoothstep(0, 60, 10) ≈ 0.074
        let recentEntry = PresetHistoryEntry(
            presetID: "Fluid", family: .fluid,
            startTime: 0, endTime: 90   // endTime=90, elapsed=100 → gap=10
        )
        let recentContext = makeContext(
            recentHistory: [recentEntry],
            elapsedSessionTime: 100
        )
        let recentBD = scorer.breakdown(preset: preset, track: track, context: recentContext)
        #expect(recentBD.fatigueMultiplier < 0.2,
                "10s after use with 60s cooldown, multiplier should be < 0.2 (got \(recentBD.fatigueMultiplier))")

        // Used 120 seconds ago — fully past the 60s window → smoothstep(0, 60, 120) = 1.0
        let oldEntry = PresetHistoryEntry(
            presetID: "Fluid", family: .fluid,
            startTime: 0, endTime: 80   // endTime=80, elapsed=200 → gap=120
        )
        let oldContext = makeContext(
            recentHistory: [oldEntry],
            elapsedSessionTime: 200
        )
        let oldBD = scorer.breakdown(preset: preset, track: track, context: oldContext)
        #expect(oldBD.fatigueMultiplier == 1.0,
                "120s after use with 60s cooldown, multiplier should be 1.0 (got \(oldBD.fatigueMultiplier))")
    }

    // MARK: 10 — Section suitability match / mismatch

    @Test("Section suitability scores 1.0 on match, 0.3 on mismatch")
    func sectionSuitabilityMatchAndMismatch() {
        let peakPreset = makePreset(name: "Peak", sectionSuitability: [.peak])
        let track = makeTrack()

        let matchContext    = makeContext(currentSection: .peak)
        let mismatchContext = makeContext(currentSection: .ambient)

        let matchBD    = scorer.breakdown(preset: peakPreset, track: track, context: matchContext)
        let mismatchBD = scorer.breakdown(preset: peakPreset, track: track, context: mismatchContext)

        #expect(matchBD.sectionSuitability    == 1.0)
        #expect(mismatchBD.sectionSuitability == 0.3)
    }

    // MARK: 11 — Nil section is neutral (1.0)

    @Test("Nil currentSection yields sectionSuitability = 1.0 even for narrow preset")
    func nilSectionIsNeutral() {
        let peakOnlyPreset = makePreset(name: "PeakOnly", sectionSuitability: [.peak])
        let context = makeContext(currentSection: nil)
        let track   = makeTrack()

        let bd = scorer.breakdown(preset: peakOnlyPreset, track: track, context: context)

        #expect(bd.sectionSuitability == 1.0)
    }

    // MARK: 12 — Identity exclusion

    @Test("Scoring a preset against itself (as currentPreset) returns excluded=true")
    func identityExclusion() {
        let preset  = makePreset(name: "MyPreset", family: .fluid)
        let context = makeContext(currentPreset: preset)
        let track   = makeTrack()

        let bd = scorer.breakdown(preset: preset, track: track, context: context)

        #expect(bd.excluded == true)
        #expect(bd.total == 0)
        #expect(bd.exclusionReason?.contains("MyPreset") == true)
    }

    // MARK: 13 — Rank stability across device tiers

    @Test("Only perf-excluded presets change rank at the tier boundary")
    func rankStabilityAcrossTiers() {
        let affordable  = makePreset(name: "A", family: .fluid,    complexityCost: ComplexityCost(tier1: 5, tier2: 3))
        let affordable2 = makePreset(name: "B", family: .geometric, complexityCost: ComplexityCost(tier1: 6, tier2: 4))
        let affordable3 = makePreset(name: "C", family: .fractal,   complexityCost: ComplexityCost(tier1: 8, tier2: 5))
        let affordable4 = makePreset(name: "D", family: .abstract,  complexityCost: ComplexityCost(tier1: 9, tier2: 6))
        let tooHeavy    = makePreset(name: "E", family: .hypnotic,  complexityCost: ComplexityCost(tier1: 20, tier2: 8))
        let catalog = [affordable, affordable2, affordable3, affordable4, tooHeavy]
        let track = makeTrack()

        let tier1Ranked = scorer.rank(presets: catalog, track: track, context: PresetScoringContext.initial(deviceTier: .tier1))
        let tier2Ranked = scorer.rank(presets: catalog, track: track, context: PresetScoringContext.initial(deviceTier: .tier2))

        // "E" should score 0 on tier1 (excluded) but positive on tier2
        let eTier1 = tier1Ranked.first(where: { $0.0.name == "E" })?.1 ?? -1
        let eTier2 = tier2Ranked.first(where: { $0.0.name == "E" })?.1 ?? -1
        #expect(eTier1 == 0,   "E should be excluded (score=0) on tier1")
        #expect(eTier2 > 0,    "E should be admitted on tier2")

        // Non-excluded presets A–D should appear in the same relative order on both tiers
        let tier1Names = tier1Ranked.filter { $0.1 > 0 }.map { $0.0.name }
        let tier2NamesWithoutE = tier2Ranked.filter { $0.0.name != "E" }.map { $0.0.name }
        #expect(tier1Names == tier2NamesWithoutE,
                "Non-excluded presets should rank identically across tiers")
    }
}

// MARK: - Fixture Builders

private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .abstract,
    visualDensity: Float = 0.5,
    motionIntensity: Float = 0.5,
    colorTemperatureRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    fatigueRisk: FatigueRisk = .medium,
    sectionSuitability: [SongSection] = SongSection.allCases,
    stemAffinity: [String: String] = [:],
    complexityCost: ComplexityCost = ComplexityCost(tier1: 2.0, tier2: 1.5)
) -> PresetDescriptor {
    // Build a minimal JSON blob and decode it so all defaults are applied correctly.
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "visual_density": \(visualDensity),
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTemperatureRange.x), \(colorTemperatureRange.y)],
        "fatigue_risk": "\(fatigueRisk.rawValue)",
        "section_suitability": [\(sectionSuitability.map { "\"\($0.rawValue)\"" }.joined(separator: ","))],
        "stem_affinity": {\(stemAffinity.map { "\"\($0.key)\": \"\($0.value)\"" }.joined(separator: ","))},
        "complexity_cost": {"tier1": \(complexityCost.tier1), "tier2": \(complexityCost.tier2)}
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func makeTrack(
    bpm: Float? = nil,
    valence: Float = 0.0,
    arousal: Float = 0.0,
    stemBalance: StemFeatures = .zero
) -> TrackProfile {
    TrackProfile(
        bpm: bpm,
        mood: EmotionalState(valence: valence, arousal: arousal),
        stemEnergyBalance: stemBalance
    )
}

private func makeContext(
    deviceTier: DeviceTier = .tier1,
    currentPreset: PresetDescriptor? = nil,
    recentHistory: [PresetHistoryEntry] = [],
    elapsedSessionTime: TimeInterval = 0,
    currentSection: SongSection? = nil
) -> PresetScoringContext {
    PresetScoringContext(
        deviceTier: deviceTier,
        recentHistory: recentHistory,
        currentPreset: currentPreset,
        elapsedSessionTime: elapsedSessionTime,
        currentSection: currentSection
    )
}
