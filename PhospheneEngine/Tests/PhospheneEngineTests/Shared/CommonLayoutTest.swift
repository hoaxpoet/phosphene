// CommonLayoutTest — D-099 layout invariant for buffer(2) / buffer(3) bindings.
//
// Engine library MSL `FeatureVector` and `StemFeatures` (Common.metal) were
// extended in DM.2 to match the Swift sources of truth (192 / 256 bytes).
// If either Swift struct ever shrinks back, every engine kernel that reads
// `f.*` or `stems.*` past the smaller boundary (motes_update's hue baking,
// any future Particles* kernel) over-reads its bound buffer — silently on
// release builds, with undefined values feeding the rendered frame.
//
// This test fails fast at CI time before MSL ever sees the regression. It
// is the Swift-side companion to D-099; locking on the engine MSL side is
// not portable in MSL, so the gate lives here.

import Testing
@testable import Shared

// MARK: - CommonLayoutTest

struct CommonLayoutTest {

    /// Locks Swift `FeatureVector` and `StemFeatures` sizes to the values
    /// Common.metal's MSL structs were extended to in D-099. Failing this
    /// test is the canary that the buffer(2) / buffer(3) layout contract
    /// has drifted between Swift and MSL.
    @Test func featureVector_stemFeatures_layouts_locked() {
        #expect(MemoryLayout<FeatureVector>.size == 192)
        #expect(MemoryLayout<StemFeatures>.size == 256)
    }
}
