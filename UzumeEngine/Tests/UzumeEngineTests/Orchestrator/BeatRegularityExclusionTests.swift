// BeatRegularityExclusionTests — FBS / D-154: beat-irregular tracks never see
// beat-locked presets (Matt's 2026-06-10 rule; Pyramid Song is the canonical case).
//
// Two surfaces under test:
//   1. `assessBeatIrregularity` — calibrated against the REAL cached grids of
//      the 2026-06-10T03-02-32Z session catalog (values read from the
//      persistent stem cache, not invented).
//   2. `DefaultPresetScorer`'s `beat_irregular` hard exclusion — a preset
//      declaring `requires_regular_beat` scores 0 on an irregular track, in
//      both planned and reactive shapes.

import XCTest
@testable import Orchestrator
@testable import Presets
@testable import Session
@testable import Shared

final class BeatRegularityExclusionTests: XCTestCase {

    // MARK: - assessBeatIrregularity (real catalog values)

    func test_assess_realCatalogValues() {
        // (gridBPM, drumsBPM, gridBarConfidence, expected, label)
        // Values from the persistent stem cache backing session 2026-06-10T03-02-32Z.
        let cases: [(Double, Double, Float, Bool?, String)] = [
            (70.0, 164.3, 0.50, true, "Pyramid Song — rubato; folded disagreement 17.4%"),
            (118.1, 119.0, 1.00, false, "Love Rehab — the track the pulse locked on"),
            (126.3, 125.8, 1.00, false, "There, There"),
            (123.2, 124.0, 0.50, false, "Money"),
            (135.5, 135.5, 1.00, false, "So What — KNOWN MISS: swing feel is invisible to these estimators"),
            (171.3, 156.8, 1.00, false, "Cherub Rock — 9.2% folded, just under the 10% gate"),
            (85.9, 77.2, 0.30, true, "SZ2 — polyrhythmic math-rock; 11.3% folded"),
            (133.1, 89.4, 0.77, true, "Mingus Better Git It — 49% folded (jazz tempo flux)"),
            (119.8, 60.7, 1.00, false, "half-time drums grid — octave fold keeps it regular (2.6%)"),
            (90.2, 0, 0.60, nil, "drums grid missing — unknown, permissive"),
            (0, 120.0, 0.50, nil, "full-mix grid missing — unknown, permissive"),
        ]
        for (grid, drums, conf, expected, label) in cases {
            let got = assessBeatIrregularity(gridBPM: grid, drumsBPM: drums, barConfidence: conf)
            XCTAssertEqual(got, expected, label)
        }
    }

    func test_assess_lowBarConfidence_isIrregular_evenWhenTemposAgree() {
        XCTAssertEqual(assessBeatIrregularity(gridBPM: 120, drumsBPM: 120.5, barConfidence: 0.1),
                       true, "bar confidence below the floor flags irregularity on its own")
    }

    // MARK: - Scorer hard exclusion

    private func makePreset(name: String, requiresRegularBeat: Bool) -> PresetDescriptor {
        let json = """
        {
            "name": "\(name)",
            "family": "reaction",
            "motion_intensity": 0.5,
            "color_temperature_range": [0.3, 0.7],
            "fatigue_risk": "medium",
            "section_suitability": ["peak"],
            "stem_affinity": {},
            "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
            "transition_affordances": ["crossfade"],
            "certified": true,
            "requires_regular_beat": \(requiresRegularBeat)
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    private func track(beatIrregular: Bool?) -> TrackProfile {
        var profile = TrackProfile.empty
        profile.beatIrregular = beatIrregular
        return profile
    }

    private let scorer = DefaultPresetScorer()
    private let ctx = PresetScoringContext(deviceTier: .tier2)

    func test_requiringPreset_excludedOnIrregularTrack() {
        let bd = scorer.breakdown(preset: makePreset(name: "FFO-like", requiresRegularBeat: true),
                                  track: track(beatIrregular: true), context: ctx)
        XCTAssertTrue(bd.excluded, "beat-locked preset must be hard-excluded on an irregular track")
        XCTAssertEqual(bd.excludedReason, "beat_irregular")
        XCTAssertEqual(bd.total, 0)
    }

    func test_requiringPreset_eligibleOnRegularTrack_andOnUnknown() {
        for irregular in [false, nil] as [Bool?] {
            let bd = scorer.breakdown(preset: makePreset(name: "FFO-like", requiresRegularBeat: true),
                                      track: track(beatIrregular: irregular), context: ctx)
            XCTAssertFalse(bd.excluded,
                           "regular (\(String(describing: irregular))) must not exclude — "
                           + "exclusion requires evidence")
        }
    }

    func test_nonRequiringPreset_unaffectedByIrregularTrack() {
        let bd = scorer.breakdown(preset: makePreset(name: "Other", requiresRegularBeat: false),
                                  track: track(beatIrregular: true), context: ctx)
        XCTAssertFalse(bd.excluded, "presets without the flag are unaffected")
    }

    // MARK: - Reactive path carries the flag

    func test_reactive_irregularTrack_excludesRequiringPresetFromSelection() {
        let orchestrator = DefaultReactiveOrchestrator()
        let requiring = makePreset(name: "FFO-like", requiresRegularBeat: true)
        let neutral = makePreset(name: "Other", requiresRegularBeat: false)
        // Past the listening window; no current preset → it must pick one.
        let decision = orchestrator.evaluate(
            liveMood: .neutral,
            liveBoundary: .none,
            elapsedSessionTime: 60,
            currentPreset: nil,
            catalog: [requiring, neutral],
            deviceTier: .tier2,
            includeUncertifiedPresets: false,
            liveStemFeatures: nil,
            currentTrackBeatIrregular: true
        )
        XCTAssertEqual(decision.suggestedPreset?.name, "Other",
                       "reactive mode must never pick a beat-locked preset on an irregular track")
    }

    // MARK: - Planner path: a full planned session never schedules FFO on an
    // irregular track (Matt's verification ask, 2026-06-10 — the live session
    // only exercised manual selection, which bypasses the gate by design)

    func test_plannedSession_neverSchedulesRequiringPreset_onIrregularTrack() throws {
        let planner = DefaultSessionPlanner()
        let requiring = makePreset(name: "FFO-like", requiresRegularBeat: true)
        let others = [makePreset(name: "A", requiresRegularBeat: false),
                      makePreset(name: "B", requiresRegularBeat: false)]
        // Pyramid-Song-shaped track: irregular flag set (as _buildPlan now does
        // from the cached grids), full duration so multiple segments get planned.
        var profile = TrackProfile.empty
        profile.beatIrregular = true
        let identity = TrackIdentity(title: "Pyramid Song", artist: "Radiohead", duration: 288.7)
        let session = try planner.plan(tracks: [(identity, profile)],
                                       catalog: [requiring] + others, deviceTier: .tier1)
        let scheduled = session.tracks.flatMap(\.segments).map(\.preset.name)
        XCTAssertFalse(scheduled.isEmpty, "planner must schedule something")
        XCTAssertFalse(scheduled.contains("FFO-like"),
                       "an irregular track must NEVER be scheduled onto a "
                       + "requires_regular_beat preset; got \(scheduled)")
    }

    func test_plannedSession_allowsRequiringPreset_onRegularTrack() throws {
        let planner = DefaultSessionPlanner()
        // Only the requiring preset in the catalog: on a REGULAR track it must
        // be schedulable (proves the exclusion doesn't over-fire).
        let requiring = makePreset(name: "FFO-like", requiresRegularBeat: true)
        var profile = TrackProfile.empty
        profile.beatIrregular = false
        let identity = TrackIdentity(title: "Love Rehab", artist: "Chaim", duration: 460.7)
        let session = try planner.plan(tracks: [(identity, profile)],
                                       catalog: [requiring], deviceTier: .tier1)
        let scheduled = session.tracks.flatMap(\.segments).map(\.preset.name)
        XCTAssertTrue(scheduled.contains("FFO-like"),
                      "a regular track must still be able to schedule the requiring preset")
    }

    func test_realFFOSidecar_doesNotDeclareRequiresRegularBeat() throws {
        // D-154 AMENDED 2026-06-11: the FFO ban is RETIRED (Matt's pick after
        // watching FFO on Pyramid Song, the gate's canonical catch: "it looks
        // and moves great"). The session data showed the live drift tracker
        // LOCKED on Pyramid at te 5.4 s — the grid-vs-drums disagreement that
        // flagged it condemned the estimate FFO doesn't use. The MECHANISM
        // (descriptor flag + scorer/planner/reactive exclusion + the recorded
        // beatIrregular signal) stays, tested via the synthetic preset above,
        // for any future preset that genuinely needs it. Re-adding the flag to
        // FFO requires a new product decision — this gate enforces that.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // → Orchestrator/
            .deletingLastPathComponent()    // → PhospheneEngineTests/
            .deletingLastPathComponent()    // → Tests/
            .deletingLastPathComponent()    // → PhospheneEngine/
            .appendingPathComponent("Sources/Presets/Shaders/FerrofluidOcean.json")
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self,
                                                  from: Data(contentsOf: url))
        XCTAssertFalse(descriptor.requiresRegularBeat,
                       "the FFO beat-regularity ban is retired (D-154 amendment, 2026-06-11)")
    }
}
