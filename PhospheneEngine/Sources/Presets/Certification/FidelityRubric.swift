// FidelityRubric — V.6 static + runtime rubric analyzer for SHADER_CRAFT.md §12.
//
// Pure analyzer: no filesystem access, no network, no Date.now().
// Tests pass in metalSource as a string and a pre-populated PresetDescriptor.
// This matches the DefaultPresetScorer pattern (D-032).
//
// Static-analysis heuristics are intentionally conservative — false negatives are
// acceptable; false positives are not. Where detection is uncertain, add a
// TODO(V.6+) marker and leave the item at its default.
//
// Rubric item IDs:
//   Full profile mandatory:  M1–M7
//   Full profile expected:   E1–E4
//   Full profile preferred:  P1–P4
//   Lightweight profile:     L1–L4
//
// See SHADER_CRAFT.md §12 and DECISIONS.md D-### for rationale.

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.presets", category: "FidelityRubric")

// MARK: - Protocol

/// Evaluates one preset against the V.6 fidelity rubric.
///
/// Implementations must be pure (deterministic, side-effect-free) so results
/// can be cached and compared across runs.
public protocol FidelityRubricEvaluating: Sendable {
    func evaluate(
        presetID: String,
        metalSource: String,
        descriptor: PresetDescriptor,
        runtimeChecks: RuntimeCheckResults,
        deviceTier: DeviceTier
    ) -> RubricResult
}

// MARK: - DefaultFidelityRubric

/// Concrete rubric evaluator implementing SHADER_CRAFT.md §12.
///
/// ## Heuristic limits
/// Static analysis greps the Metal source for known function names and patterns.
/// It cannot catch:
/// - Functions renamed or inlined by a caller
/// - Utility calls hidden behind a wrapper macro
/// - Author intent (rubric_hints compensates for P1 and P3)
///
/// When in doubt, items default to fail rather than pass. Authors can override
/// P1/P3 via `rubric_hints` in the JSON sidecar.
public struct DefaultFidelityRubric: FidelityRubricEvaluating {

    public init() {}

    // MARK: - V.3 Materials cookbook names (D-062, D-063)

    private static let knownMaterialFunctions: Set<String> = [
        "mat_polished_chrome",
        "mat_brushed_aluminum",
        "mat_gold",
        "mat_copper",
        "mat_ferrofluid",
        "mat_ceramic",
        "mat_frosted_glass",
        "mat_wet_stone",
        "mat_bark",
        "mat_leaf",
        "mat_silk_thread",
        "mat_chitin",
        "mat_ocean",
        "mat_ink",
        "mat_marble",
        "mat_granite",
        "mat_velvet",
        "mat_sand_glints",
        "mat_concrete",
        // TODO(V.6+): extend as new cookbook recipes are added in V.5+
    ]

    // MARK: - Deviation primitive field names (D-026)

    private static let deviationPrimitiveNames: [String] = [
        "f.bass_rel", "f.bass_dev",
        "f.mid_rel",  "f.mid_dev",
        "f.treb_rel", "f.treb_dev",
        "f.composite_rel", "f.composite_dev",
        "bass_att_rel", "mid_att_rel", "treb_att_rel",
        "stems.vocals_energy_rel", "stems.vocals_energy_dev",
        "stems.drums_energy_rel",  "stems.drums_energy_dev",
        "stems.bass_energy_rel",   "stems.bass_energy_dev",
        "stems.other_energy_rel",  "stems.other_energy_dev",
        // MV-3a stem rich metadata deviation forms
        "vocals_energy_rel", "vocals_energy_dev",
        "drums_energy_rel",  "drums_energy_dev",
        "bass_energy_rel",   "bass_energy_dev",
        "other_energy_rel",  "other_energy_dev",
    ]

    // MARK: - Absolute-threshold anti-patterns (D-026 violation indicators)
    // Patterns like "f.bass > 0.5" or "f.mid < 0.3" outside of comments.
    // Created inline in evaluateM4() to avoid Regex Sendable conformance issues in Swift 6.

    // MARK: - evaluate

    public func evaluate(
        presetID: String,
        metalSource: String,
        descriptor: PresetDescriptor,
        runtimeChecks: RuntimeCheckResults,
        deviceTier: DeviceTier
    ) -> RubricResult {
        let profile = descriptor.rubricProfile
        let items: [RubricItem]

        switch profile {
        case .full:
            items = evaluateFullProfile(
                metalSource: metalSource,
                descriptor: descriptor,
                runtimeChecks: runtimeChecks,
                deviceTier: deviceTier
            )
        case .lightweight:
            items = evaluateLightweightProfile(
                metalSource: metalSource,
                descriptor: descriptor,
                runtimeChecks: runtimeChecks,
                deviceTier: deviceTier
            )
        }

        return buildResult(
            presetID: presetID,
            profile: profile,
            items: items,
            certified: descriptor.certified
        )
    }

    // MARK: - Full Profile (M1–M7, E1–E4, P1–P4)

    private func evaluateFullProfile(
        metalSource: String,
        descriptor: PresetDescriptor,
        runtimeChecks: RuntimeCheckResults,
        deviceTier: DeviceTier
    ) -> [RubricItem] {
        [
            evaluateM1(metalSource),
            evaluateM2(metalSource),
            evaluateM3(metalSource),
            evaluateM4(metalSource),
            evaluateM5(runtimeChecks),
            evaluateM6(descriptor, runtimeChecks, deviceTier),
            evaluateM7(descriptor),
            evaluateE1(metalSource),
            evaluateE2(metalSource),
            evaluateE3(metalSource, descriptor),
            evaluateE4(metalSource),
            evaluateP1(descriptor),
            evaluateP2(metalSource),
            evaluateP3(metalSource, descriptor),
            evaluateP4(metalSource),
        ]
    }

    // MARK: - Lightweight Profile (L1–L4)

    private func evaluateLightweightProfile(
        metalSource: String,
        descriptor: PresetDescriptor,
        runtimeChecks: RuntimeCheckResults,
        deviceTier: DeviceTier
    ) -> [RubricItem] {
        // L1 = silence fallback (M5 logic)
        // L2 = deviation primitives (M4 logic)
        // L3 = performance (M6 logic)
        // L4 = frame match (M7 logic, always manual)
        let l1 = evaluateM5(runtimeChecks)
        let l2 = evaluateM4(metalSource)
        let l3 = evaluateM6(descriptor, runtimeChecks, deviceTier)
        let l4 = evaluateM7(descriptor)

        return [
            RubricItem(id: "L1_silence_fallback",     label: "Silence fallback",    category: .mandatory, status: l1.status, detail: l1.detail),
            RubricItem(id: "L2_deviation_primitives",  label: "Deviation primitives", category: .mandatory, status: l2.status, detail: l2.detail),
            RubricItem(id: "L3_performance",           label: "Performance budget",   category: .mandatory, status: l3.status, detail: l3.detail),
            RubricItem(id: "L4_frame_match",           label: "Reference frame match", category: .mandatory, status: l4.status, detail: l4.detail),
        ]
    }

    // MARK: - M1: Detail Cascade

    /// Heuristic: at least 3 distinct scale values detected in noise calls, OR
    /// explicit macro/meso/micro/specular comment markers present.
    private func evaluateM1(_ src: String) -> RubricItem {
        // Look for // macro, // meso, // micro, // specular discipline markers.
        let markerCount = [
            src.localizedCaseInsensitiveContains("// macro"),
            src.localizedCaseInsensitiveContains("// meso"),
            src.localizedCaseInsensitiveContains("// micro"),
            src.localizedCaseInsensitiveContains("// specular"),
        ].filter { $0 }.count

        if markerCount >= 3 {
            return RubricItem(
                id: "M1_detail_cascade",
                label: "Detail cascade",
                category: .mandatory,
                status: .pass,
                detail: "\(markerCount) of 4 cascade markers found (// macro/meso/micro/specular)"
            )
        }

        // Fallback: look for noise calls at 3+ distinct scale literals.
        // Matches patterns like fbm8(p * 3.0), fbm4(p * 12.5), etc.
        // Also matches warped_fbm(p, N), ridged_mf(p, N, N).
        let scalePattern = /(?:fbm[0-9]+|warped_fbm|ridged_mf|perlin[23]d|worley[23]d|simplex[34]d)\s*\([^)]*\*\s*([0-9]+\.?[0-9]*)/
        let matches = src.matches(of: scalePattern)
        let distinctScales = Set(matches.compactMap { Float($0.output.1) }).count

        let status: RubricItemStatus = distinctScales >= 3 ? .pass : .fail
        let detail = markerCount > 0
            ? "\(markerCount)/4 cascade markers + \(distinctScales) distinct noise scales"
            : "\(distinctScales) distinct noise scales (need ≥3, or ≥3 cascade markers)"
        return RubricItem(id: "M1_detail_cascade", label: "Detail cascade", category: .mandatory, status: status, detail: detail)
    }

    // MARK: - M2: ≥4 Octave Noise

    /// Detect the highest octave count across all hero-noise function calls.
    /// fbm4→4, fbm8→8, fbm12→12, warped_fbm/ridged_mf→8 (default), worley_fbm→6.
    private func evaluateM2(_ src: String) -> RubricItem {
        var maxOctaves = 0

        // Explicit fbmN calls: extract N.
        let fbmPattern = /\bfbm([0-9]+)\s*\(/
        for match in src.matches(of: fbmPattern) {
            if let count = Int(match.output.1) {
                maxOctaves = max(maxOctaves, count)
            }
        }
        // warped_fbm internally uses fbm8 (V.1 DomainWarp.metal).
        if src.contains("warped_fbm(") { maxOctaves = max(maxOctaves, 8) }
        // ridged_mf default = 6 octaves (V.1 RidgedMultifractal.metal).
        if src.contains("ridged_mf(")  { maxOctaves = max(maxOctaves, 6) }
        // worley_fbm = Worley blended with fbm8 internally (V.2 Worley.metal).
        if src.contains("worley_fbm(") { maxOctaves = max(maxOctaves, 6) }

        let status: RubricItemStatus = maxOctaves >= 4 ? .pass : .fail
        return RubricItem(
            id: "M2_octave_count",
            label: "≥4 noise octaves",
            category: .mandatory,
            status: status,
            detail: "max detected octave count: \(maxOctaves) (need ≥4)"
        )
    }

    // MARK: - M3: ≥3 Distinct Materials

    /// Count distinct V.3 cookbook function callsites (not occurrences of the same one).
    private func evaluateM3(_ src: String) -> RubricItem {
        let found = Self.knownMaterialFunctions.filter { src.contains($0 + "(") }
        let status: RubricItemStatus = found.count >= 3 ? .pass : .fail
        let listSnippet = found.sorted().joined(separator: ", ")
        return RubricItem(
            id: "M3_material_count",
            label: "≥3 cookbook materials",
            category: .mandatory,
            status: status,
            detail: found.isEmpty
                ? "no mat_* cookbook calls found (need ≥3 distinct)"
                : "\(found.count) distinct: \(listSnippet)"
        )
    }

    // MARK: - M4: Deviation Primitives

    /// Pass when source uses at least one D-026 deviation field AND contains no
    /// absolute-threshold anti-patterns (f.bass > 0.x outside comments).
    private func evaluateM4(_ src: String) -> RubricItem {
        let usedFields = Self.deviationPrimitiveNames.filter { src.contains($0) }

        // Check for absolute-threshold anti-patterns on non-comment lines.
        let nonCommentLines = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let absoluteThresholdPattern = /\bf\.(bass|mid|treb|treble)\s*[><]\s*0\.[0-9]/
        let hasAbsoluteThreshold = nonCommentLines.firstMatch(of: absoluteThresholdPattern) != nil

        let status: RubricItemStatus
        let detail: String

        if usedFields.isEmpty {
            status = .fail
            detail = "no deviation primitives found (bass_rel/dev, mid_rel/dev, etc. from D-026)"
        } else if hasAbsoluteThreshold {
            status = .fail
            detail = "\(usedFields.count) deviation fields found but also has absolute-threshold pattern (f.band > 0.x) — D-026 violation"
        } else {
            status = .pass
            detail = "uses: \(usedFields.prefix(4).joined(separator: ", "))\(usedFields.count > 4 ? " +" : "")"
        }

        return RubricItem(id: "M4_deviation_primitives", label: "Deviation primitives (D-026)", category: .mandatory, status: status, detail: detail)
    }

    // MARK: - M5: Silence Fallback

    /// Runtime check: silence renders non-black (from Increment 5.2).
    /// Source check for D-019 warmup pattern is informational only.
    private func evaluateM5(_ checks: RuntimeCheckResults) -> RubricItem {
        let hasWarmup = false  // informational; runtime is the gate
        _ = hasWarmup  // suppress unused warning

        let status: RubricItemStatus = checks.silenceNonBlack ? .pass : .fail
        return RubricItem(
            id: "M5_silence_fallback",
            label: "Graceful silence fallback",
            category: .mandatory,
            status: status,
            detail: checks.silenceNonBlack
                ? "runtime: silence renders non-black"
                : "runtime: silence renders black (D-019 warmup missing or broken)"
        )
    }

    // MARK: - M6: Performance Budget

    /// Pass when the descriptor's complexity_cost for the given tier is within budget.
    private func evaluateM6(
        _ descriptor: PresetDescriptor,
        _ checks: RuntimeCheckResults,
        _ tier: DeviceTier
    ) -> RubricItem {
        let cost = descriptor.complexityCost.cost(for: tier)
        let budget = tier.frameBudgetMs
        let status: RubricItemStatus = cost <= budget ? .pass : .fail
        return RubricItem(
            id: "M6_performance",
            label: "Performance budget",
            category: .mandatory,
            status: status,
            detail: "\(tier) budget \(String(format: "%.1f", budget)) ms; complexity_cost \(String(format: "%.1f", cost)) ms"
        )
    }

    // MARK: - M7: Reference Frame Match (always manual)

    private func evaluateM7(_ descriptor: PresetDescriptor) -> RubricItem {
        RubricItem(
            id: "M7_frame_match",
            label: "Matt-approved reference frame match",
            category: .mandatory,
            status: .manual,
            detail: "certified flag: \(descriptor.certified) — awaiting manual review against docs/VISUAL_REFERENCES/"
        )
    }

    // MARK: - E1: Triplanar

    private func evaluateE1(_ src: String) -> RubricItem {
        let found = src.contains("triplanar_sample(") || src.contains("triplanar_normal(")
            || src.contains("triplanar_blend_weights(") || src.contains("triplanar_detail_normal(")
        return RubricItem(
            id: "E1_triplanar",
            label: "Triplanar texturing",
            category: .expected,
            status: found ? .pass : .fail,
            detail: found ? "triplanar_* call found" : "no triplanar_* calls found"
        )
    }

    // MARK: - E2: Detail Normals

    private func evaluateE2(_ src: String) -> RubricItem {
        let found = src.contains("combine_normals_udn(")
            || src.contains("combine_normals_whiteout(")
            || src.contains("detail_normal")
            || src.contains("tbn_from_derivatives(")
        return RubricItem(
            id: "E2_detail_normals",
            label: "Detail normals",
            category: .expected,
            status: found ? .pass : .fail,
            detail: found ? "detail-normal utility call found" : "no detail-normal calls found"
        )
    }

    // MARK: - E3: Volumetric Fog / Aerial Perspective

    private func evaluateE3(_ src: String, _ descriptor: PresetDescriptor) -> RubricItem {
        let inSource = src.contains("fog(") || src.contains("aerial_perspective(")
            || src.contains("vol_accumulate(") || src.contains("ls_radial_step_uv(")
            || src.contains("cloud_march(")
        let inJSON = descriptor.sceneFog > 0
        let found = inSource || inJSON
        let detail = inJSON
            ? "scene_fog: \(String(format: "%.4f", descriptor.sceneFog))"
            : (inSource ? "volumetric/fog call found in source" : "no fog/aerial/volumetric calls found")
        return RubricItem(
            id: "E3_fog_aerial",
            label: "Volumetric fog / aerial perspective",
            category: .expected,
            status: found ? .pass : .fail,
            detail: detail
        )
    }

    // MARK: - E4: Advanced BRDF (SSS / fiber / anisotropic)

    private func evaluateE4(_ src: String) -> RubricItem {
        let found = src.contains("sss_backlit(") || src.contains("sss_wrap_lighting(")
            || src.contains("fiber_marschner_lite(") || src.contains("fiber_trt_lobe(")
            || src.contains("brdf_ashikhmin_shirley(") || src.contains("oren_nayar(")
        return RubricItem(
            id: "E4_advanced_brdf",
            label: "SSS / fiber / anisotropic BRDF",
            category: .expected,
            status: found ? .pass : .fail,
            detail: found ? "advanced BRDF call found" : "no SSS/fiber/anisotropic BRDF calls found"
        )
    }

    // MARK: - P1: Hero Specular (author-asserted)

    private func evaluateP1(_ descriptor: PresetDescriptor) -> RubricItem {
        let asserted = descriptor.rubricHints.heroSpecular
        return RubricItem(
            id: "P1_hero_specular",
            label: "Hero specular highlight ≥60% of frames",
            category: .preferred,
            status: asserted ? .pass : .fail,
            detail: asserted
                ? "rubric_hints.hero_specular: true (author-asserted)"
                : "rubric_hints.hero_specular: false (set to true in JSON when present)"
        )
    }

    // MARK: - P2: Parallax Occlusion Mapping

    private func evaluateP2(_ src: String) -> RubricItem {
        let found = src.contains("parallax_occlusion(") || src.contains("parallax_shadowed(")
        return RubricItem(
            id: "P2_parallax_occlusion",
            label: "Parallax occlusion mapping",
            category: .preferred,
            status: found ? .pass : .fail,
            detail: found ? "parallax_occlusion* call found" : "no parallax_occlusion calls found"
        )
    }

    // MARK: - P3: Volumetric Light Shafts / Dust Motes

    private func evaluateP3(_ src: String, _ descriptor: PresetDescriptor) -> RubricItem {
        let inSource = src.contains("ls_radial_step_uv(") || src.contains("ls_shadow_march(")
            || src.contains("ls_sun_disk(") || src.contains("ls_intensity_audio(")
        let asserted = descriptor.rubricHints.dustMotes
        let found = inSource || asserted
        let detail: String
        if inSource {
            detail = "light-shaft utility call found in source"
        } else if asserted {
            detail = "rubric_hints.dust_motes: true (author-asserted)"
        } else {
            detail = "no light-shaft calls; rubric_hints.dust_motes: false"
        }
        return RubricItem(
            id: "P3_volumetric_light_motes",
            label: "Volumetric light shafts / dust motes",
            category: .preferred,
            status: found ? .pass : .fail,
            detail: detail
        )
    }

    // MARK: - P4: Chromatic Aberration / Thin-Film Interference

    private func evaluateP4(_ src: String) -> RubricItem {
        let found = src.contains("chromatic_aberration_radial(")
            || src.contains("chromatic_aberration_directional(")
            || src.contains("thinfilm_rgb(")
            || src.contains("thinfilm_hue_rotate(")
        return RubricItem(
            id: "P4_chroma_thinfilm",
            label: "Chromatic aberration / thin-film",
            category: .preferred,
            status: found ? .pass : .fail,
            detail: found ? "chromatic_aberration or thinfilm call found" : "no chromatic aberration / thin-film calls"
        )
    }

    // MARK: - Result Assembly

    private func buildResult(
        presetID: String,
        profile: RubricProfile,
        items: [RubricItem],
        certified: Bool
    ) -> RubricResult {
        let mandatory  = items.filter { $0.category == .mandatory }
        let expected   = items.filter { $0.category == .expected }
        let preferred  = items.filter { $0.category == .preferred }

        let mandatoryPass = mandatory.filter { $0.status == .pass }.count
        let expectedPass  = expected.filter  { $0.status == .pass }.count
        let preferredPass = preferred.filter { $0.status == .pass }.count
        let total = mandatoryPass + expectedPass + preferredPass

        let maxScore: Int
        let meetsGate: Bool

        switch profile {
        case .full:
            maxScore = 15
            // M1–M6 must all pass (M7 is manual, excluded from automated gate).
            let automatableMandatory = mandatory.filter { $0.id != "M7_frame_match" }
            let allMandatoryPass = automatableMandatory.allSatisfy { $0.status == .pass }
            meetsGate = allMandatoryPass && expectedPass >= 2 && preferredPass >= 1

        case .lightweight:
            maxScore = 4
            // L1–L3 must all pass (L4 is manual).
            let automatableLight = mandatory.filter { $0.id != "L4_frame_match" }
            meetsGate = automatableLight.allSatisfy { $0.status == .pass }
        }

        return RubricResult(
            presetID: presetID,
            profile: profile,
            items: items,
            mandatoryPassCount: mandatoryPass,
            expectedPassCount: expectedPass,
            preferredPassCount: preferredPass,
            totalScore: total,
            maxScore: maxScore,
            meetsAutomatedGate: meetsGate,
            certified: certified
        )
    }
}
