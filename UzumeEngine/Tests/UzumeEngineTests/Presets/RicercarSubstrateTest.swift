// RicercarSubstrateTest — Ricercar is a particles-pass preset over a deep-ground backdrop.
//
// History: the IFC.6 marks failed live M7 (lag + boring); the RW Skein-recolour was rejected ("just
// Skein — I want Fantasia"); FL.1–FL.9 tried a fluid dye sim + drawn voices (rejected); FL.10 replaced
// the whole medium with an audio-reactive glowing particle flow-field (`RicercarFlowGeometry`). That
// geometry earned a live "fucking brilliant" but was superseded at RICERCAR-WIRE.1 by the fugue-echo
// onset-driven marks (`RicercarEchoGeometry`, docs/presets/RICERCAR_DESIGN.md §FANTASIA REBUILD), which
// certified at RICERCAR-CERT.1 — RicercarFlowGeometry was DELETED there per the exception recorded at
// WIRE.1 ("if the echo preset certifies, delete the flow geometry in that increment"). This file guards
// the preset wiring (particles pass + deep-ground backdrop + registry membership), which is unchanged by
// which geometry backs it. The current
// geometry is covered by RicercarEchoWiringTests (production ShaderLibrary + wiring) and
// MultiPassRenderHarness's "Ricercar" case (RICERCAR-CERT.1, frame-budget + flash-safety gates).

import Testing
import Metal
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Ricercar — particles preset wiring")
@MainActor
struct RicercarSubstrateTest {

    // MARK: - 1. The sidecar is a particles-pass preset with the deep-ground backdrop

    @Test("Ricercar loads as a particles preset backed by a ParticleGeometry registry entry")
    func test_ricercar_isParticlePreset() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarSubstrateTest: no Metal device — skipping"); return
        }
        let preset = try #require(
            _acceptanceFixture.presets.first { $0.descriptor.name == "Ricercar" },
            "Ricercar preset not loaded")
        #expect(preset.descriptor.passes.contains(.particles),
                "Ricercar must declare the particles pass (marks render through ParticleGeometry)")
        #expect(preset.descriptor.fragmentFunction == "ricercar_ground_fragment",
                "Ricercar's backdrop must be the deep-ground fragment (the light-trail covers it)")
        #expect(preset.mvWarpPipelines == nil,
                "Ricercar must NOT compile mv_warp pipelines — the marks/Skein paradigm was rejected 3×")
        #expect(ParticleGeometryRegistry.knownPresetNames.contains("Ricercar"),
                "Ricercar missing from ParticleGeometryRegistry — the app would render backdrop only")
    }
}
