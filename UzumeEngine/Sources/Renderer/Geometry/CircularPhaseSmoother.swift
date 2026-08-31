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

    /// Smoothing factor per update.
    ///
    /// ⚠ FTR.30 — THIS COMMENT WAS WRONG AND THE ERROR WAS VISIBLE ON SCREEN. It claimed 0.065
    /// gives "a time constant of roughly a second" at the ~10–18 Hz analysis rate. But the
    /// smoother is called from `MeshGenerator.draw`, which runs at the RENDER rate — 60 Hz — so
    /// the real time constant was 1/(60 × 0.065) ≈ **0.26 s**, four to six times faster than
    /// documented. Measured on Matt's capture `2026-08-18T15-17-10Z`, the hue travelled
    /// **257 °/s** through it (raw: 767 °/s), which is his *"color changes are frequent and
    /// seemingly random."*
    ///
    /// The default is now expressed as a TIME CONSTANT and converted per frame (DYN.4's rule:
    /// widths in seconds, never per-frame alphas — the same class of bug as BUG-089's rate
    /// dependence). τ 3 s takes the same capture to ~33 °/s while the hue still traverses 355°
    /// across the track, so nothing is lost but the flicker.
    public let tau: Float

    /// Per-frame alpha, kept for the tests that drive the smoother without a clock.
    public let alpha: Float

    public init(alpha: Float) {
        self.alpha = min(max(alpha, 0), 1)
        self.tau = 0
    }

    public init(tau: Float = 3.0) {
        self.tau = max(tau, 1e-4)
        self.alpha = 0
    }

    /// Feed the raw phase with the frame's delta. First call seeds exactly, so there is no ramp
    /// from zero at a track change. Uses `tau` when this smoother was built with
    /// one, so the result is independent of the rate it is called at.
    public mutating func smooth(_ raw: Float, deltaTime: Float) -> Float {
        let perFrame = tau > 0 ? 1 - exp(-max(deltaTime, 0) / tau) : alpha
        return smooth(raw, alpha: perFrame)
    }

    public mutating func smooth(_ raw: Float) -> Float {
        smooth(raw, alpha: tau > 0 ? 1 - exp(-(1.0 / 60.0) / tau) : alpha)
    }

    private mutating func smooth(_ raw: Float, alpha: Float) -> Float {
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
