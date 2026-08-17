// CircularPhaseSmoother — the D-209 treatment for a ±π circular primitive, as a reusable type.
//
// WHY THIS EXISTS AS A TYPE. `tonalPhaseFifths` is a ±π sawtooth that `TonalAnalyzer` emits RAW,
// and D-209 is explicit that it must never be EMA'd directly: smooth `sin` and `cos` separately
// and recombine with `atan2`, or the seam produces a jump. Witchlight, Nacre and Cymatic each
// implemented that inline; Fractal Tree did not, and read the raw field straight into hue.
//
// Measured on Matt's capture `2026-08-16T15-59-28Z`, the hue the shader computed moved by
// **144° at p95 and up to 180°** per analysis update, with **8 % of updates jumping more than
// 20°** — roughly 1.5 large colour flips a second. His M7: *"Color changes feel glitchy, not
// intentional."* Through this smoother the same capture reads p95 **2.8°**.
//
// ⚠ AND THE HARNESS HID IT. `FractalTreeMeshRenderTest` applied its own circular smoother inside
// `featuresFromSession`, so every offline render and contact sheet showed the smooth version
// while production shipped the raw one. A harness that "fixes up" an input is not replaying the
// production path — same species as the `advanceBeatHold` glide-seed bug (FTR.18).

import Foundation

// MARK: - CircularPhaseSmoother

/// Exponential smoothing of a circular quantity, correct across the ±π seam.
public struct CircularPhaseSmoother: Sendable {

    private var re: Float = 0
    private var im: Float = 0
    private var seeded = false

    /// Smoothing factor per update. 0.065 matches the value the Fractal Tree harness has used
    /// since FTR.2 — at the ~10–18 Hz analysis rate that is a time constant of roughly a second,
    /// slow enough to remove the seam jumps and fast enough to follow a real key change.
    public let alpha: Float

    public init(alpha: Float = 0.065) { self.alpha = min(max(alpha, 0), 1) }

    /// Feed the raw ±π phase, get the smoothed ±π phase. First call seeds exactly, so there is no
    /// ramp from zero at a track change.
    public mutating func smooth(_ raw: Float) -> Float {
        let rawRe = cos(raw), rawIm = sin(raw)
        if !seeded {
            re = rawRe; im = rawIm; seeded = true
        } else {
            re = alpha * rawRe + (1 - alpha) * re
            im = alpha * rawIm + (1 - alpha) * im
        }
        return atan2(im, re)
    }

    /// Drop the history — call on a track change so a new key does not glide in from the old one.
    public mutating func reset() { re = 0; im = 0; seeded = false }
}
