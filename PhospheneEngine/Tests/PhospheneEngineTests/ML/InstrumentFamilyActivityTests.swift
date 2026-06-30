// InstrumentFamilyActivityTests — IFC.3 class→family mapping, smoothing, D-026 deviation.
//
// Validates the taxonomy agrees with the Python reference (the single source of
// truth, cross-checked against the committed fixtures), that raw per-family
// activity reproduces the reference family values exactly, and that the
// deviation tracker has the D-026 properties (seed→0, step-up→positive,
// constant→decays to 0, reset).

import Foundation
import Testing
@testable import ML

@Suite struct InstrumentFamilyActivityTests {

    struct WindowsDoc: Decodable {
        let family_indices: [String: [Int]]   // swiftlint:disable:this identifier_name
        let windows: [Window]
        struct Window: Decodable {
            let tag: String
            let t: Double
            let probs: [Float]
            let family: [String: Float]
        }
    }

    static func loadWindows() throws -> WindowsDoc {
        let url = try #require(Bundle.module.url(
            forResource: "windows", withExtension: "json", subdirectory: "panns_reference"))
        return try JSONDecoder().decode(WindowsDoc.self, from: Data(contentsOf: url))
    }

    /// 527-class probs with one family's AudioSet classes set to `value`, rest 0.
    static func probs(_ family: InstrumentFamily, _ value: Float) -> [Float] {
        var out = [Float](repeating: 0, count: PANNsMobileNetV1.classCount)
        for i in family.audioSetClasses { out[i] = value }
        return out
    }

    // MARK: - Taxonomy agrees with the Python reference

    @Test func test_taxonomy_matchesReferenceFixture() throws {
        let doc = try Self.loadWindows()
        for family in InstrumentFamily.allCases {
            let swift = family.audioSetClasses.sorted()
            let reference = try #require(doc.family_indices[family.rawValue]).sorted()
            #expect(swift == reference, "taxonomy drift for \(family.rawValue): \(swift) vs \(reference)")
        }
    }

    // MARK: - Raw activity reproduces the reference exactly

    @Test func test_rawActivity_matchesReference() throws {
        let doc = try Self.loadWindows()
        var worst: Float = 0
        for window in doc.windows {
            let raw = InstrumentFamily.rawActivity(probs: window.probs)
            for family in InstrumentFamily.allCases {
                let got = raw[family.index]
                let ref = window.family[family.rawValue] ?? 0
                worst = max(worst, abs(got - ref))
                #expect(abs(got - ref) < 1e-6, "\(family.rawValue) @ \(window.tag)@\(window.t): \(got) vs \(ref)")
            }
        }
        print("raw-activity worst abs diff vs reference = \(worst)")
    }

    // MARK: - Deviation properties (D-026)

    @Test func test_firstWindowDeviationIsZero() {
        var tracker = InstrumentFamilyTracker()
        let out = tracker.derive(probs: Self.probs(.brass, 0.6))
        #expect(out.dev.allSatisfy { abs($0) < 1e-6 }, "first window seeds → dev 0")
        #expect(out[.brass].raw == 0.6)
    }

    @Test func test_stepUpProducesPositiveDeviation() {
        var tracker = InstrumentFamilyTracker()
        // Establish a low baseline for brass, then spike.
        for _ in 0..<20 { _ = tracker.derive(probs: Self.probs(.brass, 0.05)) }
        let spike = tracker.derive(probs: Self.probs(.brass, 0.9))
        #expect(spike[.brass].dev > 0.1, "brass spike above its running mean → positive dev (\(spike[.brass].dev))")
        // A silent family stays at zero dev.
        #expect(spike[.strings].dev < 1e-6)
    }

    @Test func test_constantInputDeviationDecaysToZero() {
        var tracker = InstrumentFamilyTracker()
        var last = tracker.derive(probs: Self.probs(.woodwinds, 0.5))
        for _ in 0..<200 { last = tracker.derive(probs: Self.probs(.woodwinds, 0.5)) }
        #expect(abs(last[.woodwinds].dev) < 1e-3, "constant input → running mean catches up → dev ≈ 0")
        #expect(abs(last[.woodwinds].smoothed - 0.5) < 1e-3, "smoothed converges to the constant")
    }

    @Test func test_smoothingDampsSingleWindowJump() {
        var tracker = InstrumentFamilyTracker()
        _ = tracker.derive(probs: Self.probs(.strings, 0.2))      // seeds smoothEMA = 0.2
        let out = tracker.derive(probs: Self.probs(.strings, 1.0)) // EMA, not the full jump
        let s = out[.strings].smoothed
        #expect(s > 0.2 && s < 1.0, "smoothed sits between (\(s))")
        #expect(abs(s - (0.2 * 0.5 + 1.0 * 0.5)) < 1e-6, "EMA with decay 0.5")
    }

    @Test func test_resetClearsState() {
        var tracker = InstrumentFamilyTracker()
        for _ in 0..<10 { _ = tracker.derive(probs: Self.probs(.percussion, 0.4)) }
        tracker.reset()
        let out = tracker.derive(probs: Self.probs(.percussion, 0.4))
        #expect(out.dev.allSatisfy { abs($0) < 1e-6 }, "after reset the next window seeds → dev 0")
    }
}
