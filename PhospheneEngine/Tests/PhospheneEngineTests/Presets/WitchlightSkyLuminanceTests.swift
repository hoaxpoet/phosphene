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

    /// Ratcheted at WL.2-h, and the reason is a correction to what `00` was taken to mean.
    ///
    /// `00` is one frame of a preset with enormous dynamic range. Measured across the
    /// source's own animation (60 frames, ~4.2 s), its lit share swings **1.04 % → 34.41 %**
    /// — near-black between events, then a frame-filling burst. `00` at 4.0 % is a
    /// mid-activity frame, so treating it as the resting state set our floor ~7× too high:
    /// the field never got out of the way and the whole preset sat at a constant glow
    /// (measured 1.3× range against the source's 33×), which is the "does not resemble the
    /// original in look and motion" half of Matt's second M7.
    ///
    /// These ceilings are therefore set against the source's QUIET frame (mean 7.64,
    /// lit 1.04 %), not against `00`, with headroom over the achieved 9.42 / 2.66 %. The
    /// old 22.0 / 10.0 were wide enough to let the floor drift back up without failing.
    private static let maxMeanLuma = 12.0
    private static let maxLitShare = 4.5

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
            the field is washing out. The source measures \(Self.sourceMeanLuma) on `00` and 7.64 \
            on its QUIET frames, which is what this ceiling is set against. This is the M7 defect: \
            a milky star field instead of deep space with a ribbon in it, and a floor this high is \
            also what flattens the preset's dynamic range (WL.2-h). \
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

    /// The settled ribbon drive, shared by the luminance and distinctness gates so the two
    /// can never measure different scenes.
    static func settledRibbonDrive() -> [FeatureVector] {
        (0..<12).map { i -> FeatureVector in
            var f = FeatureVector()
            f.deltaTime = 1.0 / 60
            f.time = Float(1800 + i) / 60
            f.bass = 0.3; f.mid = 0.3; f.treble = 0.2
            f.spectralCentroid = 0.12
            f.valence = 0.2
            f.arousal = 0.4
            f.tonalPhaseFifths = Float(sin(Double(1800 + i) / 220.0) * .pi)
            f.aspectRatio = 640.0 / 360.0
            return f
        }
    }

    static func settledRibbonStems() -> [StemFeatures] {
        [StemFeatures](repeating: StemFeatures(), count: 12)
    }

    // MARK: - The beads read as beads (WL.2-j)

    /// Counts separate bright cores in the stroke. This gate exists because the other one
    /// could not catch the defect it was written for.
    ///
    /// `ribbonShare` counts LIT PIXELS, so when WL.2-g/-h widened the drawn sprite to 2.6×
    /// then 3.2× the bead radius, consecutive sprites overlapped 30–48 % and fused into the
    /// uniform glow tube of anti-reference `11` — and the share went UP, because overlapping
    /// sprites light more pixels. The gate reported the regression as an improvement. A
    /// measure that improves as the defect worsens is worse than no measure, so distinctness
    /// is asserted separately and structurally.
    ///
    /// Connected components rather than a spacing formula on purpose: the geometry that
    /// decides fusion (`WL_HALO_EXTENT`, `emissionHz`, `baseSpeed`, `viewScale`) is spread
    /// across a shader constant, a tuning struct and a runtime auto-fit, and any of them can
    /// reintroduce it. Counting what actually reached the framebuffer cannot be fooled by a
    /// refactor of that arithmetic.
    @Test("The stroke reads as beads on a thread, not a fused tube (WL.2-j)")
    func beadsReadAsDistinct() throws {
        let harness = MultiPassRenderHarness(width: 640, height: 360)
        let frames: [[UInt8]] = try harness.render(
            preset: "Witchlight", features: Self.settledRibbonDrive(), stems: Self.settledRibbonStems(),
            settle: 1800) { $0 }
        let last = try #require(frames.last)

        let w = 640, h = 360
        var core = [Bool](repeating: false, count: w * h)
        for idx in 0..<(w * h) {
            let i = idx * 4
            let luma = 0.114 * Double(last[i]) + 0.587 * Double(last[i + 1]) + 0.299 * Double(last[i + 2])
            core[idx] = luma > 200
        }

        // 4-connected components. Stars also exceed the threshold but are 1–4 px, so a
        // minimum size of 8 px keeps them out without needing to know where they are.
        var seen = [Bool](repeating: false, count: w * h)
        var beadCount = 0
        var stack = [Int]()
        for start in 0..<(w * h) where core[start] && !seen[start] {
            seen[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var size = 0
            while let p = stack.popLast() {
                size += 1
                let x = p % w, y = p / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let q = ny * w + nx
                    if core[q] && !seen[q] { seen[q] = true; stack.append(q) }
                }
            }
            if size >= 8 { beadCount += 1 }
        }

        print("[beads] \(beadCount) distinct bright cores (floor \(Self.minDistinctBeads))")

        #expect(beadCount >= Self.minDistinctBeads, """
            only \(beadCount) distinct bright cores in the stroke — the beads have FUSED into \
            a glow tube (anti-reference `11`). Bead centres sit 1.2 × 2 × baseRadius apart, so \
            they read as separate only while the drawn sprite stays under 1.2 × viewScale bead \
            radii; `viewScale` measures 1.38–1.88, so WL_HALO_EXTENT must stay near 1.6. \
            Do NOT satisfy this by making the beads dimmer — distinctness here is geometric, \
            and `ribbonShare` will happily rise while this falls (that pairing is exactly how \
            the fusion shipped in the first place).
            """)
    }

    /// Measured on this drive, and the contrast is the whole point:
    ///
    /// | `WL_HALO_EXTENT` | ribbonShare | distinct cores |
    /// |---|---|---|
    /// | 1.6 (separated) | 0.687 % | **14** |
    /// | 2.6 (WL.2-g)    | 1.289 % | **1**  |
    /// | 3.2 (WL.2-h)    | 1.636 % | **1**  |
    ///
    /// The two metrics move in OPPOSITE directions — `ribbonShare` more than doubles as the
    /// stroke fuses into a single component. That is the recorded proof that a luminance
    /// gate cannot police this, and why both assertions have to exist.
    ///
    /// 8 sits between the fused 1 and the separated 14: it catches a return to fusion with
    /// margin while leaving the exact bead count free, since that legitimately moves with pen
    /// speed and with how much of the trail is on screen.
    private static let minDistinctBeads = 8

    // MARK: - The backdrop moves (WL.2-i)

    /// Matt's M7: *"the background is not moving and so looks fake when the dots are drawing
    /// / moving over it."* He was right, and nothing measured it.
    ///
    /// `drift` is in CELL units and a cell is `1/cells` of the frame, so the shipped
    /// `0.0035 + 0.0110·brightness` resolved to ~0.008 on a real track — the NEAR star layer
    /// travelled ~0.16 px/s at 1080p (2.5 % of frame width across a whole 5-minute track) and
    /// the far layer ~4 px per track. A still field behind a moving stroke reads as pasted-on.
    ///
    /// This renders the same scene at two times and asserts the field actually changed.
    /// It deliberately measures CHANGED PIXELS rather than a drift constant, because the
    /// visible quantity is "did the background move", and a future refactor of the layer
    /// maths must not be able to satisfy the gate while rendering a static field.
    @Test("The star field actually drifts — the backdrop is not a still image (WL.2-i)")
    func backdropDrifts() throws {
        let harness = MultiPassRenderHarness(width: 640, height: 360)

        func frameAt(_ seconds: Float) -> FeatureVector {
            var f = FeatureVector()
            f.deltaTime = 1.0 / 60
            f.time = seconds
            f.bass = 0.3; f.mid = 0.3; f.treble = 0.2
            f.spectralCentroid = 0.115      // the p50 of Matt's M7 capture
            f.valence = 0.2
            f.aspectRatio = 640.0 / 360.0
            return f
        }

        // Two independent single-frame renders, 30 s of preset time apart. Rendered as
        // one-frame drives so the ribbon is identical in both and only `time` differs —
        // otherwise the stroke's own growth would satisfy the assertion on its own.
        let stems = [StemFeatures](repeating: StemFeatures(), count: 1)
        let early: [[UInt8]] = try harness.render(
            preset: "Witchlight", features: [frameAt(0)], stems: stems, settle: 0) { $0 }
        let later: [[UInt8]] = try harness.render(
            preset: "Witchlight", features: [frameAt(30)], stems: stems, settle: 0) { $0 }
        let a = try #require(early.last), b = try #require(later.last)

        var changed = 0
        var starPixels = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            let la = 0.114 * Double(a[i]) + 0.587 * Double(a[i + 1]) + 0.299 * Double(a[i + 2])
            let lb = 0.114 * Double(b[i]) + 0.587 * Double(b[i + 1]) + 0.299 * Double(b[i + 2])
            guard la > 30 || lb > 30 else { continue }   // lit in at least one frame
            starPixels += 1
            if abs(la - lb) > 12 { changed += 1 }
        }
        let movedShare = 100.0 * Double(changed) / Double(max(starPixels, 1))

        print(String(format: "[drift] %.1f%% of lit backdrop pixels changed over 30 s (floor %.0f%%)",
                     movedShare, Self.minDriftedShare))

        #expect(movedShare >= Self.minDriftedShare, """
            only \(String(format: "%.1f", movedShare))% of lit backdrop pixels differ between \
            t=0 s and t=30 s — the star field is effectively FROZEN. `drift` is in CELL units, \
            so a rate that looks non-zero can still be sub-pixel: at the shipped 0.008 the near \
            layer moved 0.16 px/s and the far layer 4 px per TRACK. A still background behind a \
            moving stroke reads as pasted-on (Matt's M7, WL.2-i). Raise `rate`, do not raise the \
            star brightness to compensate — that regresses the WL.2-h floor.
            """)
    }

    /// Over 30 s the near layer should travel an appreciable fraction of the frame, so a large
    /// share of the (sparse, small) star pixels land somewhere new. Set well below the measured
    /// value: the point is to catch a frozen field, not to police the exact rate.
    private static let minDriftedShare = 25.0

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
