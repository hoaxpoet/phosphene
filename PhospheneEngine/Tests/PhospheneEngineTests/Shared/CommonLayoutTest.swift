// CommonLayoutTest — D-099 layout invariant for buffer(0) / buffer(3) bindings.
//
// Swift `FeatureVector` (192 bytes / 48 floats) and `StemFeatures`
// (256 bytes / 64 floats) are bound directly to MSL preset preambles
// (PresetLoader+Preamble.swift) and to the engine library Common.metal.
// If either Swift struct ever shrinks, every shader that reads past the
// smaller boundary over-reads its bound buffer — silently on release
// builds, with undefined values feeding the rendered frame.
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
