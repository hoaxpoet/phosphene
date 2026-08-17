// TonalAnalyzer — Tonal Interval Vector (TIV) computation (D-178, TONAL.1).
//
// Consumes the 12-bin chroma vector already produced by `ChromaExtractor`
// (MIRPipeline.latestChroma) and emits continuous harmonic-state signals — no
// labels, no ML, no new FFT. A weighted 12-point complex DFT of the chroma
// (Bernardes et al. 2016, ← Harte tonal centroid + Chew spiral array) gives a
// position on the circle of fifths, a consonance magnitude, a tension against
// a decaying tonal center, and a harmonic-change flux (Harte's HCDF).
//
// TONAL is a palette-coherence / long-arc channel, NOT a sync channel: the
// consumers map these to hue / slow macro state, never brightness, and encode
// relationships, never note/chord labels. See docs/TONAL_ANALYSIS_SCOPING.md.
//
// The TIV math (the `weights`) is taken verbatim from Bernardes et al. 2016 /
// the TIVlib reference implementation — do NOT re-derive it.

import Foundation

// MARK: - TonalAnalyzer

/// Per-MIR-frame Tonal Interval Vector analysis. Not thread-safe on its own —
/// driven only from `MIRPipeline.process(...)` on the serial analysis queue,
/// like every other sub-analyzer.
public final class TonalAnalyzer {

    // MARK: - Result

    /// One frame's tonal signals. Maps directly onto the reserved
    /// `FeatureVector` tonal floats (44–48).
    public struct Result: Sendable, Equatable {
        /// `arg T(5)` — position on the circle of fifths, radians −π…π. Hue driver.
        /// Circle-of-fifths phase, EMA-smoothed IN THE COMPLEX PLANE.
        ///
        /// Smoothed at the source rather than by consumers, because the raw argument is
        /// an ANGLE: it wraps at ±π and jumps a median 18.6 % of the circle per update on
        /// real music. A preset keying hue to it renders a colour that sits still and then
        /// flips — measured on Matt's 2026-08-04T17-17-01Z capture, a median frame-to-frame
        /// hue step of 0.0° with a MAXIMUM of 141.7°, which he reported as *"the color of
        /// the trunk and branches is now flashing too much."*
        ///
        /// Averaging the VECTOR (re, im) and taking the argument afterwards is the correct
        /// way to smooth an angle — averaging the angle itself would break at the wrap.
        public var phaseFifths: Float
        /// `arg T(4)` — major-thirds axis, radians −π…π. Major/minor lean.
        public var phaseThirds: Float
        /// `‖T‖ / ‖T‖_max`, 0…1. Saturation + atonality gate (noise → 0).
        public var consonance: Float
        /// Fast-vs-slow center-of-effect distance, 0…1. "How far from home."
        public var tension: Float
        /// Smoothed frame-to-frame TIV distance (HCDF), 0…1. Spikes at chord changes.
        public var harmonicFlux: Float

        public static let zero = Result(
            phaseFifths: 0, phaseThirds: 0, consonance: 0, tension: 0, harmonicFlux: 0
        )
    }

    // MARK: - Constants (Bernardes et al. 2016)

    /// TIV weights `w(k)` for k = 1…6 — VERBATIM from Bernardes et al. 2016 /
    /// TIVlib. k=5 is the circle-of-fifths axis, k=4 the major-thirds axis.
    private static let weights: [Float] = [2, 11, 17, 16, 19, 7]

    /// Max magnitude: a single pitch class gives `|T(k)| = w(k)` ∀k, so
    /// `‖T‖_max = √(Σ w(k)²)` = √1080 ≈ 32.863. The consonance denominator.
    private static let normMax: Float = weights.reduce(0) { $0 + $1 * $1 }.squareRoot()

    // Consonance gate — CALIBRATED from the TONAL.2b pilot (1000 stratified
    // tracks, 2.66M frames; docs/diagnostics/TONAL_PILOT_REPORT.md). Real
    // full-mix consonance is p5≈0.06 / p50≈0.12 / p99≈0.32 (far below an
    // isolated triad's ~0.5 — the chroma is smeared across 12 PCs). The gate
    // must sit at the ATONAL floor (percussion / noise / silence, the p1–p5
    // band 0.018–0.061), NOT the median — the placeholder 0.12 sat at the
    // corpus median and would have gated off half the library.
    /// Consonance below this reads as atonal/percussive → tension & flux gate off.
    private static let consonanceFloor: Float = 0.05   // ≈p3–4: genuine noise/silence floor
    private static let consonanceGateWidth: Float = 0.03  // full signal by 0.08 (≈p22); all genre medians ≥0.10 pass

    /// EMA time constants (seconds). Fast/slow centers of effect for tension;
    /// a short smoother for consonance (so the gate reads "sustained") and flux.
    private static let fastCenterTau: Float = 2.0
    private static let slowCenterTau: Float = 20.0
    private static let consonanceTau: Float = 0.5
    private static let fluxTau: Float = 0.15

    // MARK: - Precomputed DFT basis

    /// `basisRe[k][n]` / `basisIm [k][n]` = `cos/sin(−2π·(k+1)·n / 12)` for the
    /// six coefficients (index 0 → k=1). Weight folded in at accumulation.
    private let basisRe: [[Float]]
    private let basisIm: [[Float]]

    // MARK: - State (reset on track change, D-026 discipline)

    private var fastRe = [Float](repeating: 0, count: 6)
    private var fastIm = [Float](repeating: 0, count: 6)
    private var slowRe = [Float](repeating: 0, count: 6)
    private var slowIm = [Float](repeating: 0, count: 6)
    private var prevRe = [Float](repeating: 0, count: 6)
    private var prevIm = [Float](repeating: 0, count: 6)
    private var smoothedConsonance: Float = 0
    private var smoothedFlux: Float = 0
    private var hasPrev = false

    // MARK: - Init

    public init() {
        var re = [[Float]](repeating: [Float](repeating: 0, count: 12), count: 6)
        var im = [[Float]](repeating: [Float](repeating: 0, count: 12), count: 6)
        for kIdx in 0..<6 {
            let kCoeff = Float(kIdx + 1)
            for pc in 0..<12 {
                let angle = -2.0 * Float.pi * kCoeff * Float(pc) / 12.0
                re[kIdx][pc] = cos(angle)
                im[kIdx][pc] = sin(angle)
            }
        }
        basisRe = re
        basisIm = im
    }

    // MARK: - Process

    /// Compute the tonal signals for one frame.
    ///
    /// - Parameters:
    ///   - chroma: 12-bin chroma (C…B) from `ChromaExtractor` — any scaling; it
    ///     is L1-normalized here so absolute level does not matter.
    ///   - deltaTime: seconds since the last frame (FPS-independent EMAs).
    /// - Returns: the frame's `Result`. Deterministic given identical input.
    public func process(chroma: [Float], deltaTime: Float) -> Result {
        guard chroma.count == 12 else { return .zero }

        // L1-normalize; a silent frame (no pitched energy) decays everything
        // toward the neutral rest state and reports zero consonance.
        let sum = chroma.reduce(0, +)
        guard sum > 1e-6 else {
            decayTowardRest(deltaTime: deltaTime)
            var rest = Result.zero
            rest.consonance = smoothedConsonance
            rest.harmonicFlux = smoothedFlux
            return rest
        }
        let (tRe, tIm) = weightedTIV(chroma, inv: 1.0 / sum)

        // Consonance = ‖T‖ / ‖T‖_max, short-smoothed so the gate reads sustained.
        var mag2: Float = 0
        for kIdx in 0..<6 { mag2 += tRe[kIdx] * tRe[kIdx] + tIm[kIdx] * tIm[kIdx] }
        let consonanceRaw = min(1.0, mag2.squareRoot() / Self.normMax)
        smoothedConsonance += (consonanceRaw - smoothedConsonance) * alpha(Self.consonanceTau, deltaTime)

        // Tension = distance between a fast (~2 s) and slow (~20 s) center of effect.
        let aFast = alpha(Self.fastCenterTau, deltaTime)
        let aSlow = alpha(Self.slowCenterTau, deltaTime)
        var tensionMag2: Float = 0
        for kIdx in 0..<6 {
            fastRe[kIdx] += (tRe[kIdx] - fastRe[kIdx]) * aFast
            fastIm[kIdx] += (tIm[kIdx] - fastIm[kIdx]) * aFast
            slowRe[kIdx] += (tRe[kIdx] - slowRe[kIdx]) * aSlow
            slowIm[kIdx] += (tIm[kIdx] - slowIm[kIdx]) * aSlow
            let dRe = fastRe[kIdx] - slowRe[kIdx]
            let dIm = fastIm[kIdx] - slowIm[kIdx]
            tensionMag2 += dRe * dRe + dIm * dIm
        }
        let tensionRaw = min(1.0, tensionMag2.squareRoot() / Self.normMax)

        // Harmonic flux = smoothed frame-to-frame TIV distance (Harte HCDF).
        var fluxMag2: Float = 0
        if hasPrev {
            for kIdx in 0..<6 {
                let dRe = tRe[kIdx] - prevRe[kIdx]
                let dIm = tIm[kIdx] - prevIm[kIdx]
                fluxMag2 += dRe * dRe + dIm * dIm
            }
        }
        let fluxRaw = min(1.0, fluxMag2.squareRoot() / Self.normMax)
        smoothedFlux += (fluxRaw - smoothedFlux) * alpha(Self.fluxTau, deltaTime)
        prevRe = tRe; prevIm = tIm; hasPrev = true

        // Atonality gate: tension & flux are only meaningful over tonal material.
        let gate = smoothstep(
            Self.consonanceFloor,
            Self.consonanceFloor + Self.consonanceGateWidth,
            smoothedConsonance
        )

        return Result(
            phaseFifths: atan2(tIm[4], tRe[4]),   // k=5, circle of fifths — RAW (BUG-092)
            phaseThirds: atan2(tIm[3], tRe[3]),   // k=4, major thirds
            consonance: smoothedConsonance,
            tension: tensionRaw * gate,
            harmonicFlux: smoothedFlux * gate
        )
    }

    /// Weighted 12-point complex DFT of the L1-normalized chroma, k = 1…6
    /// (Bernardes et al. 2016). `inv` = 1/Σchroma applied per-bin.
    private func weightedTIV(_ chroma: [Float], inv: Float) -> (re: [Float], im: [Float]) {
        var tRe = [Float](repeating: 0, count: 6)
        var tIm = [Float](repeating: 0, count: 6)
        for kIdx in 0..<6 {
            var accRe: Float = 0
            var accIm: Float = 0
            let bRe = basisRe[kIdx], bIm = basisIm[kIdx]
            for pc in 0..<12 {
                let cv = chroma[pc] * inv
                accRe += cv * bRe[pc]
                accIm += cv * bIm[pc]
            }
            let wgt = Self.weights[kIdx]
            tRe[kIdx] = accRe * wgt
            tIm[kIdx] = accIm * wgt
        }
        return (tRe, tIm)
    }

    // BUG-092 — this analyzer emits `phaseFifths` RAW, and every consumer smooths it itself.
    //
    // FTR.3g added a vector EMA here because Fractal Tree read the field straight into hue.
    // FTR.19 (D-209) then gave Fractal Tree its own `CircularPhaseSmoother` — superseding the
    // reason this existed — but the source EMA was never removed, so all four consumers
    // (Witchlight 1.5 s, Nacre ~0.9 s, Cymatic `hueTau`, Fractal Tree D-209) were smoothing an
    // ALREADY-smoothed angle. A cascaded second pole does not just lengthen the time constant;
    // it attenuates fast motion far harder, and Witchlight's harmonic steer — the whole point of
    // the preset — lost 3-4x of its travel: 2.09 -> 0.72, 1.80 -> 1.00, 15.10 -> 3.77 circles
    // per 30 s, with `love_rehab` monotonicity collapsing 0.38 -> 0.24.
    //
    // NOTE the alpha below was a fixed PER-FRAME factor, so its time constant tracked the
    // analysis rate: ~1.5 s live (10-16.4 Hz, BUG-087) but ~0.36 s in the 43.07 Hz offline
    // fixture generator. Consumers smooth on `deltaTime` and do not have that problem, which is
    // the other reason to smooth there rather than here.
    //
    // It stayed invisible for the same reason BUG-090 did: the committed `route_coverage`
    // fixtures predate FTR.3g, so their `tonal_phase_fifths` column is raw and every gate kept
    // passing. Regenerating them is what exposed it. Emitting raw restores each consumer to the
    // single pole it was designed and measured with — Witchlight is back to 2.09 / 1.80 / 15.10
    // against a design of 2.1 / 1.7 / 15.4.
    //
    // The header on `CircularPhaseSmoother` already documented this contract as the intended
    // one ("`tonalPhaseFifths` is a +/-pi sawtooth that `TonalAnalyzer` emits RAW"). It was
    // describing the design, not the code. Now they agree.

    /// Reset all decaying state on track change (D-026 reset discipline).
    public func reset() {
        fastRe = [Float](repeating: 0, count: 6); fastIm = [Float](repeating: 0, count: 6)
        slowRe = [Float](repeating: 0, count: 6); slowIm = [Float](repeating: 0, count: 6)
        prevRe = [Float](repeating: 0, count: 6); prevIm = [Float](repeating: 0, count: 6)
        smoothedConsonance = 0
        smoothedFlux = 0
        hasPrev = false
    }

    // MARK: - Helpers

    /// Decay the emitted (smoothed) signals toward the neutral rest state.
    private func decayTowardRest(deltaTime: Float) {
        smoothedConsonance += (0 - smoothedConsonance) * alpha(Self.consonanceTau, deltaTime)
        smoothedFlux += (0 - smoothedFlux) * alpha(Self.fluxTau, deltaTime)
    }

    /// FPS-independent EMA coefficient for a given time constant.
    private func alpha(_ tau: Float, _ deltaTime: Float) -> Float {
        guard tau > 0, deltaTime > 0 else { return 1 }
        return 1 - exp(-deltaTime / tau)
    }

    /// Hermite smoothstep, matching the shader `smoothstep`.
    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let ss = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return ss * ss * (3 - 2 * ss)
    }
}
