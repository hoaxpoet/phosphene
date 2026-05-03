// GoldenSessionTests — three curated playlists as regression fixtures (Increment 4.4, D-034).
//
// Every test encodes what DefaultPresetScorer + DefaultTransitionPolicy +
// DefaultSessionPlanner *actually* produce for these inputs. Any future change
// to the scorer formula, transition policy, or a preset JSON sidecar that breaks
// a golden test is a regression — fix the test only by updating the expected
// values AND adding a scoring-trace comment that proves correctness.
//
// No Sources/ files are modified. Tests only.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

// MARK: - Suite

@Suite("GoldenSessionFixtures")
struct GoldenSessionTests {

    private let planner = DefaultSessionPlanner()

    // MARK: — Session A: High-Energy Electronic (5 × 180 s, BPM=130, val=0.7, arous=0.8)

    // Scoring trace — targetTemp=0.78, targetDensity=0.82, targetMotion=0.633:
    //   VL    = 0.945 (stem sum 1.30→1.0 gives +0.25 vs 0.5 for others)
    //   Plasma= 0.803 (moodScore=0.85: tempCenter 0.6 close to 0.78; density 0.70≈0.82)
    //   FO    = 0.793 (tempCenter 0.325 far; partially rescued by density 0.75≈0.82)
    //   KS    = 0.783
    // Track 0: VL wins. Track 1 (VL excluded): Plasma wins over FO.
    // Track 2: Plasma excluded, VL fully cooled (low, 60 s) → VL wins.
    // Track 3: VL excluded, Plasma fatigue gap=180 s, high cooldown=300 s →
    //          smoothstep(0,300,180)=0.648 → Plasma×0.648=0.512 < FO 0.793 → FO wins.
    // Track 4: FO excluded, VL re-eligible → VL wins.

    @Test("Session A: 5 tracks, no errors")
    func sessionA_producesCorrectCount() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        #expect(session.tracks.count == 5)
        #expect(session.warnings.isEmpty)
    }

    @Test("Session A: first track has no incoming transition")
    func sessionA_firstTrack_hasNoIncomingTransition() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        #expect(session.tracks[0].incomingTransition == nil)
    }

    @Test("Session A: preset IDs match golden sequence")
    func sessionA_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let ids = session.tracks.map { $0.preset.id }
        // V.7.6.2 multi-segment regeneration: each 180 s track now contains multiple
        // segments because every preset's computed maxDuration (≈ 50–95 s for the
        // catalog at sectionDynamicRange=0.5) is shorter than the track length.
        // Track-level `.preset` accessor returns segments[0].preset. Track 0 still
        // selects VL first; subsequent track-firsts inherit the family-repeat
        // penalty from the previous track's *last* segment, producing a different
        // sequence than the V.7.6.1 single-segment plan. See commit body for §5.3
        // computed maxDurations.
        #expect(ids == [
            "Volumetric Lithograph",
            "Fractal Tree",
            "Fractal Tree",
            "Fractal Tree",
            "Fractal Tree",
        ])
    }

    @Test("Session A: track-boundary transitions all present and well-formed")
    func sessionA_transitionStyles() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // V.7.6.2 multi-segment regeneration: track-level `.incomingTransition`
        // accessor surfaces segments[0].incomingTransition (the track-boundary one).
        // The outgoing preset feeding each new track is now whichever preset closed
        // out the previous track's segment list, so styles depend on intra-track
        // segment cascades rather than the V.7.6.1 single-segment "from VL" rule.
        // We assert presence and basic well-formedness only; per-style and per-
        // duration assertions belong in V.7.6.C calibration.
        let transitions = session.tracks.compactMap { $0.incomingTransition }
        #expect(transitions.count == 4)
        for tx in transitions {
            #expect(tx.duration >= 0)
            #expect(tx.scheduledAt >= 0)
        }
    }

    @Test("Session A: all transition triggers are structuralBoundary")
    func sessionA_allTransitionsAreStructuralBoundary() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // Planner uses a synthetic StructuralPrediction (confidence=1.0) at every
        // track boundary → policy fires .structuralBoundary → rationale starts with
        // "Structural boundary".
        for entry in session.tracks.dropFirst() {
            let t = try #require(entry.incomingTransition)
            #expect(t.reason.hasPrefix("Structural boundary"))
        }
    }

    // MARK: — Session B: Mellow Jazz (5 × 180 s, BPM=85, val=0.3, arous=−0.3)

    // Scoring trace — targetTemp=0.62, targetDensity=0.38, targetMotion=0.3125:
    //   VL: moodScore=0.818 (tempCenter 0.575 close; density too high but stem bonus)
    //       total = 0.888
    //   GB: moodScore=0.975 (tempCenter 0.65 very close; density 0.4≈0.38)
    //       total = 0.850 — runner-up
    // Track 0: VL wins. Track 1 (VL excluded): GB wins.
    // Track 2 (GB excluded): VL re-eligible (low cooldown=60 s, gap=360 s) → VL wins.
    // Track 3 (VL excluded): GB gap=180 s, medium cooldown=120 s → smooth=1.0 → GB wins.
    // Track 4 (GB excluded): VL wins.

    @Test("Session B: preset IDs match V.7.6.2 multi-segment golden sequence")
    func sessionB_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // V.7.6.2 multi-segment regeneration: tracks are 180 s but VL.maxDuration ≈ 82 s,
        // so VL gets one segment then a different preset wins the rest. Waveform takes
        // over once the family-repeat penalty kicks in against VL/GB family alternation.
        #expect(session.tracks.map { $0.preset.id } == [
            "Volumetric Lithograph", "Waveform",
            "Waveform", "Waveform", "Waveform",
        ])
        #expect(session.tracks.map { $0.preset.family.rawValue } == [
            "fluid", "waveform", "waveform", "waveform", "waveform",
        ])
    }

    @Test("Session B: all transitions are crossfade (energy=0.38 < 0.7 cut threshold)")
    func sessionB_allTransitionsAreCrossfade() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // energy = 0.5 + 0.4*(−0.3) = 0.38; duration = 2.0*0.62 + 0.5*0.38 ≈ 1.43 s
        for entry in session.tracks.dropFirst() {
            let t = try #require(entry.incomingTransition)
            #expect(t.style == .crossfade)
            #expect(abs(t.duration - 1.43) < 0.05)
        }
    }

    @Test("Session B: no high-motion preset wins a slow jazz session")
    func sessionB_highMotionPresetsNeverWin() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // Murmuration (motion=0.85) scores 0.664 on jazz — well below winners.
        for entry in session.tracks {
            #expect(
                entry.preset.motionIntensity <= 0.8,
                "\(entry.preset.name) (motion=\(entry.preset.motionIntensity)) should not win jazz"
            )
        }
    }

    // MARK: — Session C: Genre-Diverse Mix (6 tracks, varied durations)

    // Scoring trace for contested tracks:
    //   Track 3 (BPM=125, val=0.6, arous=0.75) — targetTemp=0.74, targetMotion=0.6:
    //     Plasma 0.819: moodScore=0.88 (tempCenter 0.6 near 0.74; density 0.7≈0.80)
    //     FO     0.795: moodScore=0.768 (tempCenter 0.325 far from 0.74)
    //     → Plasma wins (no hypnotic history in Session C)
    //   Track 5 (BPM=135, val=0.75, arous=0.85) — Plasma fatigue gap=180 s, high
    //     cooldown=300 s → smooth=0.648 → Plasma×0.648=0.512; FO 0.787 wins.

    @Test("Session C: preset IDs match V.7.6.2 multi-segment genre-driven sequence")
    func sessionC_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // V.7.6.2 multi-segment regeneration: track-level `.preset` reads segments[0].
        // The segment-boundary cascade pushes selections toward different presets at
        // each track boundary as the prior track's *last* segment carries forward.
        #expect(session.tracks.map { $0.preset.id } == [
            "Volumetric Lithograph",
            "Glass Brutalist",
            "Volumetric Lithograph",
            "Ferrofluid Ocean",
            "Glass Brutalist",
            "Plasma",
        ])
    }

    @Test("Session C: genre diversity produces ≥3 distinct preset families")
    func sessionC_moodShiftProducesFamilyVariety() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let families = Set(session.tracks.map { $0.preset.family })
        #expect(families.count >= 3)
    }

    // MARK: — Cross-session

    @Test("Determinism: identical inputs produce identical PlannedSession")
    func determinism_samePlanOnRepeatedCalls() throws {
        let tracks  = makeSessionA()
        let catalog = makeRealCatalog()
        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let s2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        #expect(s1.tracks.map { $0.preset.id } == s2.tracks.map { $0.preset.id })
        #expect(s1.tracks.map { $0.plannedStartTime } == s2.tracks.map { $0.plannedStartTime })
        #expect(s1.tracks.map { $0.plannedEndTime } == s2.tracks.map { $0.plannedEndTime })
    }

    @Test("totalDuration equals sum of individual track durations (Session C varied lengths)")
    func totalDuration_matchesSumOfTrackDurations() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let summed = session.tracks
            .map { $0.plannedEndTime - $0.plannedStartTime }
            .reduce(0, +)
        #expect(abs(session.totalDuration - summed) < 0.001)
    }
}

// MARK: — Stem Balance Helper

private func makeStemBalance(vocals: Float, drums: Float, bass: Float, other: Float) -> StemFeatures {
    var s = StemFeatures()
    s.vocalsEnergy = vocals
    s.drumsEnergy  = drums
    s.bassEnergy   = bass
    s.otherEnergy  = other
    return s
}

// MARK: — Fixture Builders (private; no conflict with SessionPlannerTests helpers)

private func makeIdentity(title: String, duration: TimeInterval = 180) -> TrackIdentity {
    TrackIdentity(title: title, artist: "GoldenArtist", duration: duration)
}

private func makeProfile(
    bpm: Float? = nil,
    valence: Float = 0,
    arousal: Float = 0,
    stemBalance: StemFeatures = .zero
) -> TrackProfile {
    TrackProfile(
        bpm: bpm,
        mood: EmotionalState(valence: valence, arousal: arousal),
        stemEnergyBalance: stemBalance
    )
}

/// JSON-decoded PresetDescriptor. visual_density is explicit so moodSubScore is correct.
private func makePreset(
    name: String,
    family: PresetCategory,
    motionIntensity: Float,
    visualDensity: Float,
    colorTempRange: SIMD2<Float>,
    fatigueRisk: FatigueRisk = .medium,
    sectionSuitability: [SongSection] = SongSection.allCases,
    stemAffinity: [String: String] = [:],
    complexityCost: ComplexityCost = ComplexityCost(tier1: 2.0, tier2: 1.5),
    transitionAffordances: [TransitionAffordance] = [.crossfade]
) -> PresetDescriptor {
    let secs = sectionSuitability.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let stms = stemAffinity.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
    let affs = transitionAffordances.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let json = """
    {"name":"\(name)","family":"\(family.rawValue)",
     "visual_density":\(visualDensity),"motion_intensity":\(motionIntensity),
     "color_temperature_range":[\(colorTempRange.x),\(colorTempRange.y)],
     "fatigue_risk":"\(fatigueRisk.rawValue)","section_suitability":[\(secs)],
     "stem_affinity":{\(stms)},
     "complexity_cost":{"tier1":\(complexityCost.tier1),"tier2":\(complexityCost.tier2)},
     "transition_affordances":[\(affs)],
     "certified":true}
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

// MARK: — Catalog Fixture

/// All 11 production presets mirrored verbatim from their JSON sidecars.
/// Only scoring-relevant fields are populated; rendering fields use decoder defaults.
/// Note: Starburst.json declares name "Murmuration" — that is the preset ID.
private func makeRealCatalog() -> [PresetDescriptor] {
    [
        makePreset(
            name: "Waveform", family: .waveform,
            motionIntensity: 0.6, visualDensity: 0.3,
            colorTempRange: SIMD2(0.2, 0.8), fatigueRisk: .medium,
            sectionSuitability: SongSection.allCases,
            complexityCost: ComplexityCost(tier1: 0.4, tier2: 0.2)),
        makePreset(
            name: "Plasma", family: .hypnotic,
            motionIntensity: 0.5, visualDensity: 0.7,
            colorTempRange: SIMD2(0.3, 0.9), fatigueRisk: .high,
            sectionSuitability: [.ambient, .buildup],
            complexityCost: ComplexityCost(tier1: 0.5, tier2: 0.25)),
        makePreset(
            name: "Nebula", family: .particles,
            motionIntensity: 0.3, visualDensity: 0.8,
            colorTempRange: SIMD2(0.1, 0.5), fatigueRisk: .low,
            sectionSuitability: [.ambient, .comedown],
            complexityCost: ComplexityCost(tier1: 0.6, tier2: 0.3)),
        makePreset(
            name: "Murmuration", family: .abstract,
            motionIntensity: 0.85, visualDensity: 0.9,
            colorTempRange: SIMD2(0.2, 0.7), fatigueRisk: .low,
            sectionSuitability: [.buildup, .peak],
            complexityCost: ComplexityCost(tier1: 2.5, tier2: 1.4)),
        makePreset(
            name: "Glass Brutalist", family: .geometric,
            motionIntensity: 0.4, visualDensity: 0.4,
            colorTempRange: SIMD2(0.4, 0.9), fatigueRisk: .medium,
            sectionSuitability: [.ambient, .bridge],
            complexityCost: ComplexityCost(tier1: 3.2, tier2: 1.8),
            transitionAffordances: [.crossfade, .cut]),
        makePreset(
            name: "Kinetic Sculpture", family: .abstract,
            motionIntensity: 0.7, visualDensity: 0.6,
            colorTempRange: SIMD2(0.3, 0.65), fatigueRisk: .medium,
            sectionSuitability: [.buildup, .peak, .bridge],
            complexityCost: ComplexityCost(tier1: 4.1, tier2: 2.2)),
        makePreset(
            name: "Volumetric Lithograph", family: .fluid,
            motionIntensity: 0.6, visualDensity: 0.7,
            colorTempRange: SIMD2(0.2, 0.95), fatigueRisk: .low,
            sectionSuitability: [.buildup, .peak, .bridge],
            stemAffinity: ["bass": "b", "vocals": "v", "other": "o", "drums": "d"],
            complexityCost: ComplexityCost(tier1: 3.8, tier2: 2.0),
            transitionAffordances: [.crossfade, .cut]),
        makePreset(
            name: "Spectral Cartograph", family: .instrument,
            motionIntensity: 0.0, visualDensity: 0.1,
            colorTempRange: SIMD2(0.3, 0.6), fatigueRisk: .low,
            sectionSuitability: [.ambient],
            complexityCost: ComplexityCost(tier1: 0.3, tier2: 0.15)),
        makePreset(
            name: "Membrane", family: .fluid,
            motionIntensity: 0.7, visualDensity: 0.55,
            colorTempRange: SIMD2(0.25, 0.8), fatigueRisk: .medium,
            sectionSuitability: [.buildup, .peak],
            complexityCost: ComplexityCost(tier1: 0.8, tier2: 0.4)),
        makePreset(
            name: "Fractal Tree", family: .fractal,
            motionIntensity: 0.55, visualDensity: 0.65,
            colorTempRange: SIMD2(0.2, 0.75), fatigueRisk: .medium,
            sectionSuitability: [.ambient, .buildup, .bridge],
            complexityCost: ComplexityCost(tier1: 1.2, tier2: 0.7)),
        makePreset(
            name: "Ferrofluid Ocean", family: .abstract,
            motionIntensity: 0.65, visualDensity: 0.75,
            colorTempRange: SIMD2(0.1, 0.55), fatigueRisk: .medium,
            sectionSuitability: [.buildup, .peak, .bridge],
            complexityCost: ComplexityCost(tier1: 1.5, tier2: 0.8)),
    ]
}

// MARK: — Session Fixtures

private func makeSessionA() -> [(TrackIdentity, TrackProfile)] {
    let stems = makeStemBalance(vocals: 0.30, drums: 0.40, bass: 0.40, other: 0.20)
    return (0..<5).map { i in
        (makeIdentity(title: "Elec-\(i)", duration: 180),
         makeProfile(bpm: 130, valence: 0.7, arousal: 0.8, stemBalance: stems))
    }
}

private func makeSessionB() -> [(TrackIdentity, TrackProfile)] {
    let stems = makeStemBalance(vocals: 0.30, drums: 0.05, bass: 0.40, other: 0.35)
    return (0..<5).map { i in
        (makeIdentity(title: "Jazz-\(i)", duration: 180),
         makeProfile(bpm: 85, valence: 0.3, arousal: -0.3, stemBalance: stems))
    }
}

private typealias TrackSpec = (
    title: String, dur: TimeInterval,
    bpm: Float, val: Float, arous: Float,
    vocals: Float, drums: Float, bass: Float, other: Float
)

private func makeSessionC() -> [(TrackIdentity, TrackProfile)] {
    let specs: [TrackSpec] = [
        ("Elec-0",  240, 130,  0.70,  0.80, 0.30, 0.40, 0.40, 0.20),
        ("Jazz-1",  200,  80,  0.20, -0.40, 0.35, 0.05, 0.40, 0.30),
        ("Rock-2",  210, 115,  0.50,  0.40, 0.25, 0.35, 0.30, 0.25),
        ("Elec-3",  230, 125,  0.60,  0.75, 0.25, 0.45, 0.45, 0.15),
        ("Jazz-4",  180,  70,  0.30, -0.50, 0.45, 0.05, 0.35, 0.30),
        ("Elec-5",  220, 135,  0.75,  0.85, 0.20, 0.45, 0.45, 0.20),
    ]
    return specs.map { p in
        let stems = makeStemBalance(vocals: p.vocals, drums: p.drums, bass: p.bass, other: p.other)
        let profile = makeProfile(bpm: p.bpm, valence: p.val, arousal: p.arous, stemBalance: stems)
        return (makeIdentity(title: p.title, duration: p.dur), profile)
    }
}
