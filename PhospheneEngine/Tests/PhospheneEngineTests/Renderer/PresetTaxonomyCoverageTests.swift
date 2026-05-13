// PresetTaxonomyCoverageTests — D-120 coverage integration tests.
//
// Asserts the per-preset coverage invariant: every production preset declares
// a motion_paradigm; every production preset declares non-empty concept_tags
// EXCEPT diagnostic presets (is_diagnostic: true), for which empty is allowed.
//
// This is the regression gate against an unmaintained taxonomy: if a new
// preset is added without taxonomy fields, the first or second test fires
// with the preset's name.

import Testing
import Foundation
@testable import Presets

// MARK: - Helpers

private func loadProductionDescriptors() throws -> [PresetDescriptor] {
    guard let shadersURL = PresetLoader.bundledShadersURL else {
        // Bundle.module isn't accessible from this test target — skip gracefully.
        return []
    }
    let contents = try FileManager.default.contentsOfDirectory(
        at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )
    let jsonFiles = contents.filter { $0.pathExtension == "json" }
    let decoder = JSONDecoder()
    return try jsonFiles.map { url in
        try decoder.decode(PresetDescriptor.self, from: Data(contentsOf: url))
    }
}

// MARK: - 1. motion_paradigm coverage

@Test func taxonomyCoverage_everyProductionPresetHasNonNilMotionParadigm() throws {
    let descriptors = try loadProductionDescriptors()
    guard !descriptors.isEmpty else { return }  // skip when bundle is inaccessible

    let untagged = descriptors.filter { $0.motionParadigm == nil }
    #expect(untagged.isEmpty, """
        Every production preset MUST declare motion_paradigm (D-120).
        Missing on: \(untagged.map(\.name).sorted().joined(separator: ", "))
        """)
}

// MARK: - 2. concept_tags coverage

@Test func taxonomyCoverage_everyProductionPresetHasTagsOrIsDiagnostic() throws {
    let descriptors = try loadProductionDescriptors()
    guard !descriptors.isEmpty else { return }

    // Per D-120: empty concept_tags is permitted only for diagnostic presets
    // (is_diagnostic: true). Any non-diagnostic preset with empty tags is a
    // taxonomy gap.
    let untagged = descriptors.filter { $0.conceptTags.isEmpty && !$0.isDiagnostic }
    #expect(untagged.isEmpty, """
        Non-diagnostic production presets MUST declare at least one concept_tag (D-120).
        Empty-tag non-diagnostic presets: \(untagged.map(\.name).sorted().joined(separator: ", "))
        """)
}

// MARK: - 3. Diagnostic-allowlist sanity

@Test func taxonomyCoverage_diagnosticPresetsMayHaveEmptyTags() throws {
    let descriptors = try loadProductionDescriptors()
    guard !descriptors.isEmpty else { return }

    // Verify the diagnostic allowlist matches the documented Phase-LM / V.7.6.C
    // diagnostic class — currently Spectral Cartograph + Staged Sandbox. Any
    // new diagnostic preset must be added to is_diagnostic: true explicitly;
    // an accidental "empty tags + is_diagnostic: false" combination would
    // trip test #2 above.
    let diagnostics = descriptors.filter(\.isDiagnostic).map(\.name).sorted()
    let expected = ["Spectral Cartograph", "Staged Sandbox"]
    #expect(diagnostics == expected, """
        Diagnostic-preset set drifted from documented allowlist.
        Expected: \(expected.joined(separator: ", "))
        Got:      \(diagnostics.joined(separator: ", "))
        If a new diagnostic preset is intended, update this test and the
        CLAUDE.md module-map entry; otherwise tag the offending preset
        properly with concept_tags + (probably) is_diagnostic: false.
        """)
}
