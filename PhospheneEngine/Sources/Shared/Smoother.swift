// Smoother — FPS-independent decay primitive used across the DSP layer.
//
// Centralises the `pow(rate30, 30/fps)` formula that BeatDetector
// (pulse decay) and BandEnergyProcessor (per-band EMA smoothing) both
// implement inline. Same formula, same numerical result; one location.
//
// Why FPS-independent matters: at 60 fps the per-frame decay factor for
// a rate-30 base `r` is `pow(r, 0.5)`; at 30 fps it's `r` itself; at 120
// fps it's `pow(r, 0.25)`. The formula gives time-equivalent decay
// regardless of render cadence.

import Foundation

// MARK: - Smoother

/// FPS-independent decay rate at a 30 fps reference.
///
/// Construct with the rate you want at 30 fps (`rate30`); call
/// `factor(at:)` to get the per-frame decay at the actual fps. Used
/// either as a multiplicative decay (`current *= factor`) or as the
/// retain weight in an EMA (`result = factor * current + (1 - factor) * target`,
/// available as `step(current:target:at:)`).
@frozen
public struct Smoother: Sendable {

    /// The per-frame retain factor at 30 fps reference rate.
    /// `factor(at: 30)` returns exactly this.
    public let rate30: Float

    public init(rate30: Float) {
        self.rate30 = rate30
    }

    /// Per-frame decay factor at the given fps.
    ///
    /// `factor(at: 30)` = `rate30`; `factor(at: 60)` = `sqrt(rate30)`.
    @inlinable
    public func factor(at fps: Float) -> Float {
        powf(rate30, 30.0 / fps)
    }

    /// EMA step: `result = factor * current + (1 - factor) * target`.
    ///
    /// Convenience wrapper for the common "smoothed value moves toward a
    /// new target each frame" pattern. Equivalent to computing
    /// `factor(at:)` and applying the mix inline.
    @inlinable
    public func step(current: Float, target: Float, at fps: Float) -> Float {
        let f = factor(at: fps)
        return f * current + (1 - f) * target
    }
}
