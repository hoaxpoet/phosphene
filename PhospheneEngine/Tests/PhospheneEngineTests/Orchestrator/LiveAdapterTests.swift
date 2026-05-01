// LiveAdapterTests — unit tests for DefaultLiveAdapter (Increment 4.5).
//
// All sessions are built via DefaultSessionPlanner.plan() — never hand-constructed.
// Fixture builders at the bottom keep test bodies compact.
//
// Scoring math is verified inline in comments where non-obvious.
// Key invariant: gap = altScore - currentScore must exceed 0.15 to trigger override.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

// MARK: - Test Suite

@Suite("DefaultLiveAdapter")
struct LiveAdapterTests {

    private let adapter = DefaultLiveAdapter()
    private let planner = DefaultSessionPlanner()

    // MARK: 1 — No reschedule when live boundary is within tolerance

    @Test("No reschedule when live deviation is 3 s (< 5 s threshold)")
    func noAdaptation_whenBoundaryWithinTolerance() throws {
        // 2-track plan; planned transition lands at session time ≈ 60 s.
        let plan = try twoTrackPlan(duration: 60)

        let liveBoundary = StructuralPrediction(
            sectionIndex: 0,
            sectionStartTime: 0,
            predictedNextBoundary: 57.0, // 3 s before planned → deviation < 5 s
            confidence: 0.8
        )
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0, elapsedTrackTime: 30,
            liveBoundary: liveBoundary, liveMood: .neutral, catalog: simpleCatalog()
        )

        #expect(result.updatedTransition == nil, "Deviation < 5 s must not trigger reschedule")
        #expect(result.presetOverride == nil)
        #expect(result.events.contains { $0.kind == .noAdaptation })
    }

    // MARK: 2 — Reschedule when deviation ≥ 5 s

    @Test("Boundary rescheduled when live deviation is 7 s (≥ 5 s threshold)")
    func boundaryRescheduled_whenLiveDiffers5sOrMore() throws {
        let plan = try twoTrackPlan(duration: 60)

        let liveBoundary = StructuralPrediction(
            sectionIndex: 0,
            sectionStartTime: 0,
            predictedNextBoundary: 67.0, // 7 s after planned → deviation > 5 s
            confidence: 0.8
        )
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0, elapsedTrackTime: 30,
            liveBoundary: liveBoundary, liveMood: .neutral, catalog: simpleCatalog()
        )

        let rescheduled = try #require(result.updatedTransition, "Deviation ≥ 5 s must reschedule")
        // liveSessionBoundary = 67 + plannedStartTime(0) = 67 s
        #expect(abs(Float(rescheduled.scheduledAt) - 67.0) < 0.01,
                "Rescheduled time must equal the live session boundary")
        #expect(result.presetOverride == nil, "Boundary reschedule must not also fire override")
        #expect(result.events.contains { $0.kind == .boundaryRescheduled })
    }

    // MARK: 3 — No reschedule when confidence < 0.5

    @Test("No reschedule when confidence is 0.4 even if deviation would exceed threshold")
    func boundaryRescheduled_onlyWhenConfidenceSufficient() throws {
        let plan = try twoTrackPlan(duration: 60)

        let lowConfidence = StructuralPrediction(
            sectionIndex: 0,
            sectionStartTime: 0,
            predictedNextBoundary: 67.0, // would trigger if confidence were ≥ 0.5
            confidence: 0.4             // below threshold
        )
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0, elapsedTrackTime: 30,
            liveBoundary: lowConfidence, liveMood: .neutral, catalog: simpleCatalog()
        )

        #expect(result.updatedTransition == nil, "Low confidence must suppress reschedule")
    }

    // MARK: 4 — No override when mood diverges but track is ≥ 40 % elapsed

    @Test("No override when mood diverges but 62 % of track has elapsed")
    func noPresetOverride_whenMoodDivergesLateInTrack() throws {
        // Pre-analyzed neutral; live mood is energetically divergent.
        let plan = try twoTrackPlan(duration: 120, mood: EmotionalState(valence: 0, arousal: 0))
        let liveMood = EmotionalState(valence: 0, arousal: 0.6) // arousalDiff = 0.6 > 0.4

        // Zero-confidence boundary so the boundary path is completely bypassed.
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0,
            elapsedTrackTime: 75,             // 75/120 = 62.5 % > 40 %
            liveBoundary: noBoundarySignal(),
            liveMood: liveMood,
            catalog: simpleCatalog()
        )

        #expect(result.presetOverride == nil, "Override must be suppressed after 40 % elapsed")
        #expect(result.events.contains { $0.kind == .moodDivergenceDetected },
                "Mood divergence must still be logged even when override is suppressed")
    }

    // MARK: 5 — No override when score gap is insufficient

    @Test("No override when current preset is already well-matched to live mood")
    func noPresetOverride_whenScoreGapInsufficient() throws {
        // CurrentPreset: center=0.5 temp, density=0.70 — perfect for live (arousal=0.5).
        // AltPreset: center=0.1 temp, density=0.1 — poorly matched.
        //
        // Scoring with live (valence=0, arousal=0.5): targetTemp=0.5, targetDensity=0.70
        //   CurrentPreset: moodScore=1.0 → currentScore ≈ 0.875
        //   AltPreset:     moodScore=0.5 → altScore ≈ 0.725
        //   gap = 0.725 - 0.875 = -0.15 → no override (gap < 0.15)
        let catalog = [
            makePreset(name: "CurrentPreset", family: .fluid,
                       motionIntensity: 0.5, colorTempRange: SIMD2(0.45, 0.55),
                       visualDensity: 0.70),
            makePreset(name: "AltPreset", family: .geometric,
                       motionIntensity: 0.5, colorTempRange: SIMD2(0.0, 0.2),
                       visualDensity: 0.1),
        ]

        // Pre-analyzed neutral → planner picks CurrentPreset (moodScore 0.9 vs 0.6).
        let plan = try planWithCatalog(catalog, mood: EmotionalState(valence: 0, arousal: 0),
                                       duration: 120)
        let liveMood = EmotionalState(valence: 0, arousal: 0.5) // arousalDiff = 0.5 > 0.4 ✓

        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0,
            elapsedTrackTime: 20,          // 20/120 = 16.7 % < 40 % ✓
            liveBoundary: noBoundarySignal(),
            liveMood: liveMood,
            catalog: catalog
        )

        #expect(result.presetOverride == nil, "No override when gap is insufficient")
        #expect(result.events.contains { $0.kind == .moodDivergenceDetected },
                "Diverging mood must still emit moodDivergenceDetected")
    }

    // MARK: 6 — Override triggered

    @Test("Preset override fires: early track, strong divergence, better alternative exists")
    func presetOverride_whenMoodDivergesEarlyAndBetterPresetExists() throws {
        // CurrentPreset: center=0.25 temp, density=0.25 — tuned for sad/calm pre-analyzed mood.
        // AltPreset:     center=0.78 temp, density=0.78 — tuned for happy/energetic live mood.
        //
        // Pre-analyzed (valence=-0.5, arousal=-0.5): targetTemp=0.30, targetDensity=0.30
        //   CurrentPreset moodScore = (1-|0.25-0.30| + 1-|0.25-0.30|)/2 = 0.95 → selected ✓
        //   AltPreset     moodScore = (1-|0.78-0.30| + 1-|0.78-0.30|)/2 = 0.52
        //
        // Live (valence=0.7, arousal=0.7): targetTemp=0.78, targetDensity=0.78
        //   currentScore = 0.3×0.47 + 0.2×1.0 + 0.25×0.5 + 0.25×1.0 = 0.716
        //   altScore     = 0.3×1.00 + 0.2×1.0 + 0.25×0.5 + 0.25×1.0 = 0.875
        //   gap = 0.159 > 0.15 ✓
        let catalog = overrideCatalog()
        let plan = try planWithCatalog(catalog,
                                       mood: EmotionalState(valence: -0.5, arousal: -0.5),
                                       duration: 120)

        let liveMood = EmotionalState(valence: 0.7, arousal: 0.7)
        // valenceDiff = 1.2 > 0.4, arousalDiff = 1.2 > 0.4
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0,
            elapsedTrackTime: 30,      // 30/120 = 25 % < 40 % ✓
            liveBoundary: noBoundarySignal(),
            liveMood: liveMood,
            catalog: catalog
        )

        let override = try #require(result.presetOverride, "Override must fire")
        #expect(override.preset.name == "AltPreset", "Better preset must be selected")
        #expect(override.score > plan.tracks[0].presetScore,
                "Override preset score must exceed original")
        #expect(result.updatedTransition == nil)
        #expect(result.events.contains { $0.kind == .presetOverrideTriggered })
    }

    // MARK: 7 — Boundary reschedule takes priority over override

    @Test("Boundary reschedule returned, not override, when both conditions are true")
    func boundaryReschedulePrecedesOverride_whenBothTrigger() throws {
        // Same mood setup as test 6 — override would fire without boundary condition.
        let catalog = overrideCatalog()
        let plan = try planWithCatalog(catalog,
                                       mood: EmotionalState(valence: -0.5, arousal: -0.5),
                                       duration: 120)

        // plannedTransition.scheduledAt ≈ 120 s; live boundary at 150 s → deviation 30 s > 5 s.
        let bigDeviation = StructuralPrediction(
            sectionIndex: 0, sectionStartTime: 0,
            predictedNextBoundary: 150.0,
            confidence: 0.9
        )

        let liveMood = EmotionalState(valence: 0.7, arousal: 0.7) // would also trigger override

        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0,
            elapsedTrackTime: 30,
            liveBoundary: bigDeviation,
            liveMood: liveMood,
            catalog: catalog
        )

        #expect(result.updatedTransition != nil, "Boundary reschedule must fire")
        #expect(result.presetOverride == nil,
                "Override must be suppressed when boundary reschedule wins")
        #expect(result.events.contains { $0.kind == .boundaryRescheduled })
        #expect(!result.events.contains { $0.kind == .presetOverrideTriggered },
                "presetOverrideTriggered must not appear alongside boundaryRescheduled")
    }

    // MARK: 8 — All event kinds are emitted for the correct scenarios

    @Test("Each adaptation path emits the correct AdaptationEvent.Kind")
    func adaptationEvents_areLogged_forAllOutcomes() throws {
        let catalog = overrideCatalog()
        let planOverride = try planWithCatalog(catalog,
                                               mood: EmotionalState(valence: -0.5, arousal: -0.5),
                                               duration: 120)
        let planNeutral = try twoTrackPlan(duration: 60)

        // ── noAdaptation: stable mood, zero-confidence boundary ───────────────
        let noAdaptResult = adapter.adapt(
            plan: planNeutral, currentTrackIndex: 0, elapsedTrackTime: 20,
            liveBoundary: noBoundarySignal(),
            liveMood: .neutral,
            catalog: simpleCatalog()
        )
        #expect(noAdaptResult.events.first?.kind == .noAdaptation)

        // ── boundaryRescheduled: 60 s track, planned at 60 s, live at 70 s ────
        let bigBoundary = StructuralPrediction(
            sectionIndex: 0, sectionStartTime: 0,
            predictedNextBoundary: 70.0, confidence: 0.7
        )
        let rescheduleResult = adapter.adapt(
            plan: planNeutral, currentTrackIndex: 0, elapsedTrackTime: 20,
            liveBoundary: bigBoundary, liveMood: .neutral, catalog: simpleCatalog()
        )
        #expect(rescheduleResult.events.first?.kind == .boundaryRescheduled)

        // ── moodDivergenceDetected (late in track) ────────────────────────────
        let moodDivergeLate = adapter.adapt(
            plan: planOverride, currentTrackIndex: 0,
            elapsedTrackTime: 80,          // 80/120 = 67 % > 40 %
            liveBoundary: noBoundarySignal(),
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            catalog: catalog
        )
        #expect(moodDivergeLate.events.first?.kind == .moodDivergenceDetected)

        // ── presetOverrideTriggered ───────────────────────────────────────────
        let overrideResult = adapter.adapt(
            plan: planOverride, currentTrackIndex: 0,
            elapsedTrackTime: 20,          // 20/120 = 17 % < 40 %
            liveBoundary: noBoundarySignal(),
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            catalog: catalog
        )
        #expect(overrideResult.events.first?.kind == .presetOverrideTriggered)
    }
}

// MARK: - Session Builders

private func twoTrackPlan(
    duration: TimeInterval,
    mood: EmotionalState = .neutral
) throws -> PlannedSession {
    let tracks: [(TrackIdentity, TrackProfile)] = [
        (makeIdentity(title: "T0", duration: duration), makeProfile(valence: mood.valence, arousal: mood.arousal)),
        (makeIdentity(title: "T1", duration: duration), makeProfile()),
    ]
    // swiftlint:disable:next force_try
    return try! DefaultSessionPlanner().plan(tracks: tracks, catalog: simpleCatalog(), deviceTier: .tier1)
}

private func planWithCatalog(
    _ catalog: [PresetDescriptor],
    mood: EmotionalState,
    duration: TimeInterval
) throws -> PlannedSession {
    let tracks: [(TrackIdentity, TrackProfile)] = [
        (makeIdentity(title: "T0", duration: duration),
         makeProfile(valence: mood.valence, arousal: mood.arousal)),
        (makeIdentity(title: "T1", duration: duration), makeProfile()),
    ]
    // swiftlint:disable:next force_try
    return try! DefaultSessionPlanner().plan(tracks: tracks, catalog: catalog, deviceTier: .tier1)
}

/// A structural prediction with zero confidence — the boundary path is never triggered.
///
/// Use in tests that exercise the mood-override path exclusively.
private func noBoundarySignal() -> StructuralPrediction {
    StructuralPrediction(sectionIndex: 0, sectionStartTime: 0,
                         predictedNextBoundary: 0, confidence: 0.0)
}

// MARK: - Catalog Builders

private func simpleCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "SimpleA", family: .fluid),
        makePreset(name: "SimpleB", family: .geometric),
    ]
}

/// Catalog used for override tests (tests 6, 7, 8).
///
/// CurrentPreset is cold/low-density (suits pre-analyzed sad/calm mood).
/// AltPreset is warm/high-density (suits live happy/energetic mood).
///
/// Scoring with live (valence=0.7, arousal=0.7) — targetTemp=0.78, targetDensity=0.78:
///   CurrentPreset: moodScore=0.47 → currentScore=0.716
///   AltPreset:     moodScore=1.00 → altScore=0.875
///   gap = 0.159 > 0.15 ✓
private func overrideCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "CurrentPreset", family: .fluid,
                   motionIntensity: 0.5,
                   colorTempRange: SIMD2(0.2, 0.3),   // center = 0.25
                   visualDensity: 0.25),
        makePreset(name: "AltPreset", family: .geometric,
                   motionIntensity: 0.5,
                   colorTempRange: SIMD2(0.73, 0.83),  // center = 0.78
                   visualDensity: 0.78),
    ]
}

// MARK: - Fixture Builders

private func makeIdentity(
    title: String = "TestTrack",
    duration: TimeInterval = 180
) -> TrackIdentity {
    TrackIdentity(title: title, artist: "TestArtist", duration: duration)
}

private func makeProfile(
    valence: Float = 0,
    arousal: Float = 0
) -> TrackProfile {
    TrackProfile(mood: EmotionalState(valence: valence, arousal: arousal))
}

private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .abstract,
    motionIntensity: Float = 0.5,
    colorTempRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    visualDensity: Float = 0.5,
    complexityCost: ComplexityCost = ComplexityCost(tier1: 2.0, tier2: 1.5),
    transitionAffordances: [TransitionAffordance] = [.crossfade]
) -> PresetDescriptor {
    let affordJSON = transitionAffordances.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTempRange.x), \(colorTempRange.y)],
        "visual_density": \(visualDensity),
        "complexity_cost": {"tier1": \(complexityCost.tier1), "tier2": \(complexityCost.tier2)},
        "transition_affordances": [\(affordJSON)],
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}
