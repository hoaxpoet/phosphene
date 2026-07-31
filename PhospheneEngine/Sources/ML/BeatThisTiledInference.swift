// BeatThisTiledInference — full-track activations by sliding-window tiling (FT.1).
//
// `BeatThisModel` has a fixed 1500-frame (~30 s at 50 fps) input window, so until now
// every grid — and every measurement in the beat-sync program — came from the first
// 30 s of a track. money's meter was decided from **51 beats of a 380-second track**
// (D-208 amendment). Meter is a periodicity question, and 51 beats is a materially
// weaker problem than the ~700 a full track offers.
//
// This tiles the full spectrogram into overlapping windows, runs the model on each, and
// averages the activations back into one full-length timeline. Offline path only: cost
// is ~1 forward pass per 15 s of audio, which is prep-time work, never per-frame.
//
// Thread safety: stateless; concurrency is bounded by the model's own lock.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "BeatThisTiledInference")

public enum BeatThisTiledInference {

    /// Model input window. Tiling only exists because this is fixed.
    public static let windowFrames = BeatThisModel.tMax

    /// 50 % overlap, so every interior frame is predicted twice — once with left
    /// context and once with right context — and the average of the two is better
    /// conditioned than either near a window edge.
    public static let hopFrames = windowFrames / 2

    /// Beat/downbeat activations for a spectrogram of any length.
    ///
    /// Input shorter than one window takes a single `predict` and is returned unchanged,
    /// so the tiler is exactly transparent on the ≤ 30 s case the rest of the engine
    /// already relies on.
    ///
    /// - Parameters:
    ///   - model: the inference model; called once per window.
    ///   - spectrogram: flat row-major `[frameCount × BeatThisModel.inputMels]`.
    ///   - frameCount: rows in `spectrogram`. May exceed `windowFrames`.
    /// - Returns: beat and downbeat probabilities, each of length `frameCount`.
    public static func predictFullTrack(
        model: BeatThisModel,
        spectrogram: [Float],
        frameCount: Int
    ) throws -> (beats: [Float], downbeats: [Float]) {
        guard frameCount > 0 else { return ([], []) }
        guard frameCount > windowFrames else {
            return try model.predict(spectrogram: spectrogram, frameCount: frameCount)
        }

        let mels = BeatThisModel.inputMels
        let starts = windowStarts(frameCount: frameCount)
        var beatSum = [Float](repeating: 0, count: frameCount)
        var downbeatSum = [Float](repeating: 0, count: frameCount)
        var counts = [Float](repeating: 0, count: frameCount)

        for start in starts {
            let end = min(start + windowFrames, frameCount)
            let length = end - start
            let slice = Array(spectrogram[(start * mels)..<(end * mels)])
            let (beats, downbeats) = try model.predict(spectrogram: slice, frameCount: length)
            // `predict` is documented to return `frameCount` values; guard rather than
            // trap if a future change breaks that, since this runs on real tracks.
            let usable = min(length, min(beats.count, downbeats.count))
            for i in 0..<usable {
                beatSum[start + i] += beats[i]
                downbeatSum[start + i] += downbeats[i]
                counts[start + i] += 1
            }
        }

        for i in 0..<frameCount where counts[i] > 0 {
            beatSum[i] /= counts[i]
            downbeatSum[i] /= counts[i]
        }
        let seconds = String(format: "%.1f", Double(frameCount) / 50.0)
        let windows = starts.count
        logger.info("tiled inference: \(frameCount) frames (\(seconds) s) in \(windows) windows")
        return (beatSum, downbeatSum)
    }

    /// Window start frames.
    ///
    /// Strided by `hopFrames`, with the final window **anchored to end at `frameCount`**
    /// rather than allowed to run short. A stub final window (a few frames with almost no
    /// context) would produce poorly-conditioned activations and then be averaged in at
    /// full weight; anchoring costs a little extra overlap and avoids that entirely.
    static func windowStarts(frameCount: Int) -> [Int] {
        guard frameCount > windowFrames else { return [0] }
        var starts: [Int] = []
        var start = 0
        while start + windowFrames < frameCount {
            starts.append(start)
            start += hopFrames
        }
        let final = frameCount - windowFrames
        if starts.last != final { starts.append(final) }
        return starts
    }
}
