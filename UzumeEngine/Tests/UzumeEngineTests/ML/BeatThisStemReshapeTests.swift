// BeatThisStemReshapeTests — Targeted regression for DSP.2 S8 Bug 2.
//
// Pre-fix: the stem path byte-reinterpreted `[T, F]` to `[1, F, T, 1]` instead of
// transposing-then-reshaping, scrambling the mel spectrogram before the stem conv.
// Post-fix: transpose first (`[T, F]` → `[F, T]`), then reshape to NHWC `[1, F, T, 1]`.
//
// Bug 2 is *also* covered by `BeatThisLayerMatchTests` via the stem.bn1d stage stat
// divergence; this test stands alone so a future regression localises immediately
// to "the stem reshape lost per-mel structure" rather than emerging only as a stat
// mismatch in the layer-match test (which could also reflect Bug 1, 3, or 4).
//
// Strategy: feed an input that is constant in time but non-uniform across mels.
//   correct path:  per-mel structure preserved → variance along the mel (F) axis is
//                  much larger than variance along the time (T) axis.
//   wrong path:    byte-reinterpret scrambles the [T, F] memory layout, smearing
//                  the per-mel signal across the time axis and collapsing the F-vs-T
//                  variance ratio toward 1×.

import Testing
import Foundation
import Metal
@testable import ML

@Suite("BeatThisStemReshape")
struct BeatThisStemReshapeTests {

    @Test("stem.bn1d preserves per-mel structure (transpose, not byte-reinterpret) — DSP.2 S8 Bug 2")
    func test_stemReshapePreservesPerMelStructure() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("BeatThisStemReshapeTests: no Metal device — skipping")
            return
        }
        let model = try BeatThisModel(device: device)

        // Synthetic input: constant in time, non-uniform across mels.
        // Use a smoothly-varying per-mel ramp scaled into [0, 1] so post-BN values
        // span a reasonable range without saturating the stem path.
        let frameCount = 256
        let mels = BeatThisModel.inputMels
        var spect = [Float](repeating: 0, count: frameCount * mels)
        for t in 0..<frameCount {
            for mel in 0..<mels {
                spect[t * mels + mel] = Float(mel) / Float(mels - 1)   // 0 → 1 across mels
            }
        }

        let captures = try model.predictDiagnostic(spectrogram: spect, frameCount: frameCount)
        guard let bn1d = captures["stem.bn1d"] else {
            Issue.record("stem.bn1d not present in predictDiagnostic output — capture surface changed?")
            return
        }
        // stem.bn1d shape: row-major [tMax, mels]. Restrict to the signal frames
        // (0..<frameCount) so padded frames never enter the variance computation —
        // they are forced near zero by Bug 3's padding fix and would skew the std
        // unfairly toward "F has variance, T does not" for the wrong reasons.
        let tMax = 1500
        #expect(bn1d.values.count >= tMax * mels,
                "unexpected bn1d capture size \(bn1d.values.count); expected ≥ \(tMax * mels)")

        // Variance along T (at fixed mel): for an input that is constant in time
        // per mel, the correct path yields ~0 variance along T. The wrong path
        // smears per-mel signal across T → non-trivial T-variance.
        var varAlongT_avgPerMel: Double = 0
        for mel in 0..<mels {
            var sum: Double = 0
            var sumSq: Double = 0
            for t in 0..<frameCount {
                let v = Double(bn1d.values[t * mels + mel])
                sum += v
                sumSq += v * v
            }
            let mean = sum / Double(frameCount)
            let variance = max(0, sumSq / Double(frameCount) - mean * mean)
            varAlongT_avgPerMel += variance
        }
        varAlongT_avgPerMel /= Double(mels)

        // Variance along F (at fixed time): the input ramp produces large per-row
        // variation across mels → high F-variance under the correct path.
        var varAlongF_avgPerT: Double = 0
        for t in 0..<frameCount {
            var sum: Double = 0
            var sumSq: Double = 0
            for mel in 0..<mels {
                let v = Double(bn1d.values[t * mels + mel])
                sum += v
                sumSq += v * v
            }
            let mean = sum / Double(mels)
            let variance = max(0, sumSq / Double(mels) - mean * mean)
            varAlongF_avgPerT += variance
        }
        varAlongF_avgPerT /= Double(frameCount)

        // Conservative threshold: 5× is far below what the correct path produces
        // (constant-in-time input gives near-zero T-variance, only float noise);
        // if the production stem reshape regressed to byte-reinterpret, the ratio
        // collapses well below 2×.
        let stdAlongF = varAlongF_avgPerT.squareRoot()
        let stdAlongT = varAlongT_avgPerMel.squareRoot()
        let ratioOK = stdAlongF > stdAlongT * 5
        #expect(ratioOK, """
            Bug 2 regression: stem.bn1d lost per-mel structure. \
            stdAlongF=\(stdAlongF), stdAlongT=\(stdAlongT), \
            ratio=\(stdAlongT > 0 ? stdAlongF / stdAlongT : .infinity), expected > 5×. \
            Pre-S8: byte-reinterpreting [T,F] as [1,F,T,1] collapses this ratio toward 1×.
            """)
    }
}
