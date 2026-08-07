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
        // DYN.2c — the track's own density normal, measured here rather than learned
        // during playback (a τ45 s EMA cannot develop contrast inside a 3-minute song).
        var densities = [Float]()
        densities.reserveCapacity(samples.count / fftSize)
        let binResolution = Float(sampleRate) / Float(fftSize)
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
            densities.append(densityFraction(magnitudes: fft.magnitudes,
                                             count: fft.binCount,
                                             binResolution: binResolution))
            if !seeded {
                smoothed = level
                seeded = true
            } else {
                smoothed = levelSmoothingAlpha * level + (1 - levelSmoothingAlpha) * smoothed
            }
            levels.append(smoothed)
            offset += fftSize
        }

        guard let base = LoudnessProfile(smoothedLevelsDB: levels), base.isUsable else {
            return nil
        }
        // Smooth with the analyzer's OWN section alpha before taking quantiles — the live
        // side ranks a τ20 s signal, and quantiles of the raw fraction would be far wider,
        // parking every live value mid-scale. Seeded on the first frame, as the engine does.
        var smoothedDensity: [Float] = []
        smoothedDensity.reserveCapacity(densities.count)
        var running: Float?
        let sectionAlpha = LoudnessProfile.densitySectionAlpha
        for value in densities {
            let next = running.map { sectionAlpha * value + (1 - sectionAlpha) * $0 } ?? value
            running = next
            smoothedDensity.append(next)
        }
        let sortedDensity = smoothedDensity.sorted()
        let densityQuantiles: [Float] = sortedDensity.isEmpty ? [] : (0...LoudnessProfile.steps).map { step in
            let index = Int((Float(sortedDensity.count - 1) * Float(step) / Float(LoudnessProfile.steps)).rounded())
            return sortedDensity[min(max(index, 0), sortedDensity.count - 1)]
        }
        return LoudnessProfile(quantilesDB: base.quantilesDB, densityQuantiles: densityQuantiles)
    }
}
