// RicercarSubstrateTest — RICERCAR-RW: Ricercar rebuilt on Skein's painter engine, family-coloured.
//
// The IFC.6 per-section mark shader (ricercar_geometry_*) FAILED live M7 (lines lagged the music; the
// paint read as a fat line + speckles; boring — see docs/presets/RICERCAR_DESIGN.md §IFC.6). Ricercar
// now REUSES Skein's proven painter engine (audio-modulated painterTau clock + onset-burst splatter +
// rich marks) via `fragment_function: skein_fragment`, with the pour/burst COLOUR driven by the dominant
// instrument FAMILY instead of the dominant stem (`SkeinState(colorFromFamily: true)` + a family palette).
// The rich-marks / sync / canvas-hold behaviour is covered by SkeinCanvasHoldTest (same engine); this
// file guards the RW-specific wiring + family-colour contract.

import Testing
import Metal
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Ricercar-RW — Skein engine, family-coloured")
@MainActor
struct RicercarSubstrateTest {

    /// The family palette Ricercar feeds SkeinState (mirror of VisualizerEngine.ricercarFamilyPalette,
    /// InstrumentFamily.allCases order: strings, brass, woodwinds, percussion).
    static let familyPalette: [SIMD3<Float>] = [
        SIMD3(0.34, 0.24, 0.64), SIMD3(0.88, 0.62, 0.16),
        SIMD3(0.76, 0.38, 0.18), SIMD3(0.13, 0.60, 0.66)
    ]

    // MARK: - 1. The sidecar reuses Skein's engine

    @Test("Ricercar loads and resolves Skein's geometry pipeline (skein_fragment reuse)")
    func test_ricercar_reusesSkeinGeometry() throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("RicercarSubstrateTest: no Metal device — skipping"); return
        }
        let preset = try #require(
            _acceptanceFixture.presets.first { $0.descriptor.name == "Ricercar" },
            "Ricercar preset not loaded")
        #expect(preset.descriptor.fragmentFunction == "skein_fragment",
                "Ricercar must reuse Skein's shader (family-coloured sibling)")
        let warp = try #require(preset.mvWarpPipelines, "Ricercar mvWarpPipelines nil — passes misconfigured")
        #expect(warp.sceneGeometryState != nil,
                "skein_geometry_* not resolved for Ricercar — the marks-on-top overlay is missing")
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
