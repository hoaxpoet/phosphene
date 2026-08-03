// WitchlightSkyLuminanceTests — the backdrop must read as deep space, measurably.
//
// Matt's M7 verdict on the first live session was "it looks nothing like the original
// preset it was supposed to be based on", and the dominant term was the backdrop: the
// star field washed the frame to a milky grey while the source is genuinely black with a
// ribbon in it. Measured on the same frame size:
//
//     source render (`00`)   mean luma 10.6   lit (>40) 4.0%
//     shipped Witchlight     mean luma 31.5   lit (>40) 17.5%
//
// Three times the background brightness and four times the lit-pixel share. That single
// difference is most of why it read as a different preset — and nothing measured it,
// because every existing gate looks at audio→visual coupling, not at whether the frame
// looks like the register it committed to.
//
// So this is a plain image-statistics gate on the backdrop, held against the source
// render's own numbers. It is deliberately generous (the bands are wide) because the
// point is to catch a 4× regression, not to police taste.
//
// `07` in the reference set IS a dense star field — density is not the defect. Star SIZE
// is: sub-pixel-to-2px points leave the field reading black no matter how many there are,
// while fat ones wash it out. The assertions below are on luminance, which is what the
// eye actually integrates, rather than on a star count.

import Foundation
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@MainActor
@Suite("Witchlight backdrop luminance (WL.2-e)")
struct WitchlightSkyLuminanceTests {

    /// Measured from Matt's render of the inspiration source, 760×428.
    private static let sourceMeanLuma = 10.6
    private static let sourceLitShare = 4.0     // % of pixels above 40/255

    /// Bands: within ~2× of the source on the mean, and no more than ~2.5× its lit share.
    /// Wide on purpose — the shipped value was 3× and 4.4× out, which is the class of
    /// regression worth failing on.
    private static let maxMeanLuma = 22.0
    private static let maxLitShare = 10.0

    @Test("The deep-space backdrop reads black, not milky (WL.2-e)")
    func backdropReadsAsDeepSpace() throws {
        let harness = MultiPassRenderHarness(width: 640, height: 360)

        // A short silent-ish drive: the backdrop is procedural and audio-independent in
        // its base level (D-037), so this measures the field itself rather than a
        // particular musical moment. The stroke is present but occupies ~1 % of frame.
        var features = [FeatureVector]()
        for i in 0..<90 {
            var f = FeatureVector()
            f.deltaTime = 1.0 / 60
            f.time = Float(i) / 60
            f.bass = 0.3; f.mid = 0.3; f.treble = 0.2
            f.spectralCentroid = 0.12          // mid of the measured 0.04–0.21 band
            f.valence = 0.2
            f.aspectRatio = 640.0 / 360.0
            features.append(f)
        }
        let stems = [StemFeatures](repeating: StemFeatures(), count: features.count)

        let frames: [[UInt8]] = try harness.render(
            preset: "Witchlight", features: features, stems: stems, settle: 0) { $0 }
        let last = try #require(frames.last, "no frame rendered")

        var sum = 0.0
        var lit = 0
        let pixels = last.count / 4
        for i in stride(from: 0, to: last.count, by: 4) {
            // BGRA → Rec.601 luma, matching how the source render was measured.
            let luma = 0.114 * Double(last[i]) + 0.587 * Double(last[i + 1]) + 0.299 * Double(last[i + 2])
            sum += luma
            if luma > 40 { lit += 1 }
        }
        let mean = sum / Double(pixels)
        let litShare = 100.0 * Double(lit) / Double(pixels)

        print(String(format: "[sky] mean luma %.2f (source %.1f, ceiling %.1f) | lit %.2f%% (source %.1f%%, ceiling %.1f%%)",
                     mean, Self.sourceMeanLuma, Self.maxMeanLuma,
                     litShare, Self.sourceLitShare, Self.maxLitShare))

        #expect(mean <= Self.maxMeanLuma, """
            backdrop mean luma \(String(format: "%.2f", mean)) exceeds \(Self.maxMeanLuma) — \
            the field is washing out. The source render measures \(Self.sourceMeanLuma). This is \
            the M7 defect: a milky star field instead of deep space with a ribbon in it. \
            Reduce star SIZE/brightness before reducing count — `07` is legitimately dense.
            """)
        #expect(litShare <= Self.maxLitShare, """
            \(String(format: "%.2f", litShare))% of pixels are lit, above \(Self.maxLitShare)% — \
            the source render measures \(Self.sourceLitShare)%. Stars are too large; sub-pixel \
            points leave the field black at any density.
            """)
        // Never let the fix overshoot into a black rectangle: the backdrop must still be
        // visibly a star field, and D-037 forbids a black silence state.
        #expect(mean >= 2.0, """
            backdrop mean luma \(String(format: "%.2f", mean)) — the field has gone black. \
            D-037: silence must never render black, and the register needs a visible star \
            field and violet bloom.
            """)
    }
}
