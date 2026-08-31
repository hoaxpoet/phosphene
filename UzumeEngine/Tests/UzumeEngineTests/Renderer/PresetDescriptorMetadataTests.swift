// PresetDescriptorMetadataTests — Regression gate for Increment 4.0 enriched preset metadata.
//
// Five tests:
//   1. Round-trip: encode → decode preserves all new fields.
//   2. Default: minimal JSON applies documented defaults for all new fields.
//   3. Malformed: unknown fatigue_risk value decodes without throwing, falls back to .medium.
//   4. ComplexityCost variants: scalar and nested object forms both decode correctly.
//   5. Back-fill: every on-disk JSON sidecar was back-filled (non-default complexity proves it).

import Testing
import Foundation
import Metal
import simd
@testable import Presets

private enum MetadataTestError: Error {
    case noMetalDevice
}

// MARK: - 1. Round-trip

@Test func presetDescriptorMetadata_roundTrip() throws {
    let json = """
    {
        "name": "RoundTrip",
        "family": "geometric",
        "visual_density": 0.35,
        "motion_intensity": 0.72,
        "color_temperature_range": [0.15, 0.85],
        "fatigue_risk": "high",
        "transition_affordances": ["crossfade", "cut"],
        "section_suitability": ["buildup", "peak"],
        "complexity_cost": { "tier1": 2.4, "tier2": 1.1 }
    }
    """
    let decoder = JSONDecoder()
    let first = try decoder.decode(PresetDescriptor.self, from: Data(json.utf8))

    // Re-encode then re-decode.
    let encoder = JSONEncoder()
    let reencoded = try encoder.encode(first)
    let second = try decoder.decode(PresetDescriptor.self, from: reencoded)

    #expect(second.name == "RoundTrip")
    #expect(second.visualDensity == 0.35)
    #expect(second.motionIntensity == 0.72)
    #expect(second.colorTemperatureRange == SIMD2<Float>(0.15, 0.85))
    #expect(second.fatigueRisk == .high)
    #expect(second.transitionAffordances == [.crossfade, .cut])
    #expect(second.sectionSuitability == [.buildup, .peak])
    #expect(second.complexityCost.tier1 == 2.4)
    #expect(second.complexityCost.tier2 == 1.1)
}

// MARK: - 2. Defaults

@Test func presetDescriptorMetadata_defaultsWhenFieldsMissing() throws {
    // Only "name" is required; all new fields should fall back to documented defaults.
    let json = """
    { "name": "Minimal" }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))

    #expect(descriptor.visualDensity == 0.5,
            "visual_density default is 0.5, got \(descriptor.visualDensity)")
    #expect(descriptor.motionIntensity == 0.5,
            "motion_intensity default is 0.5, got \(descriptor.motionIntensity)")
    #expect(descriptor.colorTemperatureRange == SIMD2<Float>(0.3, 0.7),
            "color_temperature_range default is [0.3, 0.7], got \(descriptor.colorTemperatureRange)")
    #expect(descriptor.fatigueRisk == .medium,
            "fatigue_risk default is .medium, got \(descriptor.fatigueRisk)")
    #expect(descriptor.transitionAffordances == [.crossfade],
            "transition_affordances default is [.crossfade], got \(descriptor.transitionAffordances)")
    #expect(Set(descriptor.sectionSuitability) == Set(SongSection.allCases),
            "section_suitability default is all cases, got \(descriptor.sectionSuitability)")
    #expect(descriptor.complexityCost == ComplexityCost(tier1: 1.0, tier2: 1.0),
            "complexity_cost default is {1.0, 1.0}, got \(descriptor.complexityCost)")
}

// MARK: - 3. Malformed fatigue_risk

@Test func presetDescriptorMetadata_malformedFatigueRiskFallsBackToMedium() throws {
    let json = """
    { "name": "MalformedRisk", "fatigue_risk": "extreme" }
    """
    // Must not throw — unknown values fall back to .medium with a logged warning.
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.fatigueRisk == .medium,
            "Unknown fatigue_risk 'extreme' should fall back to .medium")
    // The warning is emitted to os.log (Logging.renderer) — not assertable here,
    // but the non-throw behaviour above is the critical contract.
}

// MARK: - 4. ComplexityCost variants

@Test func presetDescriptorMetadata_complexityCostScalarForm() throws {
    let json = """
    { "name": "ScalarCost", "complexity_cost": 1.5 }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.complexityCost.tier1 == 1.5)
    #expect(descriptor.complexityCost.tier2 == 1.5,
            "Scalar form must apply the same value to both tiers")
}

@Test func presetDescriptorMetadata_complexityCostNestedForm() throws {
    let json = """
    { "name": "NestedCost", "complexity_cost": { "tier1": 2.1, "tier2": 0.9 } }
    """
    let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    #expect(descriptor.complexityCost.tier1 == 2.1)
    #expect(descriptor.complexityCost.tier2 == 0.9)
}

// MARK: - 5. On-disk back-fill regression

/// Loads all built-in presets via PresetLoader and asserts that each has a non-default
/// complexity_cost.tier1 (≠ 1.0). This proves the JSON back-fill happened — if any
/// preset loses its metadata, the decoder applies the 1.0 default and this test fails.
@Test func presetDescriptorMetadata_allBuiltInPresetsWereBackFilled() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw MetadataTestError.noMetalDevice
    }

    // PresetLoader(device:pixelFormat:) loads from Bundle.module (the Presets bundle),
    // identical to the production path — so JSON back-fill regressions are caught here.
    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)

    #expect(loader.presets.count >= 3,
            "Expected at least 3 built-in presets; got \(loader.presets.count)")

    var failedPresets: [String] = []
    for preset in loader.presets {
        // complexity_cost.tier1 == 1.0 is the decoder default — means back-fill was lost.
        if preset.descriptor.complexityCost.tier1 == 1.0 {
            failedPresets.append(preset.descriptor.name)
        }
    }

    #expect(failedPresets.isEmpty,
            "Presets missing back-filled complexity_cost: \(failedPresets). Restore their metadata in the corresponding .json sidecar.")
}
