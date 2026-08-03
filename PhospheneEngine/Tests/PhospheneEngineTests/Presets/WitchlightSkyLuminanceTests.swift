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
//
// WL.2-g added the second half. The same M7 had a third defect, on the other side of the
// same measurement: with the field fixed and the beads correctly sized, the ribbon still
// carried almost no light. Same frame, same scale:
//
//     source render (`00`)   ribbon pixels (luma > 120) 1.048%   peak luma 255
//     shipped Witchlight     ribbon pixels (luma > 120) 0.119%   peak luma 224
//
// Nine times too little light in the stroke — bright cores with real bloom halos in the
// source against hard pinpoints on a thin thread in ours. Both halves live here because
// they are one trade-off: brightening the ribbon must not brighten the field, and the
// only way to hold that is to assert both against the source in the same suite.

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Presets
@testable import Renderer
@testable import Shared

@MainActor
@Suite("Witchlight frame statistics vs the source (WL.2-e / WL.2-g)")
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

    // MARK: - The ribbon (WL.2-g)

    /// Measured from the same source render: share of pixels above 120/255, and the
    /// brightest pixel in the frame.
    private static let sourceRibbonShare = 1.048   // %
    private static let sourcePeakLuma = 255.0

    /// Floors, not equalities. `≥ 0.6 %` is most of the way to the source without demanding
    /// a pixel-for-pixel copy — the register is "a luminous ribbon" (D-121), not the source
    /// frame. `≥ 250` is the bead core reaching near-white, which is what `08` shows a real
    /// arc core doing.
    private static let minRibbonShare = 0.6
    private static let minPeakLuma = 250.0

    @Test("The ribbon carries light — bright cores, real halos (WL.2-g)")
    func ribbonCarriesLight() throws {
        let harness = MultiPassRenderHarness(width: 640, height: 360)

        // A settled, turning drive. The heading has to move or the pen lays a straight line
        // and the beads pile up along it — which measures overlap, not shading. `settle`
        // advances the stroke without rendering, so a full 30 s trail is cheap.
        func frame(_ i: Int) -> FeatureVector {
            var f = FeatureVector()
            f.deltaTime = 1.0 / 60
            f.time = Float(i) / 60
            f.bass = 0.3; f.mid = 0.3; f.treble = 0.2
            f.spectralCentroid = 0.12
            f.valence = 0.2
            f.arousal = 0.4
            // A slow harmonic circuit — the pen turns, so the ribbon is a curve with the
            // bead spacing the source has rather than a collapsed straight stroke.
            f.tonalPhaseFifths = Float(sin(Double(i) / 220.0) * .pi)
            f.aspectRatio = 640.0 / 360.0
            return f
        }
        let features = (0..<12).map { frame(1800 + $0) }
        let stems = [StemFeatures](repeating: StemFeatures(), count: features.count)

        let frames: [[UInt8]] = try harness.render(
            preset: "Witchlight", features: features, stems: stems, settle: 1800) { $0 }
        let last = try #require(frames.last, "no frame rendered")

        var ribbon = 0
        var peak = 0.0
        let pixels = last.count / 4
        var hist = [Int](repeating: 0, count: 8)   // >20 >40 >60 >90 >120 >160 >200 >240
        let edges: [Double] = [20, 40, 60, 90, 120, 160, 200, 240]
        for i in stride(from: 0, to: last.count, by: 4) {
            let luma = 0.114 * Double(last[i]) + 0.587 * Double(last[i + 1]) + 0.299 * Double(last[i + 2])
            if luma > 120 { ribbon += 1 }
            for (k, e) in edges.enumerated() where luma > e { hist[k] += 1 }
            peak = max(peak, luma)
        }
        let ribbonShare = 100.0 * Double(ribbon) / Double(pixels)
        print("[hist] " + zip(edges, hist).map {
            String(format: ">%.0f %.3f%%", $0, 100.0 * Double($1) / Double(pixels))
        }.joined(separator: "  "))
        if ProcessInfo.processInfo.environment["RENDER_VISUAL"] != nil {
            let dir = URL(fileURLWithPath: "/tmp/phosphene_visual/witchlight_ribbon")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = dir.appendingPathComponent("ribbon.png")
            try writePNG(bgra: last, width: 640, height: 360, to: out)
            print("[ribbon] frame → \(out.path)")
        }

        print(String(format: "[ribbon] share %.3f%% (source %.3f%%, floor %.2f%%) | peak %.1f (source %.0f, floor %.0f)",
                     ribbonShare, Self.sourceRibbonShare, Self.minRibbonShare,
                     peak, Self.sourcePeakLuma, Self.minPeakLuma))

        #expect(ribbonShare >= Self.minRibbonShare, """
            ribbon share \(String(format: "%.3f", ribbonShare))% is below \
            \(Self.minRibbonShare)% — the source measures \(Self.sourceRibbonShare)%. The beads \
            are carrying no light: hard pinpoints instead of bright cores with bloom halos \
            (`08`). This is a SHADING fix — widen and brighten the halo term and lift the \
            line, do NOT enlarge `baseRadius` or raise `emissionHz`, which are solved and \
            were measured not to move this number.
            """)
        #expect(peak >= Self.minPeakLuma, """
            peak luma \(String(format: "%.1f", peak)) is below \(Self.minPeakLuma) — the \
            source reaches \(Self.sourcePeakLuma). A bead core has to resolve to near-white \
            (`08`: hot near-white core inside a cooler, wider, hue-carrying halo). A core \
            that only lifts the hue's brightest channel tops out below white; the hue lives \
            in the halo, which is where trait #7 is carried.
            """)
    }

    /// `RENDER_VISUAL=1` escape hatch — the numbers say how much light, only the frame says
    /// whether it is in the right *places*.
    private func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        let cs = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                              | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let cg = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let c = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: cs, bitmapInfo: bi.rawValue)
            else { return nil }
            return c.makeImage()
        }
        let img = try #require(cg)
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}
