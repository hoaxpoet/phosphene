// ReactiveOrchestratorTests — unit tests for DefaultReactiveOrchestrator (Increment 4.6).
//
// Scoring math verified inline in comments. Key threshold: gap > 0.20 for reactive switch.
//
// Scoring formula (no BPM, no stems, no section, no history in these tests):
//   raw = 0.30*moodScore + 0.20*tempoMotion(0.5→1.0 for nil BPM) + 0.25*stemAffinity(0.5) + 0.25*section(1.0)
//       = 0.30*moodScore + 0.575
//
//   targetTemp    = 0.5 + 0.4 * valence
//   targetDensity = 0.5 + 0.4 * arousal
//   moodScore     = (1-|center-targetTemp| + 1-|density-targetDensity|) / 2

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

// MARK: - Test Suite

@Suite("DefaultReactiveOrchestrator")
struct ReactiveOrchestratorTests {

    private let orchestrator = DefaultReactiveOrchestrator()

    // MARK: 1 — Listening state always holds

    @Test("Returns hold with nil suggestion during 0–15 s listening window")
    func listening_state_always_holds() {
        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: strongBoundary(),
            elapsedSessionTime: 10.0,
            currentPreset: nil,
            catalog: smallGapCatalog(),
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil, "Must hold during listening window")
        #expect(decision.accumulationState == .listening)
        #expect(decision.scheduleTransitionAt == nil)
    }

    // MARK: 2 — Confidence ramps correctly

    @Test("Confidence ramps from 0 at 0 s to 1.0 at 30 s")
    func confidence_ramps_correctly() {
        let eps: Float = 0.001

        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 0) - 0.0) < eps,
                "0 s → 0.0")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 7.5) - 0.15) < eps,
                "7.5 s → 0.15")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 15.0) - 0.30) < eps,
                "15 s → 0.30")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 22.5) - 0.65) < eps,
                "22.5 s → 0.65")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 30.0) - 1.0) < eps,
                "30 s → 1.0")
    }

    // MARK: 3 — Ramping state suggests best preset for live mood

    @Test("Suggests better-matching preset during ramping state when score gap > 0.20")
    func ramping_suggests_best_preset_for_live_mood() throws {
        // Live happy/energetic: valence=0.7, arousal=0.7
        //   targetTemp = 0.5 + 0.4*0.7 = 0.78
        //   targetDensity = 0.78
        //
        // CurrentPreset: center=0.10, density=0.10
        //   moodScore = (1-|0.10-0.78| + 1-|0.10-0.78|)/2 = 0.32
        //   total = 0.30*0.32 + 0.575 = 0.671
        //
        // AltPreset: center=0.78, density=0.78
        //   moodScore = 1.0, total = 0.875
        //
        // gap = 0.875 - 0.671 = 0.204 > 0.20 ✓
        let catalog = largeGapCatalog()
        let currentDesc = catalog[0]  // CurrentPreset

        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: noBoundarySignal(),
            elapsedSessionTime: 20.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        let suggested = try #require(decision.suggestedPreset, "Gap > 0.20 must trigger switch")
        #expect(suggested.name == "AltPreset", "Better preset must be selected")
        #expect(decision.accumulationState == .ramping)
    }

    // MARK: 4 — No switch when score gap is too small

    @Test("Holds current preset when gap is 0.03 (< 0.20) and no boundary signal")
    func no_switch_when_score_gap_too_small() {
        // Live (valence=0.7, arousal=0.7): targetTemp=0.78, targetDensity=0.78
        //
        // CurrentPreset: center=0.68, density=0.68
        //   moodScore = (0.90 + 0.90)/2 = 0.90
        //   total = 0.30*0.90 + 0.575 = 0.845
        //
        // AltPreset: center=0.78, density=0.78 → total=0.875
        //
        // gap = 0.875 - 0.845 = 0.030 < 0.20 ✓  boundary confidence = 0.0 < 0.5 ✓
        let catalog = smallGapCatalog()
        let currentDesc = catalog[0]  // CurrentPreset

        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: noBoundarySignal(),
            elapsedSessionTime: 60.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil, "Gap < 0.20 and no boundary — must hold")
        #expect(decision.accumulationState == .full)
    }

    // MARK: 5 — Boundary triggers switch even without score gap

    @Test("Suggests switch when boundary fires even though gap is only 0.03")
    func boundary_triggers_switch_even_without_score_gap() {
        // Same catalog as test 4: gap = 0.030 < 0.20 (score gate fails).
        // liveBoundary.confidence = 0.8 ≥ 0.5 → boundary gate passes → switch.
        let catalog = smallGapCatalog()
        let currentDesc = catalog[0]  // CurrentPreset

        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: strongBoundary(predictedNextBoundary: 10.0),
            elapsedSessionTime: 60.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset != nil, "Boundary must trigger switch despite small gap")
        #expect(decision.suggestedPreset?.name == "AltPreset")
    }

    // MARK: 6 — Boundary schedules transition at correct session time

    @Test("scheduleTransitionAt equals elapsedSessionTime + predictedNextBoundary")
    func boundary_schedules_transition_at_correct_time() {
        // elapsedSessionTime = 45.0, predictedNextBoundary = 3.5, confidence = 0.8 ≥ 0.5
        // scheduleTransitionAt = 3.5 + 45.0 = 48.5
        let catalog = smallGapCatalog()
        let currentDesc = catalog[0]

        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: strongBoundary(predictedNextBoundary: 3.5),
            elapsedSessionTime: 45.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset != nil, "Boundary must trigger a switch")
        #expect(decision.scheduleTransitionAt != nil)
        #expect(abs(Float(decision.scheduleTransitionAt!) - 48.5) < 0.1,
                "scheduleTransitionAt must equal elapsedSessionTime + predictedNextBoundary")
    }

    // MARK: 7 — nil current preset always suggests past listening

    @Test("Suggests top preset when currentPreset is nil and past listening window")
    func nil_current_preset_always_suggests_past_listening() {
        // No current preset → skip score comparison entirely; always suggest top-ranked.
        // Score gap gate does not apply — there is nothing to compare against.
        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: noBoundarySignal(),
            elapsedSessionTime: 20.0,
            currentPreset: nil,
            catalog: smallGapCatalog(),
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset != nil,
                "Must suggest a preset when no current preset is set")
        #expect(decision.accumulationState == .ramping)
    }

    // MARK: 8 — Empty catalog returns hold

    @Test("Returns hold with nil suggestion when catalog is empty")
    func empty_catalog_returns_hold() {
        let decision = orchestrator.evaluate(
            liveMood: EmotionalState(valence: 0.7, arousal: 0.7),
            liveBoundary: strongBoundary(),
            elapsedSessionTime: 60.0,
            currentPreset: nil,
            catalog: [],
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil, "Empty catalog must return hold")
        #expect(decision.scheduleTransitionAt == nil)
    }
}

// MARK: - Signal Helpers

/// Structural prediction with zero confidence — boundary gate never fires.
private func noBoundarySignal() -> StructuralPrediction {
    StructuralPrediction(
        sectionIndex: 0, sectionStartTime: 0,
        predictedNextBoundary: 0, confidence: 0.0
    )
}

/// Structural prediction with confidence 0.8 (≥ 0.5 threshold).
private func strongBoundary(predictedNextBoundary: Float = 10.0) -> StructuralPrediction {
    StructuralPrediction(
        sectionIndex: 0, sectionStartTime: 0,
        predictedNextBoundary: predictedNextBoundary, confidence: 0.8
    )
}

// MARK: - Catalog Builders

/// Large-gap catalog (test 3).
///
/// With live (valence=0.7, arousal=0.7): targetTemp=0.78, targetDensity=0.78
///   CurrentPreset: center=0.10, density=0.10  → total=0.671
///   AltPreset:     center=0.78, density=0.78  → total=0.875
///   gap = 0.204 > 0.20 ✓
private func largeGapCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "CurrentPreset", family: .fluid,
                   colorTempRange: SIMD2(0.05, 0.15),   // center = 0.10
                   visualDensity: 0.10),
        makePreset(name: "AltPreset", family: .geometric,
                   colorTempRange: SIMD2(0.73, 0.83),   // center = 0.78
                   visualDensity: 0.78),
    ]
}

/// Small-gap catalog (tests 4, 5, 6, 7).
///
/// With live (valence=0.7, arousal=0.7): targetTemp=0.78, targetDensity=0.78
///   CurrentPreset: center=0.68, density=0.68  → total=0.845
///   AltPreset:     center=0.78, density=0.78  → total=0.875
///   gap = 0.030 < 0.20 — score gate fails; boundary gate still works.
private func smallGapCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "CurrentPreset", family: .fluid,
                   colorTempRange: SIMD2(0.63, 0.73),   // center = 0.68
                   visualDensity: 0.68),
        makePreset(name: "AltPreset", family: .geometric,
                   colorTempRange: SIMD2(0.73, 0.83),   // center = 0.78
                   visualDensity: 0.78),
    ]
}

// MARK: - Fixture Builder

private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .abstract,
    motionIntensity: Float = 0.5,
    colorTempRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    visualDensity: Float = 0.5
) -> PresetDescriptor {
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTempRange.x), \(colorTempRange.y)],
        "visual_density": \(visualDensity),
        "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
        "transition_affordances": ["crossfade"]
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}
