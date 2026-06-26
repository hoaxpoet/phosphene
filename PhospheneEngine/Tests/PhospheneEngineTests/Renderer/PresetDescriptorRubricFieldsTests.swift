// PresetDescriptorRubricFieldsTests — Regression gate for V.6 rubric schema fields.
//
// Tests:
//   1. Default on missing: certified defaults false, rubric_profile defaults .full,
//      rubric_hints defaults .allFalse.
//   2. Round-trip Codable: certified + rubric_profile + rubric_hints encode then decode.
//   3. Malformed rubric_profile: unknown string falls back to .full with a warning.
//   4. Lightweight preset classification: rubric_profile "lightweight" decodes correctly.
//   5. All built-in sidecars decode; any declared rubric_profile is a known value.
//   6. rubric_hints hero_specular and dust_motes decode from JSON.

import Testing
import Foundation
@testable import Presets

// MARK: - 1. Defaults when fields missing

@Test func presetDescriptorRubric_defaultsWhenFieldsMissing() throws {
    let json = #"{ "name": "TestPreset" }"#
    let d = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(d.certified == false)
    #expect(d.rubricProfile == .full)
    #expect(d.rubricHints == .allFalse)
    #expect(d.rubricHints.heroSpecular == false)
    #expect(d.rubricHints.dustMotes == false)
}

// MARK: - 2. Round-trip Codable

@Test func presetDescriptorRubric_roundTrip() throws {
    let json = """
    {
        "name": "RoundTrip",
        "certified": false,
        "rubric_profile": "lightweight",
        "rubric_hints": { "hero_specular": true, "dust_motes": false }
    }
    """
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    let first = try decoder.decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(first.certified == false)
    #expect(first.rubricProfile == .lightweight)
    #expect(first.rubricHints.heroSpecular == true)
    #expect(first.rubricHints.dustMotes == false)

    let reencoded = try encoder.encode(first)
    let second = try decoder.decode(PresetDescriptor.self, from: reencoded)
    #expect(second.certified == false)
    #expect(second.rubricProfile == .lightweight)
    #expect(second.rubricHints.heroSpecular == true)
}

// MARK: - 3. Malformed rubric_profile falls back to .full

@Test func presetDescriptorRubric_malformedProfileFallsBackToFull() throws {
    let json = #"{ "name": "BadProfile", "rubric_profile": "ultra_fancy" }"#
    let d = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    // Should not throw; should silently fall back to .full.
    #expect(d.rubricProfile == .full)
}

// MARK: - 4. Lightweight classification

@Test func presetDescriptorRubric_lightweightDecodes() throws {
    let json = #"{ "name": "LightweightPreset", "rubric_profile": "lightweight" }"#
    let d = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(d.rubricProfile == .lightweight)
}

// MARK: - 5. All built-in sidecars decode; declared profiles are valid

@Test func presetDescriptorRubric_allBuiltInPresetsHaveCertificationFields() throws {
    // `Bundle.module` is module-scoped: from this test target it resolves to the
    // test bundle, which has no `Shaders` resource, so this guard used to skip
    // silently (BUG-002). `PresetLoader.bundledShadersURL` runs the same lookup
    // inside the Presets module, where the resource lives, so the guard enforces
    // instead of skipping. (Don't "fix" this by copying Shaders into the test
    // target — there's no such directory under Tests/, and it would duplicate the
    // whole shader corpus.)
    let shadersURL = try #require(PresetLoader.bundledShadersURL,
        "Shaders resource not found via PresetLoader.bundledShadersURL")
    let jsonFiles = try FileManager.default.contentsOfDirectory(
        at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == "json" }
    #expect(jsonFiles.count >= 13, "Expected at least 13 JSON sidecars")

    // The certified-flag ground truth is owned and enforced against the real rubric
    // pipeline by FidelityRubricTests.automatedGate_uncertifiedPresetsAreUncertified
    // (its `certifiedPresets` set). Duplicating that list here is exactly what let
    // it go stale, so this test no longer mirrors it. We assert only schema
    // integrity over the real corpus: every sidecar decodes, and any declared
    // rubric_profile is a known value — i.e. nothing silently fell back to .full
    // from a typo'd string (the decoder's behaviour for an unknown profile).
    let decoder = JSONDecoder()
    for jsonURL in jsonFiles {
        let data = try Data(contentsOf: jsonURL)

        // Name the file + error on a decode throw (see shippedPresets_neverDecodeToEmptyPasses):
        // one bad enum throws the whole descriptor decode, and a bare `try` names neither.
        let descriptor: PresetDescriptor
        do {
            descriptor = try decoder.decode(PresetDescriptor.self, from: data)
        } catch {
            Issue.record("Malformed sidecar \(jsonURL.lastPathComponent): \(error)")
            continue
        }

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let profileString = object?["rubric_profile"] as? String {
            #expect(RubricProfile(rawValue: profileString) != nil,
                    "\(descriptor.name): unknown rubric_profile \"\(profileString)\" (falls back to .full)")
        }
    }
}

// MARK: - 6. rubric_hints decode

@Test func presetDescriptorRubric_hintsDecodeCorrectly() throws {
    let json = """
    {
        "name": "WithHints",
        "rubric_hints": { "hero_specular": true, "dust_motes": true }
    }
    """
    let d = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(d.rubricHints.heroSpecular == true)
    #expect(d.rubricHints.dustMotes == true)
}
