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
    static let expectedProductionPresetCount = 15

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
