// RicercarSubstrateTest — RICERCAR-FL.10: Ricercar is the particle flow-field preset.
//
// History: the IFC.6 marks failed live M7 (lag + boring); the RW Skein-recolour was rejected ("just
// Skein — I want Fantasia"); FL.1–FL.9 tried a fluid dye sim + drawn voices (rejected); FL.10 replaced
// the whole medium with an audio-reactive glowing particle flow-field (`RicercarFlowGeometry`,
// docs/presets/RICERCAR_DESIGN.md §FANTASIA REBUILD). This file guards the preset wiring (particles pass
// + deep-ground backdrop + registry membership). Test 2 still guards the SkeinState `colorFromFamily`
// engine feature (no longer used by any preset after FL.10 — a follow-up removal candidate). The flow
// field itself is covered by RicercarFlowRenderTests + RicercarFluidVideoHarness (live dispatch path).

import Testing
import Metal
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Ricercar-FL — particle flow-field preset + SkeinState family-colour mode")
@MainActor
struct RicercarSubstrateTest {

    /// The family palette Ricercar feeds SkeinState (mirror of VisualizerEngine.ricercarFamilyPalette,
    /// InstrumentFamily.allCases order: strings, brass, woodwinds, percussion).
    static let familyPalette: [SIMD3<Float>] = [
        SIMD3(0.34, 0.24, 0.64), SIMD3(0.88, 0.62, 0.16),
        SIMD3(0.76, 0.38, 0.18), SIMD3(0.13, 0.60, 0.66)
    ]

    // MARK: - 1. The sidecar is the particle flow-field preset (FL.10)

    @Test("Ricercar loads as a particles preset backed by the flow-field geometry registry entry")
    func test_ricercar_isFlowParticlePreset() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarSubstrateTest: no Metal device — skipping"); return
        }
        let preset = try #require(
            _acceptanceFixture.presets.first { $0.descriptor.name == "Ricercar" },
            "Ricercar preset not loaded")
        #expect(preset.descriptor.passes.contains(.particles),
                "Ricercar must declare the particles pass (flow field renders through ParticleGeometry)")
        #expect(preset.descriptor.fragmentFunction == "ricercar_ground_fragment",
                "Ricercar's backdrop must be the deep-ground fragment (the light-trail covers it)")
        #expect(preset.mvWarpPipelines == nil,
                "Ricercar must NOT compile mv_warp pipelines — the marks/Skein paradigm was rejected 3×")
        #expect(ParticleGeometryRegistry.knownPresetNames.contains("Ricercar"),
                "Ricercar missing from ParticleGeometryRegistry — the app would render backdrop only")
    }

    // MARK: - 2. Family-mode SkeinState: colour locks onto the dominant family

    @Test("Family mode: the pour colour locks onto the fed dominant instrument family")
    func test_familyMode_colourTracksDominantFamily() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("RicercarSubstrateTest: no Metal device — skipping"); return
        }
        let state = try #require(
            SkeinState(device: device, seed: 0, palette: Self.familyPalette, colorFromFamily: true),
            "family-mode SkeinState failed to allocate")

        // Feed frames where WOODWINDS (family index 2) clearly leads by deviation, over real stem
        // energy (so the painter clock advances + a pour commits). ~4 s at 60 fps.
        var stem = StemFeatures.zero
        stem.otherEnergy = 0.5; stem.drumsEnergy = 0.3                    // stem mix > 0 → the painter paints
        stem.woodwindsActivity = 0.55; stem.woodwindsActivityDev = 0.6   // the clear family lead
        stem.stringsActivity = 0.15; stem.stringsActivityDev = 0.05
        let dt: Float = 1.0 / 60.0
        for i in 0..<240 {
            let f = FeatureVector(time: Float(i) * dt, deltaTime: dt, aspectRatio: 16.0 / 9.0)
            state.tick(deltaTime: dt, features: f, stems: stem)          // must not crash
        }
        // The committed pour must be the WOODWINDS family (index 2) — colour ← family, the RW contract.
        #expect(state.lineDominantStem == 2,
                "pour colour should lock onto the dominant family (woodwinds=2), got \(state.lineDominantStem)")
    }
}
