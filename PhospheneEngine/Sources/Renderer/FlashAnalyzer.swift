// FlashAnalyzer.swift — Harding / WCAG 2.3.1 photosensitivity flash analysis.
//
// CLEAN.7.6 / GAP-9. Measures the temporal luminance-transition rate of a
// rendered frame sequence and reports peak flashes-per-second against the
// Harding general-flash threshold. This is the measurement primitive behind
// the photosensitivity certification gate (Work B) and the planned runtime
// backstop (A-next).
//
// Standard (WCAG 2.3.1, general flash):
//   - A *flash* is a pair of opposing changes in relative luminance of ≥ 10 %
//     of max (≥ 0.10 on a 0…1 scale) where the *darker* state is < 0.80.
//   - Content is unsafe if it produces *more than 3 flashes within any
//     1-second window* over a sufficiently large area (~25 % of a 10° field).
//
// SCOPE (v1, full-frame). This analyzer consumes the per-frame *full-frame
// mean* relative luminance. That is the correct, conservative metric for
// GLOBAL luminance pumping — the FBS "beat-punch" failure class (the whole
// field brightening on every kick), which is the documented real-world defect
// this gate exists to prevent. It deliberately does NOT yet implement:
//   - regional / area-gating: a flash confined to < the full frame can move
//     the full-frame mean by < 10 % and be missed. Follow-up refinement.
//   - the separate saturated-RED flash channel. Follow-up.
//   - feedback-chain accumulation: callers that render frame-independently
//     (no previous-frame texture) measure the shader response, not feedback
//     build-up. Follow-up (drive the real RenderPipeline for a faithful chain).
// These limits are restated at the certification-gate call site.

import Foundation

// MARK: - FlashReport

/// Result of analyzing one luminance sequence against the Harding threshold.
public struct FlashReport: Sendable, Equatable {
    /// Number of frames analyzed.
    public let frameCount: Int
    /// Frames-per-second used to map frame indices to time.
    public let fps: Double
    /// Total qualifying opposing luminance transitions (each ≥ 10 % swing,
    /// darker state < 0.80). A flash is a pair of these.
    public let transitionCount: Int
    /// Peak flashes/second over any 1-second sliding window.
    public let peakFlashesPerSecond: Double
    /// Start time (s) of the worst 1-second window.
    public let peakWindowStartSeconds: Double
    /// True iff `peakFlashesPerSecond` is within the Harding limit (≤ 3).
    public let isSafe: Bool
}

// MARK: - FlashAnalyzer

public enum FlashAnalyzer {

    /// WCAG general-flash limit: *more than* this many flashes within any 1 s
    /// is unsafe. The limit itself (exactly 3/s) is safe.
    public static let flashesPerSecondLimit = 3.0
    /// Minimum relative-luminance swing (of max) for a change to count.
    public static let swingThreshold = 0.10
    /// The darker state of a qualifying flash must be below this.
    public static let darkStateCeiling = 0.80

    /// Analyze a chronological sequence of full-frame mean relative luminances
    /// (each in 0…1) at a uniform frame rate.
    ///
    /// - Parameters:
    ///   - luma: per-frame full-frame mean relative luminance, chronological.
    ///   - fps: frames per second (must be > 0).
    public static func analyze(relativeLuminance luma: [Double], fps: Double) -> FlashReport {
        precondition(fps > 0, "fps must be positive")

        // 1. Reduce the signal to significant turning points via hysteresis: a
        //    peak/valley is confirmed only once luminance reverses by ≥ the
        //    swing threshold, so sub-threshold wiggles are absorbed.
        let extrema = significantExtrema(luma, threshold: swingThreshold)

        // 2. Each adjacent extremum pair is one qualifying transition iff it
        //    swings ≥ threshold AND its darker endpoint is < the dark ceiling.
        var transitionTimes: [Double] = []
        if extrema.count >= 2 {
            for k in 1..<extrema.count {
                let prev = extrema[k - 1].value
                let curr = extrema[k].value
                if abs(curr - prev) >= swingThreshold && min(prev, curr) < darkStateCeiling {
                    transitionTimes.append(Double(extrema[k].index) / fps)
                }
            }
        }

        // 3. Slide a 1-second window over the transition events. A flash is a
        //    pair of opposing transitions, so the peak flashes/second is the
        //    worst window's transition count ÷ 2.
        var peakTransitionsInWindow = 0
        var peakWindowStart = 0.0
        for j in 0..<transitionTimes.count {
            let windowStart = transitionTimes[j]
            var count = 0
            for k in j..<transitionTimes.count where transitionTimes[k] < windowStart + 1.0 {
                count += 1
            }
            if count > peakTransitionsInWindow {
                peakTransitionsInWindow = count
                peakWindowStart = windowStart
            }
        }
        let peakFlashes = Double(peakTransitionsInWindow) / 2.0

        return FlashReport(
            frameCount: luma.count,
            fps: fps,
            transitionCount: transitionTimes.count,
            peakFlashesPerSecond: peakFlashes,
            peakWindowStartSeconds: peakWindowStart,
            isSafe: peakFlashes <= flashesPerSecondLimit
        )
    }

    // MARK: - Internal

    private struct Extremum { let index: Int; let value: Double }

    /// Turning points with a minimum reversal amplitude (hysteresis). The first
    /// sample seeds the sequence; thereafter a peak/valley is emitted only when
    /// luminance reverses from the running extreme by ≥ `threshold`. Consecutive
    /// emitted extrema therefore alternate direction and differ by ≥ `threshold`.
    private static func significantExtrema(_ x: [Double], threshold: Double) -> [Extremum] {
        guard let first = x.first else { return [] }
        var out: [Extremum] = [Extremum(index: 0, value: first)]
        var anchor = out[0]            // last confirmed turning point
        var cand = anchor              // running extreme since the anchor
        var dir = 0.0                  // +1 rising, -1 falling, 0 undetermined

        // The rising and falling cases are mirror images, so direction is a sign
        // multiplier: `delta * dir > 0` means "still moving the current way"
        // (extend the running extreme); a reversal of ≥ threshold confirms a
        // turning point and flips the direction.
        for i in 1..<x.count {
            let lum = x[i]
            if dir == 0 {
                if abs(lum - anchor.value) >= threshold {
                    dir = lum > anchor.value ? 1 : -1
                    cand = Extremum(index: i, value: lum)
                }
            } else if (lum - cand.value) * dir > 0 {
                cand = Extremum(index: i, value: lum)
            } else if (cand.value - lum) * dir >= threshold {
                out.append(cand); anchor = cand
                dir = -dir
                cand = Extremum(index: i, value: lum)
            }
        }
        return out
    }
}
