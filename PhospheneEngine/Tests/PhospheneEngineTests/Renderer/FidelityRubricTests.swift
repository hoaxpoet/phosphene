// FidelityRubricTests — V.6 rubric analyzer gate.
//
// Three suites:
//   1. Per-preset rubric report — loads all production presets from PresetCertificationStore,
//      prints structured breakdown. No content assertions; confirms loading works.
//   2. Automated gate assertions — locks in meetsAutomatedGate values from first run.
//      Regressions in rubric logic or shader source flip these and are caught here.
//   3. Heuristic correctness — exercises DefaultFidelityRubric with synthetic Metal
//      source strings, one @Test per criterion. Fully deterministic; no bundle access needed.

import Testing
import Foundation
@testable import Presets
import Shared

// MARK: - Fixture Helpers

private func makeDescriptor(
    name: String,
    certified: Bool = false,
    profile: RubricProfile = .full,
    hints: RubricHints = .allFalse,
    sceneFog: Float = 0.0,
    complexityCostTier2: Float = 1.0
) -> PresetDescriptor {
    let hintsJSON = """
    {"hero_specular": \(hints.heroSpecular ? "true" : "false"), "dust_motes": \(hints.dustMotes ? "true" : "false")}
    """
    let json = """
    {
        "name": "\(name)",
        "family": "geometric",
        "certified": \(certified ? "true" : "false"),
        "rubric_profile": "\(profile.rawValue)",
        "rubric_hints": \(hintsJSON),
        "scene_fog": \(sceneFog),
        "complexity_cost": { "tier1": 2.0, "tier2": \(complexityCostTier2) },
        "visual_density": 0.5,
        "motion_intensity": 0.5
    }
    """
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func passChecks() -> RuntimeCheckResults {
    RuntimeCheckResults(silenceNonBlack: true, p95FrameTimeMs: 1.0)
}

private func failChecks() -> RuntimeCheckResults {
    RuntimeCheckResults(silenceNonBlack: false, p95FrameTimeMs: 99.0)
}

// MARK: - Suite 1: Per-Preset Rubric Report

@Suite("Fidelity Rubric — Per-Preset Report")
struct FidelityRubricReportTests {

    @Test func rubricReport_allPresetsLoad() async {
        let store = PresetCertificationStore()
        let results = await store.results()

        guard !results.isEmpty else {
            Issue.record("PresetCertificationStore returned no results — Shaders bundle not found. Skipping report.")
            return
        }

        for (presetID, result) in results.sorted(by: { $0.key < $1.key }) {
            let gateSymbol = result.meetsAutomatedGate ? "✓" : "✗"
            let certSymbol = result.certified ? "CERTIFIED" : "uncertified"
            print("[\(gateSymbol)] \(presetID) (\(result.profile.rawValue)) \(certSymbol) — \(result.totalScore)/\(result.maxScore)")

            for item in result.items {
                let sym = item.status == .pass ? "  pass" : (item.status == .manual ? "  manual" : "  FAIL")
                print("      \(sym)  \(item.id): \(item.detail)")
            }
        }

        // Smoke checks: every result has items and consistent counts.
        for (presetID, result) in results {
            let itemCount = result.items.count
            #expect(itemCount > 0, "\(presetID): RubricResult has no items")
            #expect(result.totalScore >= 0, "\(presetID): negative totalScore")
            #expect(result.totalScore <= result.maxScore, "\(presetID): totalScore \(result.totalScore) exceeds maxScore \(result.maxScore)")
        }
    }
}

// MARK: - Suite 2: Automated Gate Assertions

/// Expected meetsAutomatedGate values for all 13 production presets.
///
/// Updated 2026-04-30 after V.7 Session 2. Arachne now passes (11/15, meetsAutomatedGate).
/// SpectralCartograph passes as lightweight. All other presets still fail M3.
/// Update this dictionary when rubric logic or shader source is intentionally changed.
private let expectedAutomatedGate: [String: Bool] = [
    "Arachne":              true,    // full; V.7 S2 — M1-M6 all pass, E2+E3+E4 ≥2, P1+P3 ≥1
    "Ferrofluid Ocean":     false,   // full; M3 fails
    "Fractal Tree":         false,   // full; M3 fails
    "Glass Brutalist":      false,   // full; M3 fails
    "Gossamer":             false,   // full; M3 fails
    "Kinetic Sculpture":    false,   // full; M3 fails
    "Membrane":             false,   // full; M3 fails
    "Murmuration":          false,   // full; M3 fails (file: Starburst.metal)
    "Nebula":               false,   // lightweight; L2 fails — no deviation primitives in source
    "Plasma":               false,   // lightweight; L2 fails — no deviation primitives in source
    "Spectral Cartograph":  true,    // lightweight; L1+L2+L3 all pass
    "Volumetric Lithograph": false,  // full; M3 fails — mat_* cookbook not yet called
    "Waveform":             false,   // lightweight; L2 fails — no deviation primitives in source
]

@Suite("Fidelity Rubric — Automated Gate")
struct FidelityRubricGateTests {

    @Test func automatedGate_allPresetsMatchExpected() async {
        let store = PresetCertificationStore()
        let results = await store.results()

        guard !results.isEmpty else {
            Issue.record("No rubric results — Shaders bundle not found. Skipping gate assertions.")
            return
        }

        for (presetID, expected) in expectedAutomatedGate {
            guard let result = results[presetID] else {
                Issue.record("\(presetID): not found in rubric results (expected \(expected))")
                continue
            }
            #expect(
                result.meetsAutomatedGate == expected,
                "\(presetID): expected meetsAutomatedGate=\(expected), got \(result.meetsAutomatedGate). Items: \(result.items.map { "\($0.id)=\($0.status)" }.joined(separator: ", "))"
            )
        }
    }

    /// Presets approved by Matt after M7 review and V.7 Session 3 delivery (2026-04-30).
    private let certifiedPresets: Set<String> = ["Arachne"]

    @Test func automatedGate_certifiedMatchesExpected() async {
        let store = PresetCertificationStore()
        let results = await store.results()

        guard !results.isEmpty else {
            Issue.record("No rubric results — Shaders bundle not found. Skipping.")
            return
        }

        for (presetID, result) in results {
            let expectCertified = certifiedPresets.contains(presetID)
            #expect(result.certified == expectCertified, "\(presetID): certified=\(result.certified) expected=\(expectCertified)")
            // isCertified = meetsAutomatedGate && certified — only true when both hold.
            let expectICertified = expectCertified && result.meetsAutomatedGate
            #expect(result.isCertified == expectICertified, "\(presetID): isCertified=\(result.isCertified) expected=\(expectICertified)")
        }
    }
}

// MARK: - Suite 3: Heuristic Correctness (Synthetic Source)

private let rubric = DefaultFidelityRubric()

@Suite("Fidelity Rubric — Heuristics")
struct FidelityRubricHeuristicTests {

    // MARK: - M1 Detail Cascade

    @Test func m1_threeCommentMarkers_passes() {
        let src = """
        // macro: main sdf form
        // meso: ridge variation
        // micro: fbm4(p * 12.0) surface detail
        """
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m1 = r.item(id: "M1_detail_cascade")!
        #expect(m1.status == .pass, "m1: \(m1.detail)")
    }

    @Test func m1_threeDistinctScalesInNoiseCalls_passes() {
        let src = """
        float h = fbm8(p * 3.0);
        float d = fbm4(p * 0.5 + offset);
        float r = fbm4(p * 12.5);
        """
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m1 = r.item(id: "M1_detail_cascade")!
        #expect(m1.status == .pass, "m1: \(m1.detail)")
    }

    @Test func m1_oneScale_fails() {
        let src = "float h = fbm8(p * 3.0);"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m1 = r.item(id: "M1_detail_cascade")!
        #expect(m1.status == .fail, "m1 should fail with single scale: \(m1.detail)")
    }

    // MARK: - M2 Octave Count

    @Test func m2_fbm8_passes() {
        let src = "float n = fbm8(p);"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m2 = r.item(id: "M2_octave_count")!
        #expect(m2.status == .pass, "fbm8 = 8 octaves ≥ 4: \(m2.detail)")
    }

    @Test func m2_warpedFbm_passes() {
        let src = "float3 d = warped_fbm(p, 0.8);"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m2 = r.item(id: "M2_octave_count")!
        #expect(m2.status == .pass, "warped_fbm = 8 octaves: \(m2.detail)")
    }

    @Test func m2_noNoiseCall_fails() {
        let src = "float h = sin(p.x);"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m2 = r.item(id: "M2_octave_count")!
        #expect(m2.status == .fail, "no fbm call: \(m2.detail)")
    }

    // MARK: - M3 Material Count

    @Test func m3_threeDistinctMaterials_passes() {
        let src = """
        MaterialResult mr = mat_polished_chrome(p, n, fv);
        MaterialResult ms = mat_frosted_glass(p, n, fv);
        MaterialResult mw = mat_wet_stone(p, n, fv);
        """
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m3 = r.item(id: "M3_material_count")!
        #expect(m3.status == .pass, "m3: \(m3.detail)")
    }

    @Test func m3_twoMaterials_fails() {
        let src = """
        MaterialResult ma = mat_polished_chrome(p, n, fv);
        MaterialResult mb = mat_frosted_glass(p, n, fv);
        """
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m3 = r.item(id: "M3_material_count")!
        #expect(m3.status == .fail, "2 materials < 3 required: \(m3.detail)")
    }

    // MARK: - M4 Deviation Primitives

    @Test func m4_deviationPrimitive_noAntiPattern_passes() {
        let src = "float zoom = 1.0 + 0.1 * f.bass_rel;"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m4 = r.item(id: "M4_deviation_primitives")!
        #expect(m4.status == .pass, "m4: \(m4.detail)")
    }

    @Test func m4_absoluteThresholdOnNonCommentLine_fails() {
        let src = """
        float zoom = 1.0 + 0.1 * f.bass_rel;
        if (f.bass > 0.4) { doThing(); }
        """
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m4 = r.item(id: "M4_deviation_primitives")!
        #expect(m4.status == .fail, "anti-pattern on non-comment line should fail: \(m4.detail)")
    }

    @Test func m4_absoluteThresholdInComment_passes() {
        // Anti-pattern only in a comment — should not trigger the check.
        let src = """
        // Old code: if (f.bass > 0.3) — replaced with deviation primitive
        float zoom = 1.0 + 0.1 * f.bass_dev;
        """
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m4 = r.item(id: "M4_deviation_primitives")!
        #expect(m4.status == .pass, "anti-pattern in comment only should pass: \(m4.detail)")
    }

    // MARK: - M5/M6/M7

    @Test func m5_silenceNonBlackFalse_fails() {
        let src = ""
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: failChecks(), deviceTier: .tier2)
        let m5 = r.item(id: "M5_silence_fallback")!
        #expect(m5.status == .fail, "silence renders black: \(m5.detail)")
    }

    @Test func m6_costWithinBudget_passes() {
        let desc = makeDescriptor(name: "T", complexityCostTier2: 10.0)  // well under 16.6ms tier2 budget
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m6 = r.item(id: "M6_performance")!
        #expect(m6.status == .pass, "10ms ≤ 16.6ms budget: \(m6.detail)")
    }

    @Test func m6_costExceedsBudget_fails() {
        let desc = makeDescriptor(name: "T", complexityCostTier2: 20.0)  // over 16.6ms
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m6 = r.item(id: "M6_performance")!
        #expect(m6.status == .fail, "20ms > 16.6ms budget: \(m6.detail)")
    }

    @Test func m7_isAlwaysManual() {
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let m7 = r.item(id: "M7_frame_match")!
        #expect(m7.status == .manual, "M7 is always manual: \(m7.detail)")
    }

    // MARK: - Expected Items (E1–E4)

    @Test func e1_triplanarSampleCall_passes() {
        let src = "float3 c = triplanar_sample(p, n, noiseHQ, s);"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let e1 = r.item(id: "E1_triplanar")!
        #expect(e1.status == .pass, "e1: \(e1.detail)")
    }

    @Test func e3_sceneFogInJSON_passes() {
        let desc = makeDescriptor(name: "T", sceneFog: 0.015)
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let e3 = r.item(id: "E3_fog_aerial")!
        #expect(e3.status == .pass, "scene_fog > 0 in JSON: \(e3.detail)")
    }

    // MARK: - Preferred Items (P1–P4)

    @Test func p1_heroSpecularHint_passes() {
        let desc = makeDescriptor(name: "T", hints: RubricHints(heroSpecular: true, dustMotes: false))
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let p1 = r.item(id: "P1_hero_specular")!
        #expect(p1.status == .pass, "rubric_hints.hero_specular: true: \(p1.detail)")
    }

    @Test func p3_dustMotesHint_passes() {
        let desc = makeDescriptor(name: "T", hints: RubricHints(heroSpecular: false, dustMotes: true))
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let p3 = r.item(id: "P3_volumetric_light_motes")!
        #expect(p3.status == .pass, "rubric_hints.dust_motes: true: \(p3.detail)")
    }

    @Test func p4_chromaticAberration_passes() {
        let src = "float3 c = chromatic_aberration_radial(uv, tex, 0.005);"
        let desc = makeDescriptor(name: "T")
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let p4 = r.item(id: "P4_chroma_thinfilm")!
        #expect(p4.status == .pass, "p4: \(p4.detail)")
    }

    // MARK: - Lightweight Profile

    @Test func lightweight_hasOnlyFourItems() {
        let desc = makeDescriptor(name: "T", profile: .lightweight)
        let r = rubric.evaluate(presetID: "T", metalSource: "", descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        #expect(r.items.count == 4, "lightweight has 4 items: \(r.items.map(\.id))")
        #expect(r.maxScore == 4)
        #expect(r.items.allSatisfy { $0.category == .mandatory }, "all lightweight items are mandatory")
    }

    @Test func lightweight_l2MapsMToM4Logic() {
        // L2 (deviation primitives) should pass when deviation fields are present.
        let src = "float zoom = 1.0 + 0.08 * f.mid_att_rel;"
        let desc = makeDescriptor(name: "T", profile: .lightweight)
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        let l2 = r.item(id: "L2_deviation_primitives")!
        #expect(l2.status == .pass, "L2 should pass with mid_att_rel: \(l2.detail)")
    }

    @Test func lightweight_passesGateWhenL1L2L3Pass() {
        // Full pass: silence=true, deviation present, cost within budget.
        let src = "float v = f.bass_dev * 0.5;"
        let desc = makeDescriptor(name: "T", profile: .lightweight, complexityCostTier2: 1.0)
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        #expect(r.meetsAutomatedGate == true, "lightweight gate should pass: \(r.items.map { "\($0.id)=\($0.status.rawValue)" })")
    }

    // MARK: - meetsAutomatedGate — Full Profile End-to-End

    @Test func fullProfile_meetsGate_whenAllConditionsSatisfied() {
        // Source satisfying M1 (3 scales), M2 (fbm8), M3 (3 mat_*), M4 (deviation, no anti-pattern),
        // E items passing, P items passing — M5/M6 from runtime/descriptor.
        let src = """
        // macro: macro form
        // meso: meso variation
        // micro: micro detail
        float h  = fbm8(p * 3.0);
        float d  = fbm4(p * 0.5);
        float r  = fbm4(p * 12.0);
        MaterialResult a = mat_polished_chrome(p, n, fv);
        MaterialResult b = mat_frosted_glass(p, n, fv);
        MaterialResult c = mat_wet_stone(p, n, fv);
        float zoom = 1.0 + 0.08 * f.bass_rel;
        float3 nt = combine_normals_udn(n, d_n);
        float scene_fog_check = 0.015;
        float3 ca = chromatic_aberration_radial(uv, tex, 0.005);
        """
        let desc = makeDescriptor(
            name: "T",
            hints: RubricHints(heroSpecular: true, dustMotes: false),
            sceneFog: 0.015,
            complexityCostTier2: 8.0
        )
        let r = rubric.evaluate(presetID: "T", metalSource: src, descriptor: desc, runtimeChecks: passChecks(), deviceTier: .tier2)
        #expect(r.meetsAutomatedGate == true,
            "full gate should pass. Items: \(r.items.map { "\($0.id)=\($0.status.rawValue)" }.joined(separator: ", "))"
        )
    }
}
