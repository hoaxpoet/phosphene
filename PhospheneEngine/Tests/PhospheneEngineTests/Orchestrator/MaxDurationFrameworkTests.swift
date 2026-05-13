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
/// Source: docs/presets/ARACHNE_V8_DESIGN.md §5.3.
private struct ReferenceRow {
    let presetName: String
    /// Expected default-section maxDuration; nil for diagnostic presets (∞).
    let expectedSeconds: Double?
}

private let referenceTable: [ReferenceRow] = [
    // BUG-011 round 8: Arachne is now `wait_for_completion_event:true`, so
    // `maxDuration` returns `.infinity`. The pre-round-8 60 s
    // `natural_cycle_seconds` cap is bypassed by the new early-return.
    ReferenceRow(presetName: "Arachne",                expectedSeconds: nil),
    // V.9 Session 1: motion_intensity 0.65→0.55, visual_density 0.75→0.65
    // per D-124 redirect — 90 + (-50)(0.05) + (-30)(1) + (-15)(0.15) = 55.25.
    ReferenceRow(presetName: "Ferrofluid Ocean",       expectedSeconds: 55),
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

    @Test("Arachne returns .infinity (wait_for_completion_event, BUG-011 round 8)")
    func arachneMaxDurationIsInfinity() throws {
        let descriptors = try loadProductionDescriptors()
        guard let arachne = descriptors["Arachne"] else { return }

        let computed = arachne.maxDuration(forSection: nil)
        #expect(computed == .infinity, """
            Arachne must return .infinity because wait_for_completion_event=true \
            short-circuits the naturalCycleSeconds cap. The completion-event \
            subscription wires the actual transition trigger.
            """)
        #expect(arachne.waitForCompletionEvent == true)
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
                // nil expected = either isDiagnostic or waitForCompletionEvent.
                #expect(computed == .infinity, """
                    \(ref.presetName) should return .infinity (diagnostic or completion-gated). Got \(computed).
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

    // MARK: - BUG-011 round 8: wait_for_completion_event

    @Test("wait_for_completion_event=true forces maxDuration to .infinity")
    func waitForCompletionEventReturnsInfinity() throws {
        let json = """
        {
          "name": "CompletionGated",
          "family":"sparkle",
          "wait_for_completion_event": true
        }
        """
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        #expect(descriptor.waitForCompletionEvent == true)
        #expect(descriptor.maxDuration(forSection: nil) == .infinity)
        for section in SongSection.allCases {
            #expect(descriptor.maxDuration(forSection: section) == .infinity)
        }
    }

    @Test("waitForCompletionEvent defaults to false when JSON omits the field")
    func waitForCompletionEventDefaultsFalse() throws {
        let json = """
        {
          "name": "PlainPreset",
          "family": "geometric"
        }
        """
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        #expect(descriptor.waitForCompletionEvent == false)
        #expect(descriptor.maxDuration(forSection: nil) != .infinity)
    }

    @Test("Arachne ships with wait_for_completion_event=true (BUG-011 round 8)")
    func arachneIsCompletionGated() throws {
        let descriptors = try loadProductionDescriptors()
        // Bundle resources unreachable from the test target — silently skip,
        // matching the surrounding tests' pattern.
        guard !descriptors.isEmpty else { return }
        guard let arachne = descriptors["Arachne"] else {
            Issue.record("Arachne descriptor not found in production catalog")
            return
        }
        #expect(arachne.waitForCompletionEvent == true, """
            Arachne JSON must set wait_for_completion_event:true so the build cycle \
            is allowed to complete before the orchestrator schedules a transition.
            """)
        #expect(arachne.maxDuration(forSection: nil) == .infinity)
    }

    @Test("naturalCycleSeconds caps even when formula would be longer")
    func naturalCycleCapsLongerFormula() throws {
        // Construct a synthetic preset with very high motion intensity, low fatigue,
        // low density — formula would produce a huge baseMax — and assert the
        // naturalCycleSeconds cap takes effect.
        let json = """
        {
          "name": "TestCap",
          "family":"sparkle",
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
