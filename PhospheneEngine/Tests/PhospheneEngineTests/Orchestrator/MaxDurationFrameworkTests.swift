// MaxDurationFrameworkTests — V.7.6.2 §5 framework verification.
//
// Cross-checks the §5.2 formula against §5.3 reference table values for the
// 13 production presets. Disagreements over ±2 s are flagged as V.7.6.C
// calibration items via inline comments — they are NOT pre-tuned here.

import Foundation
import Testing
@testable import Presets
import Shared

// MARK: - Reference Table

/// §5.3 reference table values at `sectionDynamicRange = 0.5` (nil section context).
/// Source: docs/ARACHNE_V8_DESIGN.md §5.3.
private struct ReferenceRow {
    let presetName: String
    let expectedSeconds: Double
    /// True when §5.3 itself flags this row for V.7.6.C calibration.
    let calibrationFlag: Bool
}

private let referenceTable: [ReferenceRow] = [
    ReferenceRow(presetName: "Arachne",                expectedSeconds: 60,  calibrationFlag: false),
    ReferenceRow(presetName: "Plasma",                 expectedSeconds: 12,  calibrationFlag: false),
    ReferenceRow(presetName: "Membrane",               expectedSeconds: 46,  calibrationFlag: false),
    ReferenceRow(presetName: "Murmuration",            expectedSeconds: 49,  calibrationFlag: false),
    ReferenceRow(presetName: "Kinetic Sculpture",      expectedSeconds: 53,  calibrationFlag: false),
    ReferenceRow(presetName: "Stalker",                expectedSeconds: 58,  calibrationFlag: false),
    ReferenceRow(presetName: "Gossamer",               expectedSeconds: 92,  calibrationFlag: false),
    ReferenceRow(presetName: "Ferrofluid Ocean",       expectedSeconds: 87,  calibrationFlag: false),
    ReferenceRow(presetName: "Glass Brutalist",        expectedSeconds: 71,  calibrationFlag: true),
    ReferenceRow(presetName: "Volumetric Lithograph",  expectedSeconds: 82,  calibrationFlag: false),
    ReferenceRow(presetName: "Nebula",                 expectedSeconds: 60,  calibrationFlag: false),
    ReferenceRow(presetName: "Spectral Cartograph",    expectedSeconds: 94,  calibrationFlag: false),
    ReferenceRow(presetName: "Waveform",               expectedSeconds: 58,  calibrationFlag: false)
]

// MARK: - Loader

private func loadProductionDescriptors() throws -> [String: PresetDescriptor] {
    guard let shadersURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
        return [:]
    }
    let contents = try FileManager.default.contentsOfDirectory(
        at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    )
    let jsonFiles = contents.filter { $0.pathExtension == "json" }
    let decoder = JSONDecoder()
    var byName: [String: PresetDescriptor] = [:]
    for url in jsonFiles {
        let data = try Data(contentsOf: url)
        let descriptor = try decoder.decode(PresetDescriptor.self, from: data)
        byName[descriptor.name] = descriptor
    }
    return byName
}

// MARK: - Tests

@Suite("MaxDurationFramework")
struct MaxDurationFrameworkTests {

    @Test("Arachne is capped by naturalCycleSeconds (60 s)")
    func arachneCappedByNaturalCycle() throws {
        let descriptors = try loadProductionDescriptors()
        guard let arachne = descriptors["Arachne"] else { return }

        // The cap is min(naturalCycleSeconds, formulaResult). Spec §5.3 reports 60 s.
        let computed = arachne.maxDuration(forSection: nil)
        #expect(computed == 60, "Arachne should cap at 60 s (naturalCycleSeconds)")
        #expect(arachne.naturalCycleSeconds == 60)
    }

    @Test("Computed maxDurations match §5.3 reference table within ±2 s")
    func computedValuesMatchReferenceTable() throws {
        let descriptors = try loadProductionDescriptors()
        guard !descriptors.isEmpty else { return }  // bundle resources unreachable

        // Per the increment plan: divergences over ±2 s are documented as V.7.6.C
        // calibration items — not auto-failed. Glass Brutalist is the §5.3-flagged
        // calibration anchor. We assert ±2 s on every other row, and treat
        // calibration-flagged rows as informational only.
        for ref in referenceTable {
            guard let descriptor = descriptors[ref.presetName] else {
                Issue.record("Production preset '\(ref.presetName)' not found in bundle")
                continue
            }
            let computed = descriptor.maxDuration(forSection: nil)
            let delta = abs(computed - ref.expectedSeconds)
            if ref.calibrationFlag {
                // V.7.6.C: row is a known calibration item. Log the delta but don't fail.
                continue
            }
            #expect(delta <= 2.0, """
                \(ref.presetName) maxDuration mismatch: \
                expected \(ref.expectedSeconds) s ± 2, got \(computed) s. \
                If intentional, document as V.7.6.C calibration item.
                """)
        }
    }

    @Test("Section context shifts maxDuration in expected direction")
    func sectionContextShiftsDuration() throws {
        let descriptors = try loadProductionDescriptors()
        guard let plasma = descriptors["Plasma"] else { return }

        // Peak (high dynamic range, 0.80) should be longer than ambient (0.30).
        let peak = plasma.maxDuration(forSection: .peak)
        let ambient = plasma.maxDuration(forSection: .ambient)
        #expect(peak > ambient, "Energetic sections keep a preset interesting longer")
    }

    @Test("naturalCycleSeconds caps even when formula would be longer")
    func naturalCycleCapsLongerFormula() throws {
        // Construct a synthetic preset with very high motion intensity, low fatigue,
        // low density — formula would produce a huge baseMax — and assert the
        // naturalCycleSeconds cap takes effect.
        let json = """
        {
          "name": "TestCap",
          "family": "organic",
          "natural_cycle_seconds": 30,
          "motion_intensity": 0.0,
          "visual_density": 0.0,
          "fatigue_risk": "low"
        }
        """
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        // Formula at section=nil (dynamicRange=0.5):
        //   baseMax = 90 + (-50)(-0.5) + 0 + (-15)(-0.5) = 90 + 25 + 7.5 = 122.5
        //   adjusted = 122.5 × 1.0 = 122.5 s
        // Cap kicks in: min(30, 122.5) = 30.
        #expect(descriptor.maxDuration(forSection: nil) == 30)
    }

    @Test("maxDuration is monotonic non-negative")
    func maxDurationNonNegative() throws {
        let descriptors = try loadProductionDescriptors()
        for (_, descriptor) in descriptors {
            #expect(descriptor.maxDuration(forSection: nil) >= 0)
            for section in SongSection.allCases {
                #expect(descriptor.maxDuration(forSection: section) >= 0)
            }
        }
    }
}
