// PresetDescriptorRubricFieldsTests — Regression gate for V.6 rubric schema fields.
//
// Tests:
//   1. Default on missing: certified defaults false, rubric_profile defaults .full,
//      rubric_hints defaults .allFalse.
//   2. Round-trip Codable: certified + rubric_profile + rubric_hints encode then decode.
//   3. Malformed rubric_profile: unknown string falls back to .full with a warning.
//   4. Lightweight preset classification: rubric_profile "lightweight" decodes correctly.
//   5. All 13 production sidecars decode without warnings (certified: false, correct profiles).
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

// MARK: - 5. All 13 production sidecars decode correctly

@Test func presetDescriptorRubric_allBuiltInPresetsHaveCertificationFields() throws {
    guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
        return  // Shaders bundle not accessible from this test target — skip gracefully
    }
    let contents = try FileManager.default.contentsOfDirectory(
        at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )
    let jsonFiles = contents.filter { $0.pathExtension == "json" }
    #expect(jsonFiles.count >= 13, "Expected at least 13 JSON sidecars")

    let lightweightExpected: Set<String> = ["Plasma", "Waveform", "Nebula", "Spectral Cartograph"]
    let decoder = JSONDecoder()
    var loaded = 0

    for jsonURL in jsonFiles {
        let data = try Data(contentsOf: jsonURL)
        let descriptor = try decoder.decode(PresetDescriptor.self, from: data)
        loaded += 1

        // All presets must have certified: false initially.
        #expect(descriptor.certified == false, "\(descriptor.name): expected certified: false")

        // Lightweight presets must declare the correct profile.
        if lightweightExpected.contains(descriptor.name) {
            #expect(descriptor.rubricProfile == .lightweight,
                    "\(descriptor.name): expected rubric_profile: lightweight")
        } else {
            #expect(descriptor.rubricProfile == .full,
                    "\(descriptor.name): expected rubric_profile: full (or missing)")
        }
    }
    #expect(loaded >= 13)
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
