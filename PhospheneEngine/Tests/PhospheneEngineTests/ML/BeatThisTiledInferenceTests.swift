// BeatThisTiledInferenceTests — FT.1's parity gates.
//
// The done-when is a "stitched-activation parity test (tiled vs single-window on a
// ≤ 30 s fixture, near-identical)". That case is exact by construction here — the tiler
// short-circuits to a single `predict` below one window — so it is tested as a real
// guard (the tiler must not perturb the path the whole engine already relies on) and
// backed by a second, stronger test: on a track long enough to tile, the interior of the
// first window must still track the single-window result, which is what proves the
// stitching preserves signal rather than smearing it.

import Testing
import Foundation
import Metal
@testable import DSP
@testable import ML

@Suite("BeatThisTiledInference")
struct BeatThisTiledInferenceTests {

    // MARK: - Window layout (no GPU)

    @Test("short input is a single window")
    func test_windowStarts_short() {
        #expect(BeatThisTiledInference.windowStarts(frameCount: 100) == [0])
        #expect(BeatThisTiledInference.windowStarts(frameCount: 1500) == [0])
    }

    @Test("windows stride by half a window and the last is anchored to the end")
    func test_windowStarts_tiled() {
        let frames = 4000
        let starts = BeatThisTiledInference.windowStarts(frameCount: frames)
        #expect(starts.first == 0)
        // Every window is full length — no stub final window with no context.
        for start in starts {
            #expect(start >= 0)
            #expect(start + BeatThisTiledInference.windowFrames <= frames,
                    "window at \(start) overruns \(frames)")
        }
        #expect(starts.last == frames - BeatThisTiledInference.windowFrames,
                "final window must be anchored to the track end, got \(String(describing: starts.last))")
        // Contiguous coverage: no frame is left unpredicted.
        var covered = [Bool](repeating: false, count: frames)
        for start in starts {
            for i in start..<(start + BeatThisTiledInference.windowFrames) { covered[i] = true }
        }
        #expect(!covered.contains(false), "tiling leaves uncovered frames")
    }

    @Test("no duplicate final window when the track divides evenly")
    func test_windowStarts_noDuplicateTail() {
        let frames = BeatThisTiledInference.windowFrames + BeatThisTiledInference.hopFrames
        let starts = BeatThisTiledInference.windowStarts(frameCount: frames)
        #expect(starts == Array(Set(starts)).sorted(), "duplicate window starts: \(starts)")
    }

    // MARK: - Parity against the single-window path (GPU)

    /// FT.1's stated done-when. A sub-window track must come back byte-identical to the
    /// path the engine already uses, so introducing the tiler cannot perturb any existing
    /// grid, golden or benchmark number.
    @Test("≤ 30 s: tiled output is identical to a single predict")
    func test_parity_shortTrack() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("no Metal device — skipping"); return
        }
        let model = try BeatThisModel(device: device)
        let frames = 900                              // 18 s, comfortably one window
        let spect = Self.syntheticSpectrogram(frames: frames)

        let single = try model.predict(spectrogram: spect, frameCount: frames)
        let tiled = try BeatThisTiledInference.predictFullTrack(
            model: model, spectrogram: spect, frameCount: frames
        )
        #expect(tiled.beats.count == frames)
        #expect(tiled.downbeats.count == frames)
        for i in 0..<frames {
            #expect(tiled.beats[i] == single.beats[i], "beat frame \(i) diverged")
            #expect(tiled.downbeats[i] == single.downbeats[i], "downbeat frame \(i) diverged")
        }
    }

    /// The stronger property: once tiling actually engages, the *interior* of the first
    /// window — where the tiled result averages a full-context prediction with another
    /// full-context prediction — must still track the single-window result closely.
    /// Frames near a window edge legitimately differ; the interior must not.
    @Test("tiled interior tracks the single-window result on a long track")
    func test_parity_longTrackInterior() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("no Metal device — skipping"); return
        }
        let model = try BeatThisModel(device: device)
        let window = BeatThisTiledInference.windowFrames
        let frames = window * 2 + 300                 // ~66 s: forces several windows
        let spect = Self.syntheticSpectrogram(frames: frames)

        let tiled = try BeatThisTiledInference.predictFullTrack(
            model: model, spectrogram: spect, frameCount: frames
        )
        #expect(tiled.beats.count == frames)
        let firstWindow = Array(spect[0..<(window * BeatThisModel.inputMels)])
        let single = try model.predict(spectrogram: firstWindow, frameCount: window)

        // Compare in the region that is genuinely BLENDED — covered by window 0 and by
        // window `hopFrames`. Frames before the hop are covered by a single window, so
        // comparing there is trivially identical and asserts nothing about stitching.
        let starts = BeatThisTiledInference.windowStarts(frameCount: frames)
        let lo = BeatThisTiledInference.hopFrames + 100
        let hi = window - 100
        var coverage = [Int](repeating: 0, count: frames)
        for start in starts {
            for i in start..<(start + window) { coverage[i] += 1 }
        }
        #expect(coverage[lo..<hi].allSatisfy { $0 >= 2 },
                "frames \(lo)..<\(hi) are not blended — the test would assert nothing")

        var maxDelta: Float = 0
        for i in lo..<hi { maxDelta = max(maxDelta, abs(tiled.beats[i] - single.beats[i])) }
        print("[FT.1] blended-region max |Δbeat| over frames \(lo)..<\(hi) "
              + "(coverage \(coverage[lo])×): \(maxDelta)")
        // The tiled value here is the mean of two predictions of the same audio made with
        // different context, so it legitimately differs from either — it must be CLOSE,
        // not identical. A large delta would mean the windows disagree wildly and the
        // average is smearing rather than reinforcing.
        #expect(maxDelta < 0.25, """
            blended region diverged from single-window by \(maxDelta) — the overlapping \
            windows disagree enough that averaging is smearing the activations
            """)
    }

    // MARK: - Fixture

    /// A synthetic log-mel-shaped spectrogram with a periodic low-band accent, so the
    /// model sees *something* structured. These tests assert tiler mechanics, not
    /// musical accuracy — real-audio behaviour is the FT.1 full-track measurement.
    private static func syntheticSpectrogram(frames: Int) -> [Float] {
        let mels = BeatThisModel.inputMels
        var out = [Float](repeating: 0, count: frames * mels)
        for frame in 0..<frames {
            let onBeat = frame % 25 == 0            // 25 frames = 0.5 s = 120 BPM
            // Non-stationary on purpose: a stationary fixture makes every window see the
            // same audio, so overlapping predictions agree trivially and the blend test
            // passes without exercising anything.
            let section = Float(frame) / Float(max(frames, 1))
            for mel in 0..<mels {
                let base = Float(mel) / Float(mels)
                var value = -4.0 + base * 0.5 + section * 1.5
                if onBeat && mel < 24 { value += 3.0 - section }
                out[frame * mels + mel] = value
            }
        }
        return out
    }
}
