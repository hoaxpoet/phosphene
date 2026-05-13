// PresetDescriptorTaxonomyTests — Regression gate for D-120 property taxonomy fields.
//
// Tests:
//   1. Defaults: minimal JSON decodes with empty concept_tags + nil motion_paradigm.
//   2. concept_tags: ["a","b"] decodes as ["a","b"].
//   3. motion_paradigm: "ray_march_static" decodes as .rayMarchStatic.
//   4. Invalid motion_paradigm throws DecodingError (closed set; no silent fallback).
//   5. Round-trip: encode/decode preserves both fields.
//   6. MotionParadigm.allCases == 8 (regression-locks the closed set).

import Testing
import Foundation
@testable import Presets

// MARK: - 1. Defaults when fields missing

@Test func presetDescriptorTaxonomy_defaultsToEmptyTagsAndNilParadigm() throws {
    let json = #"{ "name": "MinimalPreset" }"#
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.conceptTags == [])
    #expect(descriptor.motionParadigm == nil)
}

// MARK: - 2. concept_tags array decodes

@Test func presetDescriptorTaxonomy_conceptTagsDecodesArray() throws {
    let json = #"{ "name": "Tagged", "concept_tags": ["fractal", "geometric"] }"#
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.conceptTags == ["fractal", "geometric"])
}

// MARK: - 3. motion_paradigm enum decodes

@Test func presetDescriptorTaxonomy_motionParadigmDecodesEnum() throws {
    let json = #"{ "name": "RayMarchPreset", "motion_paradigm": "ray_march_static" }"#
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.motionParadigm == .rayMarchStatic)
}

// MARK: - 4. Invalid motion_paradigm throws

@Test func presetDescriptorTaxonomy_invalidMotionParadigmThrows() throws {
    let json = #"{ "name": "BadParadigm", "motion_paradigm": "not_a_real_paradigm" }"#
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }
}

// MARK: - 5. Round-trip preserves both fields

@Test func presetDescriptorTaxonomy_roundTripPreservesBothFields() throws {
    let json = """
    {
        "name": "RoundTrip",
        "concept_tags": ["web", "glass"],
        "motion_paradigm": "staged_composition"
    }
    """
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    let first = try decoder.decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(first.conceptTags == ["web", "glass"])
    #expect(first.motionParadigm == .stagedComposition)

    let reencoded = try encoder.encode(first)
    let second = try decoder.decode(PresetDescriptor.self, from: reencoded)
    #expect(second.conceptTags == ["web", "glass"])
    #expect(second.motionParadigm == .stagedComposition)
}

// MARK: - 6. MotionParadigm closed-set invariant

@Test func motionParadigm_allCasesCovers8Values() {
    // D-120 names a closed set of 8 motion paradigms derived from D-029.
    // Any change to this count requires a D-120 amendment.
    #expect(MotionParadigm.allCases.count == 8)
    let expected: Set<MotionParadigm> = [
        .mvWarp, .particles, .feedbackWarp, .cameraFlight,
        .meshAnimation, .directTimeModulation, .rayMarchStatic, .stagedComposition
    ]
    #expect(Set(MotionParadigm.allCases) == expected)
}
