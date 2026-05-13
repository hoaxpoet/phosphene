// StageRigStateLayoutTests — V.9 Session 3 / D-125 layout invariant.
//
// Swift `StageRigState` (208 bytes) and `StageRigLight` (32 bytes) are
// the byte-identical mirrors of the MSL structs declared in both
// `PhospheneEngine/Sources/Renderer/Shaders/Common.metal` (Renderer library)
// and `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift`
// (`rayMarchGBufferPreamble`). They're bound at fragment slot 9 of the
// ray-march G-buffer + lighting passes.
//
// If either Swift struct ever shrinks, the matID == 2 branch in
// `raymarch_lighting_fragment` (RayMarch.metal) over-reads its bound
// buffer — silently on release builds, with undefined values feeding the
// rendered frame. The `RayMarchPipeline.stageRigPlaceholderBuffer` is also
// sized to a hard-coded 208 B literal; this test is the canary that the
// placeholder allocation, the Swift struct, and the MSL structs are
// consistent.
//
// Companion to D-099 `CommonLayoutTest` (FeatureVector / StemFeatures).

import Testing
@testable import Shared

// MARK: - StageRigStateLayoutTests

struct StageRigStateLayoutTests {

    /// Locks Swift `StageRigState` size to D-125(c)'s 208 bytes. If this
    /// trips: update the assertion AND the matching MSL struct in
    /// `Common.metal` + `rayMarchGBufferPreamble` AND the placeholder buffer
    /// size in `RayMarchPipeline.stageRigPlaceholderBuffer`.
    @Test func test_stageRigState_strideIs208() {
        #expect(MemoryLayout<StageRigState>.stride == 208)
    }

    /// Locks Swift `StageRigLight` size to D-125(c)'s 32 bytes (float4 +
    /// float4). If this trips, the per-light fields in the MSL struct have
    /// drifted from the Swift mirror.
    @Test func test_stageRigLight_strideIs32() {
        #expect(MemoryLayout<StageRigLight>.stride == 32)
    }
}
