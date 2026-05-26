// BeatThisBugRegressionTests — Targeted regression tests for the four DSP.2 S8 bugs.
//
// Each test surfaces exactly one root cause so that a future regression localises immediately
// rather than requiring layer-diff detective work:
//
//   Bug 1 (norm-after-conv shape) — test_frontendBlockNorms_matchOutputDim
//   Bug 2 (stem reshape transpose) — covered by BeatThisLayerMatchTests (stem.bn1d stage)
//   Bug 3 (BN1d-aware padding)     — test_bn1dAwarePadding_paddedFramesAreNearZeroPostBN
//   Bug 4 (paired-adjacent RoPE)  — covered by BeatThisLayerMatchTests (transformer.0 stage)
//
// Reactive-mode regression: test_reactiveMode_setBeatGridNil_returnsBeatPredictorOutput
//   Confirms the MIRPipeline no-grid fallback path runs without crashing when setBeatGrid(nil)
//   is called. This is the path used by ad-hoc / reactive-mode sessions where no offline
//   BeatGrid is available (S7 only engaged in planned mode; reactive must keep working).

import Testing
import Foundation
import Metal
@testable import Shared
@testable import DSP
@testable import ML

@Suite("BeatThisBugRegression")
struct BeatThisBugRegressionTests {

    // MARK: - Bug 1: Frontend block norm shape matches out_dim, not in_dim

    /// The frontend block order must be: partial → conv → norm(out_dim) → GELU.
    /// The pre-S8 order was: partial → norm(wrong in_dim) → conv → GELU, which
    /// meant the BN2d was scaled by the wrong (input) channel count, corrupting
    /// all downstream activations.
    ///
    /// Verify by checking that each BeatThisFrontendBlockWeights.norm.scale has
    /// length equal to the conv OUTPUT dim (64, 128, 256), not the input dim (32, 64, 128).
    @Test func test_frontendBlockNorms_matchOutputDim() throws {
        let weights = try BeatThisModel.loadWeights()
        // Each block doubles the channel count: 32→64, 64→128, 128→256.
        let expectedOutDims = [64, 128, 256]
        for (idx, expected) in expectedOutDims.enumerated() {
            let actual = weights.frontendBlocks[idx].norm.scale.count
            #expect(actual == expected,
                    "block \(idx) norm.scale.count should be \(expected) (out_dim), got \(actual). Pre-S8: norm was applied with wrong in_dim, corrupting all downstream layers.")
        }
    }

    // MARK: - Bug 3: BN1d-aware padding keeps padded frames near zero post-BN

    /// When the input spectrogram has fewer than tMax=1500 frames, the model pads
    /// the remainder with per-mel values chosen so that BN1d(padValue_mel) == 0.
    /// This matches PyTorch's convention that zero-padded inputs produce zero
    /// post-BN activations.
    ///
    /// Pre-S8: padding was naive 0-fill, and BN1d(0) == shift/scale ≠ 0, bleeding
    /// non-zero values through the stem conv and corrupting the last ~3 timesteps.
    ///
    /// Test: feed a 1497-frame zero spectrogram (forces 3 padded frames) and
    /// verify that the stem.bn1d intermediate at frames [1497, 1498, 1499] is
    /// near zero (|value| < 1e-3).
    @Test func test_bn1dAwarePadding_paddedFramesAreNearZeroPostBN() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("BeatThisBugRegressionTests: no Metal device — skipping")
            return
        }
        let model = try BeatThisModel(device: device)
        let frameCount = 1497
        let mels = BeatThisModel.inputMels
        let tMax  = 1500

        // All-zero input: the padded region will be filled with bn1dPadValues.
        let zeros = [Float](repeating: 0, count: frameCount * mels)
        let captures = try model.predictDiagnostic(spectrogram: zeros, frameCount: frameCount)

        guard let bn1d = captures["stem.bn1d"] else {
            Issue.record("stem.bn1d not present in predictDiagnostic output")
            return
        }
        // stem.bn1d shape: [tMax, mels] = [1500, 128], row-major (time outer).
        // Padded frames are at time indices [frameCount..<tMax], i.e. flat indices
        // [frameCount*mels ..< tMax*mels].
        var failures: [(t: Int, mel: Int, val: Float)] = []
        for t in frameCount..<tMax {
            for mel in 0..<mels {
                let val = bn1d.values[t * mels + mel]
                if abs(val) >= 1e-3 {
                    failures.append((t, mel, val))
                }
            }
        }
        #expect(failures.isEmpty, """
            BN1d-aware padding: \(failures.count) padded elements exceed 1e-3. \
            Pre-S8: naive zero-fill caused BN1d(0)==shift to produce non-zero values. \
            First failing: frame=\(failures.first?.t ?? -1) mel=\(failures.first?.mel ?? -1) \
            val=\(failures.first?.val ?? 0)
            """)
    }

    // MARK: - Bugs 2 + 4: Covered by BeatThisLayerMatchTests

    // Bug 2 (stem reshape must transpose [T,F]→[F,T] before NHWC reshape):
    //   Regression surface: BeatThisLayerMatchTests/test_swiftMatchesPython_allKeyStages
    //   for stage "stem.bn1d" — wrong reshape scrambles the mel spectrogram, causing
    //   the stage mean to diverge from Python by > 50 %.
    //
    // Bug 4 (RoPE must pair adjacent elements (x[2i], x[2i+1]), not half-and-half):
    //   Regression surface: BeatThisLayerMatchTests/test_swiftMatchesPython_allKeyStages
    //   for stages "transformer.0" through "transformer.5" — wrong pairing produces
    //   completely wrong attention dot products, causing mean relative error > 30 %.

    // MARK: - Reactive-mode: setBeatGrid(nil) falls back to BeatPredictor

    /// When no BeatGrid is installed (setBeatGrid(nil) or ad-hoc mode), MIRPipeline
    /// must fall back to BeatPredictor for beatPhase01/beatsUntilNext.  The S7 drift
    /// tracker only activates on a planned session; all reactive/ad-hoc sessions must
    /// keep producing valid (finite, non-crashing) FeatureVectors.
    ///
    /// This test confirms the fallback path completes without throwing and produces
    /// a FeatureVector with all-finite values.  The deeper behavioural test (beat_phase01
    /// advances with actual beat input) is covered by existing MIRPipelineDriftIntegration
    /// tests; here we gate only on "doesn't crash, returns finite output."
    @Test func test_reactiveMode_setBeatGridNil_returnsBeatPredictorOutput() throws {
        let mir = MIRPipeline()
        mir.setBeatGrid(nil)

        // Feed 100 frames of silent (zero-magnitude) FFT input.
        let mags = [Float](repeating: 0, count: 512)
        let fps: Float = 60
        let dt: Float  = 1.0 / fps

        var lastFV = FeatureVector()
        for frame in 0..<100 {
            lastFV = mir.process(
                magnitudes: mags,
                fps: fps,
                time: Float(frame) * dt,
                deltaTime: dt
            )
        }

        #expect(lastFV.bass.isFinite,        "bass must be finite in reactive mode")
        #expect(lastFV.mid.isFinite,         "mid must be finite in reactive mode")
        #expect(lastFV.treble.isFinite,      "treble must be finite in reactive mode")
        #expect(lastFV.beatPhase01.isFinite, "beatPhase01 must be finite in reactive mode")
        #expect(!mir.liveDriftTracker.hasGrid, "liveDriftTracker.hasGrid must be false after setBeatGrid(nil)")
    }
}
