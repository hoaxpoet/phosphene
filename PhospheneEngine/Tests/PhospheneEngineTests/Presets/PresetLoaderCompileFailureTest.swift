// PresetLoaderCompileFailureTest — Catches Failed Approach #44 silent drops.
//
// PresetLoader compiles every .metal shader in the bundled Shaders/ directory at
// init time. If a shader fails to compile (e.g. someone introduces a Metal compiler
// error), the loader logs the failure and continues — the preset is silently dropped
// from `presets`. There is no test-time signal that anything has gone wrong, and
// downstream regression tests pass trivially because the broken preset is no longer
// reached. This is exactly the trap Failed Approach #44 (`int half = ...` shadowing
// the Metal `half` type) caught after the fact.
//
// This test asserts `presets.count == expectedProductionPresetCount` on a fresh
// loader. A drop in count without a corresponding decision in `docs/DECISIONS.md`
// AND a bump to the expected count means a preset was silently lost.
//
// **Verification (done at QR.3 land)**: temporarily edited
// `Sources/Presets/Shaders/Plasma.metal` to add `int half = 1;` (the same Metal
// compiler error that motivated Failed Approach #44 — shadows the `half` type).
// Loader count dropped from 14 → 13 and this test failed with a count mismatch
// pointing at Failed Approach #44. Plasma was used because the original
// instructions referenced Stalker.metal but Stalker is no longer in production.
// To re-verify after future preset churn: pick any production .metal, add
// `int half = 1;` inside a function body, run this test, confirm fail, revert.

import Testing
import Metal
@testable import Presets

@Suite("PresetLoaderCompileFailure")
struct PresetLoaderCompileFailureTest {

    /// Expected production preset count. Update this number whenever a preset is
    /// added or retired AND a corresponding decision is recorded in
    /// `docs/DECISIONS.md`. A drop in this number without a decision means a
    /// preset was silently dropped from the fixture — Failed Approach #44 territory.
    ///
    /// History: 14 → 15 at DM.1 (Drift Motes, D-097 / D-099). 15 → 16 at LM.1
    /// (Lumen Mosaic, D-LM-matid). 16 → 15 when Drift Motes was retired.
    /// 15 → 16 at AV.1 (Aurora Veil — direct-fragment + mv_warp ambient
    /// ribbon preset, lightweight rubric). 16 → 17 at Dragon Bloom Spike 1
    /// (D-135) — Milkdrop-uplift feedback bloom (direct + mv_warp). 17 → 18 at
    /// FM.L1 (Fata Morgana — butterchurn mirage port: custom warp + comp + blur,
    /// direct + mv_warp; D-139). Not yet certified (mirage substrate, shapes L2).
    /// 18 → 19 at NB.1 (Nimbus — first `volumetric`-family preset; single-pass
    /// direct-fragment volumetric ray-march composing the V.2 Volume tree; the
    /// `volumetric` PresetCategory case was Matt-authorized 2026-06-04). Not yet
    /// certified (NB.1 macro maquette; cert at NB.9).
    /// 19 → 20 at Skein.ENGINE.1 (Skein — canvas-hold accumulation skeleton:
    /// the no-decay / identity config of the mv_warp brush-on-feedback paradigm,
    /// D-142; direct + mv_warp). ENGINE.1 ships an identity-warp recipe + a fixed
    /// test stamp only — no audio/marks/family yet (family `painterly` + emission
    /// at Skein.1+). Not certified.
    /// 20 → 21 at NACRE.2b (Nacre — faithful port of `$$$ Royal - Mashup (431)`'s
    /// iridescent jello-mirror onto the custom-warp+comp mv_warp branch; direct +
    /// mv_warp, HDR feedback). Family `hypnotic`. Not certified (cert at NACRE.4 after
    /// Matt's live M7). NACRE.2a added the preset to the catalog but did not bump this.
    /// 21 → 22 at FLORET.2a (Floret — port of butterchurn `Sunflower Passion` onto the
    /// same custom-warp+comp mv_warp branch; direct + mv_warp, HDR feedback; family
    /// `hypnotic`). Certified at FLORET.4.
    /// 22 → 23 at PHYS.2 (Filigree — physarum agent-network graduated from the throwaway
    /// sketch; family `particles`, `PhysarumGeometry` conformer). Not certified (cert at
    /// PHYS.5 after Matt's live M7, per the Nacre precedent). See docs/presets/FILIGREE_DESIGN.md.
    /// 23 → 24 at GLAZE.2a (Glaze — port of `Flexi + stahlregen - jelly showoff parade`'s
    /// glossy contour-gel onto a dedicated mv_warp branch; direct + mv_warp, HDR feedback;
    /// family `hypnotic`). Certified at GLAZE.8.
    /// 24 → 25 at MITOSIS.1 (Mitosis — Gray–Scott reaction–diffusion cell colony graduated
    /// from its throwaway sketch; family `particles`, `MitosisGeometry` conformer). Not
    /// certified (cert at MITOSIS.4 after Matt's live sync listen + M7). See
    /// docs/presets/MITOSIS_DESIGN.md.
    /// 26: Cytokinesis (Mitosis gen-2 — detailed explicit-cell division, family `particles`,
    /// `MitosisGen2Geometry` conformer; certified:false, cert at MITOSIS-G2.3). See
    /// docs/presets/MITOSIS_GEN2_DESIGN.md.
    /// 27: Ricercar (Fantasia rebuild — audio-reactive glowing particle flow-field, Magnetosphere
    /// lineage, family `painterly`, `RicercarFlowGeometry` conformer; the marks/Skein + fluid-dye
    /// paradigms were rejected. Uncertified — FL.10 look + M7 pending). See docs/presets/RICERCAR_DESIGN.md
    /// §FANTASIA REBUILD.
    /// 27 → 26 at GBRETIRE.1 (Glass Brutalist retired — ray-march "brutalist corridor"
    /// concept fails the viability gate: D-020 makes the concrete deliberately audio-static
    /// so the hero subject can never be an instrument. See docs/DECISIONS.md D-186.)
    /// 26 → 25 at KSRETIRE.1 (Kinetic Sculpture retired — after multiple redesigns the
    /// preset never found the right direction; a fresh psychedelic-geometry preset will be
    /// authored separately. Phase RMENV engine work is retained. See docs/DECISIONS.md D-188.)
    /// 25 → 26 at PG.4.1 (Truchet Loom — multiscale curved-Truchet op-art weave whose
    /// subdivision depth tracks smoothed spectral_flux; direct pass, family `geometric`.
    /// The first Phase PG psychedelic-geometry preset. Not certified — reviewable v1, cert
    /// after Matt's live M7; D-189/190/191 for PG.4.1/4.2/4.3.) See
    /// docs/presets/psychedelic_geometry/PG_4_TRUCHET_LOOM.md.
    static let expectedProductionPresetCount = 26

    @Test("PresetLoader.presets.count matches expectedProductionPresetCount — catches Failed Approach #44 silent drops")
    func test_presetLoaderProductionCount() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("PresetLoaderCompileFailureTest: no Metal device — skipping")
            return
        }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        #expect(loader.presets.count == Self.expectedProductionPresetCount, """
            Production preset count is \(loader.presets.count); expected \
            \(Self.expectedProductionPresetCount). If you added or retired a preset, \
            update expectedProductionPresetCount AND log a decision in docs/DECISIONS.md. \
            If you did not, a shader is silently failing to compile — see Failed Approach #44.
            """)
    }
}
