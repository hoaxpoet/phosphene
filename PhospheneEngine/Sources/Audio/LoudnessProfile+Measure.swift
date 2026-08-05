// LoudnessProfile+Measure — DYN.1c: run the level follower over a decoded local file.
//
// Lives in `Audio` rather than next to the type because it needs `FFTMagnitudeKernel`,
// the single source of truth for the window→magnitude formula (BUG-066). Reusing that
// kernel is what makes the offline level numerically comparable to the live one: the
// alternative — a second hand-rolled FFT — is exactly how the offline path once ran 16×
// hot for months.

import Foundation
import Shared

extension LoudnessProfile {

    /// Measure a track's own quiet-to-loud range from fully-decoded mono PCM.
    ///
    /// Mirrors the live path frame for frame: non-overlapping 1024-sample hops (the live
    /// tap delivers 1024-frame buffers, so live runs at the same ~47 Hz), the shared
    /// window→magnitude kernel, `LoudnessProfile.levelDB`, and the same EMA alpha —
    /// seeded on the first frame rather than climbing from −120 dB, so a lead-in does not
    /// drag the low percentile below anything the track actually contains.
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 PCM for the WHOLE file. A 30 s preview is not enough to
    ///     characterise a track and the percentiles would describe the preview window.
    ///   - sampleRate: Unused by the maths (the level sums over bins) — taken for symmetry
    ///     with the rest of the analysis API and to keep call sites self-documenting.
    ///   - fftSize: FFT length; must match the live pipeline's 1024.
    /// - Returns: `nil` when the audio is too short, silent, or the FFT setup fails —
    ///   every one of which means "keep the fixed band".
    public static func measure(
        samples: [Float],
        sampleRate: Double,
        fftSize: Int = 1024
    ) -> LoudnessProfile? {
        guard samples.count >= fftSize * minimumFrames,
              let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else { return nil }

        var levels = [Float]()
        levels.reserveCapacity(samples.count / fftSize)
        var smoothed: Float = 0
        var seeded = false
        var offset = 0

        while offset + fftSize <= samples.count {
            samples.withUnsafeBufferPointer { src in
                fft.windowed.withUnsafeMutableBufferPointer { dst in
                    guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress else { return }
                    dstBase.update(from: srcBase.advanced(by: offset), count: fftSize)
                }
            }
            fft.computeMagnitudes()
            let level = levelDB(magnitudes: fft.magnitudes, count: fft.binCount)
            if !seeded {
                smoothed = level
                seeded = true
            } else {
                smoothed = levelSmoothingAlpha * level + (1 - levelSmoothingAlpha) * smoothed
            }
            levels.append(smoothed)
            offset += fftSize
        }

        guard let profile = LoudnessProfile(smoothedLevelsDB: levels), profile.isUsable else {
            return nil
        }
        return profile
    }
}
