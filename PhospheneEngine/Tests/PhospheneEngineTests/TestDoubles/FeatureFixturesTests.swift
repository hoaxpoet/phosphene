// FeatureFixturesTests — proves the CLEAN.7.2b builders are a safe drop-in for inline
// construction: with no overrides they are BYTE-IDENTICAL to the struct's own init (so
// migrating a call site can't silently change a test's meaning), and overrides land on
// the right field. This is the verifying consumer that justifies the shared builders.

import Foundation
import Testing
@testable import Shared

@Suite("Shared test fixture builders (CLEAN.7.2b)")
struct FeatureFixturesTests {

    /// @frozen, SIMD-aligned value types → a raw byte compare is a total field compare.
    private func bytesEqual<T>(_ a: T, _ b: T) -> Bool {
        withUnsafeBytes(of: a) { ab in withUnsafeBytes(of: b) { bb in
            ab.elementsEqual(bb)
        } }
    }

    @Test("makeFeatureVector() is byte-identical to FeatureVector()")
    func featureVectorDefaultsMatchInit() {
        #expect(bytesEqual(FeatureFixtures.makeFeatureVector(), FeatureVector()))
    }

    @Test("makeFeatureVector core override matches the hand-built construct-then-keep")
    func featureVectorCoreOverride() {
        let built = FeatureFixtures.makeFeatureVector(bass: 0.5, mid: 0.3, valence: -0.2)
        let hand = FeatureVector(bass: 0.5, mid: 0.3, valence: -0.2)
        #expect(bytesEqual(built, hand))
    }

    @Test("makeFeatureVector deviation + beat overrides match construct-then-mutate")
    func featureVectorExtendedOverride() {
        let built = FeatureFixtures.makeFeatureVector(bass: 0.5, bassDev: 0.4, beatPhase01: 0.2)
        var hand = FeatureVector(bass: 0.5)
        hand.bassDev = 0.4
        hand.beatPhase01 = 0.2
        #expect(bytesEqual(built, hand))
        // And the fields actually carry the values (not just equal-to-each-other).
        #expect(built.bassDev == 0.4)
        #expect(built.beatPhase01 == 0.2)
        #expect(built.beatsPerBar == 4)   // default preserved
        #expect(built.aspectRatio == 1.777)
    }

    @Test("makeStemFeatures() is byte-identical to StemFeatures()")
    func stemFeaturesDefaultsMatchInit() {
        #expect(bytesEqual(FeatureFixtures.makeStemFeatures(), StemFeatures()))
    }

    @Test("makeStemFeatures dev overrides match construct-then-mutate")
    func stemFeaturesExtendedOverride() {
        let built = FeatureFixtures.makeStemFeatures(drumsEnergy: 0.6, drumsEnergyDev: 0.5, otherEnergyDev: 0.3)
        var hand = StemFeatures(drumsEnergy: 0.6)
        hand.drumsEnergyDev = 0.5
        hand.otherEnergyDev = 0.3
        #expect(bytesEqual(built, hand))
        #expect(built.drumsEnergyDev == 0.5)
        #expect(built.otherEnergyDev == 0.3)
    }
}
