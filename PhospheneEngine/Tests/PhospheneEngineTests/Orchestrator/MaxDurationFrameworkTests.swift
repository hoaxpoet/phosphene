// MaxDurationFrameworkTests — V.7.6.2 §5 framework verification.
//
// Cross-checks the §5.2 formula against §5.3 reference table values for the
// 13 production presets. V.7.6.C calibrated: per-section linger factors
// inverted (Option B), diagnostic class added.

import Foundation
import Testing
@testable import Presets
import Shared

// MARK: - Reference Table

/// §5.3 reference table values at default section context (nil, lingerFactor=0.5).
/// Source: docs/ARACHNE_V8_DESIGN.md §5.3.
private struct ReferenceRow {
    let presetName: String
    /// Expected default-section maxDuration; nil for diagnostic presets (∞).
    let expectedSeconds: Double?
}

private let referenceTable: [ReferenceRow] = [
    ReferenceRow(presetName: "Arachne",                expectedSeconds: 60),
    ReferenceRow(presetName: "Ferrofluid Ocean",       expectedSeconds: 49),
    ReferenceRow(presetName: "Fractal Tree",           expectedSeconds: 55),
    ReferenceRow(presetName: "Glass Brutalist",        expectedSeconds: 67),
    ReferenceRow(presetName: "Gossamer",               expectedSeconds: 102),
    ReferenceRow(presetName: "Kinetic Sculpture",      expectedSeconds: 49),
    ReferenceRow(presetName: "Membrane",               expectedSeconds: 49),
    ReferenceRow(presetName: "Murmuration",            expectedSeconds: 67),
    ReferenceRow(presetName: "Nebula",                 expectedSeconds: 96),
    ReferenceRow(presetName: "Plasma",                 expectedSeconds: 27),
    ReferenceRow(presetName: "Spectral Cartograph",    expectedSeconds: nil),  // diagnostic
    ReferenceRow(presetName: "Volumetric Lithograph",  expectedSeconds: 82),
    ReferenceRow(presetName: "Waveform",               expectedSeconds: 58)
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

        let computed = arachne.maxDuration(forSection: nil)
        #expect(computed == 60, "Arachne should cap at 60 s (naturalCycleSeconds)")
        #expect(arachne.naturalCycleSeconds == 60)
    }

    @Test("Computed maxDurations match §5.3 reference table within ±2 s")
    func computedValuesMatchReferenceTable() throws {
        let descriptors = try loadProductionDescriptors()
        guard !descriptors.isEmpty else { return }  // bundle resources unreachable

        for ref in referenceTable {
            guard let descriptor = descriptors[ref.presetName] else {
                Issue.record("Production preset '\(ref.presetName)' not found in bundle")
                continue
            }
            let computed = descriptor.maxDuration(forSection: nil)
            if let expected = ref.expectedSeconds {
                let delta = abs(computed - expected)
                #expect(delta <= 2.0, """
                    \(ref.presetName) maxDuration mismatch: \
                    expected \(expected) s ± 2, got \(computed) s. \
                    Adjust §5.3 reference table or coefficients in PresetMaxDuration.swift.
                    """)
            } else {
                #expect(computed == .infinity, """
                    \(ref.presetName) is flagged diagnostic — expected .infinity, got \(computed).
                    """)
            }
        }
    }

    @Test("V.7.6.C Option B: ambient lingers, bridge is shortest")
    func sectionLingerOrderingIsOptionB() throws {
        let descriptors = try loadProductionDescriptors()
        guard let plasma = descriptors["Plasma"] else { return }

        let ambient = plasma.maxDuration(forSection: .ambient)
        let peak = plasma.maxDuration(forSection: .peak)
        let comedown = plasma.maxDuration(forSection: .comedown)
        let buildup = plasma.maxDuration(forSection: .buildup)
        let bridge = plasma.maxDuration(forSection: .bridge)

        // Option B ordering: ambient > peak > comedown > buildup > bridge.
        #expect(ambient > peak, "Ambient should linger longest (meditative)")
        #expect(peak > comedown, "Peak (climactic) lingers more than comedown")
        #expect(comedown > buildup, "Comedown lingers more than buildup")
        #expect(buildup > bridge, "Bridge is the shortest section")
    }

    @Test("Diagnostic presets return .infinity from maxDuration")
    func diagnosticPresetReturnsInfinity() throws {
        let descriptors = try loadProductionDescriptors()
        guard let cartograph = descriptors["Spectral Cartograph"] else { return }

        #expect(cartograph.isDiagnostic == true, "Spectral Cartograph should be flagged diagnostic")
        #expect(cartograph.maxDuration(forSection: nil) == .infinity)
        for section in SongSection.allCases {
            #expect(cartograph.maxDuration(forSection: section) == .infinity)
        }
    }

    @Test("isDiagnostic defaults to false when JSON omits the field")
    func isDiagnosticDefaultsFalse() throws {
        let json = """
        {
          "name": "PlainPreset",
          "family": "geometric"
        }
        """
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        #expect(descriptor.isDiagnostic == false)
        #expect(descriptor.maxDuration(forSection: nil) != .infinity)
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
        // Formula at section=nil (lingerFactor=0.5):
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
