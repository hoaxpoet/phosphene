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
// See SHADER_CRAFT.md §12 and DECISIONS.md D-067 for rationale.

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

    static let knownMaterialFunctions: Set<String> = [
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

    static let deviationPrimitiveNames: [String] = [
        "f.bass_rel", "f.bass_dev",
        "f.mid_rel", "f.mid_dev",
        "f.treb_rel", "f.treb_dev",
        "f.composite_rel", "f.composite_dev",
        "bass_att_rel", "mid_att_rel", "treb_att_rel",
        "stems.vocals_energy_rel", "stems.vocals_energy_dev",
        "stems.drums_energy_rel", "stems.drums_energy_dev",
        "stems.bass_energy_rel", "stems.bass_energy_dev",
        "stems.other_energy_rel", "stems.other_energy_dev",
        // MV-3a stem rich metadata deviation forms
        "vocals_energy_rel", "vocals_energy_dev",
        "drums_energy_rel", "drums_energy_dev",
        "bass_energy_rel", "bass_energy_dev",
        "other_energy_rel", "other_energy_dev",
    ]

    // Absolute-threshold regex is created inline in evaluateM4() to avoid
    // Regex<Output> Sendable conformance issues in Swift 6.

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
}
