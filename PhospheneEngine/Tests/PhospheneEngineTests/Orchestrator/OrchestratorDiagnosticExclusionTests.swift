// OrchestratorDiagnosticExclusionTests — V.7.6.D diagnostic auto-selection gate.
//
// Tests:
//   1. Scorer: diagnostic preset is excluded with excludedReason == "diagnostic".
//   2. Scorer: gate fires even when includeUncertifiedPresets == true (no toggle re-enables).
//   3. Scorer: gate fires before family boost — boost cannot resurrect a diagnostic.
//   4. LiveAdapter: mood-override never targets a diagnostic preset.
//   5. SessionPlanner: diagnostics never appear in plan.tracks[].preset.
//   6. ReactiveOrchestrator: diagnostics never appear in suggestedPreset.
//   7. PresetDescriptor remains constructible with isDiagnostic == true (manual-switch path).

import Testing
import Foundation
@testable import Orchestrator
@testable import Presets
@testable import Shared
import Session
import simd

// MARK: - Fixture Helpers

private func makePreset(
    name: String,
    family: PresetCategory = .geometric,
    isDiagnostic: Bool = false,
    certified: Bool = true,
    motionIntensity: Float = 0.5,
    colorTempRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    visualDensity: Float = 0.5
) -> PresetDescriptor {
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": \(motionIntensity),
        "visual_density": \(visualDensity),
        "color_temperature_range": [\(colorTempRange.x), \(colorTempRange.y)],
        "complexity_cost": { "tier1": 1.0, "tier2": 1.0 },
        "transition_affordances": ["crossfade"],
        "certified": \(certified ? "true" : "false"),
        "is_diagnostic": \(isDiagnostic ? "true" : "false")
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func makeProfile(
    bpm: Float? = 120,
    valence: Float = 0,
    arousal: Float = 0
) -> TrackProfile {
    TrackProfile(
        bpm: bpm,
        mood: EmotionalState(valence: valence, arousal: arousal)
    )
}

private func makeIdentity(title: String = "T", duration: TimeInterval = 180) -> TrackIdentity {
    TrackIdentity(title: title, artist: "A", duration: duration)
}

// MARK: - Suite

@Suite("Orchestrator Diagnostic Exclusion")
struct OrchestratorDiagnosticExclusionTests {

    let scorer = DefaultPresetScorer()

    // MARK: 1 — Scorer excludes diagnostic preset

    @Test("Diagnostic preset excluded with excludedReason 'diagnostic'")
    func scorer_diagnosticExcluded() {
        let preset = makePreset(name: "Diag", isDiagnostic: true)
        let context = PresetScoringContext(deviceTier: .tier2)
        let bd = scorer.breakdown(preset: preset, track: makeProfile(), context: context)

        #expect(bd.excluded == true)
        #expect(bd.excludedReason == "diagnostic")
        #expect(bd.total == 0)
    }

    // MARK: 2 — Gate fires even with uncertified toggle on

    @Test("Diagnostic excluded even when includeUncertifiedPresets == true")
    func scorer_diagnosticExcluded_uncertifiedToggleOn() {
        let preset = makePreset(name: "Diag", isDiagnostic: true, certified: false)
        let context = PresetScoringContext(
            deviceTier: .tier2,
            includeUncertifiedPresets: true
        )
        let bd = scorer.breakdown(preset: preset, track: makeProfile(), context: context)

        #expect(bd.excluded == true)
        #expect(bd.excludedReason == "diagnostic",
                "Diagnostic gate must fire before uncertified gate")
        #expect(bd.total == 0)
    }

    // MARK: 3 — Family boost cannot resurrect a diagnostic

    @Test("Family boost on a diagnostic still yields excluded == true and total 0")
    func scorer_diagnosticBeatsFamilyBoost() {
        let preset = makePreset(name: "Diag", family: .waveform, isDiagnostic: true)
        let context = PresetScoringContext(
            deviceTier: .tier2,
            familyBoosts: [PresetCategory.waveform: 1.0]
        )
        let bd = scorer.breakdown(preset: preset, track: makeProfile(), context: context)

        #expect(bd.excluded == true)
        #expect(bd.total == 0)
    }

    // MARK: 4 — LiveAdapter never overrides into a diagnostic

    @Test("LiveAdapter mood-override never targets a diagnostic preset")
    func liveAdapter_neverOverridesIntoDiagnostic() throws {
        // Catalog: a "current" cool preset, a diagnostic that would otherwise be the
        // perfect mood match for the live state, plus a non-diagnostic alternative.
        let current = makePreset(name: "Cool", family: .reaction,
                                 colorTempRange: SIMD2(0.20, 0.30), visualDensity: 0.25)
        let diag = makePreset(name: "DiagWarm", family: .waveform,
                              isDiagnostic: true,
                              colorTempRange: SIMD2(0.73, 0.83), visualDensity: 0.78)
        let alt = makePreset(name: "AltCool", family: .geometric,
                             colorTempRange: SIMD2(0.20, 0.30), visualDensity: 0.25)
        let catalog = [current, diag, alt]

        // Plan against pre-analyzed sad/calm so the planner picks `current`.
        let tracks: [(TrackIdentity, TrackProfile)] = [
            (makeIdentity(title: "T0", duration: 120),
             makeProfile(valence: -0.5, arousal: -0.5)),
            (makeIdentity(title: "T1", duration: 120), makeProfile()),
        ]
        let plan = try DefaultSessionPlanner().plan(
            tracks: tracks,
            catalog: catalog,
            deviceTier: .tier2
        )

        let liveMood = EmotionalState(valence: 0.7, arousal: 0.7)
        let result = DefaultLiveAdapter().adapt(
            plan: plan,
            currentTrackIndex: 0,
            elapsedTrackTime: 20,
            liveBoundary: StructuralPrediction(
                sectionIndex: 0, sectionStartTime: 0,
                predictedNextBoundary: 0, confidence: 0
            ),
            liveMood: liveMood,
            catalog: catalog
        )

        if let override = result.presetOverride {
            #expect(override.preset.isDiagnostic == false,
                    "Override target must never be a diagnostic preset")
        }
        // Nothing in the planned plan should be a diagnostic either.
        for plannedTrack in plan.tracks {
            #expect(plannedTrack.preset.isDiagnostic == false)
        }
    }

    // MARK: 5 — SessionPlanner excludes diagnostic from all tracks

    @Test("SessionPlanner never selects a diagnostic preset for any track")
    func sessionPlanner_excludesDiagnosticFromAllTracks() throws {
        let diag = makePreset(name: "Diag", family: .waveform, isDiagnostic: true)
        let goodA = makePreset(name: "GoodA", family: .reaction)
        let goodB = makePreset(name: "GoodB", family: .geometric)
        let catalog = [diag, goodA, goodB]

        let tracks: [(TrackIdentity, TrackProfile)] = (0..<5).map { i in
            (makeIdentity(title: "T\(i)", duration: 60),
             makeProfile(valence: Float(i) * 0.2 - 0.5, arousal: Float(i) * 0.2 - 0.5))
        }

        let plan = try DefaultSessionPlanner().plan(
            tracks: tracks,
            catalog: catalog,
            deviceTier: .tier2
        )

        for plannedTrack in plan.tracks {
            #expect(plannedTrack.preset.isDiagnostic == false,
                    "Track \(plannedTrack.track.title) selected diagnostic preset")
            #expect(plannedTrack.preset.id != diag.id)
        }
    }

    // MARK: 6 — ReactiveOrchestrator never suggests a diagnostic

    @Test("ReactiveOrchestrator never suggests a diagnostic preset")
    func reactiveOrchestrator_neverSelectsDiagnostic() {
        // Catalog with a "would otherwise win" diagnostic plus two fallback options.
        let diag = makePreset(name: "DiagPerfect", family: .waveform,
                              isDiagnostic: true,
                              colorTempRange: SIMD2(0.73, 0.83), visualDensity: 0.78)
        let altA = makePreset(name: "AltA", family: .reaction,
                              colorTempRange: SIMD2(0.20, 0.30), visualDensity: 0.25)
        let altB = makePreset(name: "AltB", family: .geometric,
                              colorTempRange: SIMD2(0.40, 0.50), visualDensity: 0.50)
        let catalog = [diag, altA, altB]

        let liveMood = EmotionalState(valence: 0.7, arousal: 0.7)
        let boundary = StructuralPrediction(
            sectionIndex: 0, sectionStartTime: 0,
            predictedNextBoundary: 10, confidence: 0.8
        )

        // Past the listening window, currentPreset == nil → orchestrator wants to suggest
        // *something*. It must not be the diagnostic.
        let decision = DefaultReactiveOrchestrator().evaluate(
            liveMood: liveMood,
            liveBoundary: boundary,
            elapsedSessionTime: 35,
            currentPreset: nil,
            catalog: catalog,
            deviceTier: .tier2,
            includeUncertifiedPresets: false
        )

        if let suggested = decision.suggestedPreset {
            #expect(suggested.isDiagnostic == false,
                    "Reactive orchestrator must never suggest a diagnostic preset")
        }
    }

    // MARK: 7 — Manual-switch path: PresetDescriptor remains constructible

    @Test("Diagnostic flag is data-only — descriptor still constructs cleanly")
    func manualSwitch_acceptsDiagnosticDescriptor() {
        // The exclusion is a Scorer-level gate, not a data-model constraint.
        // Manual switch surfaces (keyboard/dev) bypass scoring and operate on
        // PresetDescriptor directly — assert the descriptor still constructs.
        let preset = makePreset(name: "DiagManual", isDiagnostic: true)
        #expect(preset.isDiagnostic == true)
        #expect(preset.id == "DiagManual")
    }
}
