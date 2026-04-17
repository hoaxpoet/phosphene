// PitchTracker — YIN autocorrelation-based pitch detector for vocal stems.
//
// Implements the YIN algorithm (de Cheveigné & Kawahara, 2002) using vDSP
// dot-product for the difference function.  No ML required.  The input is
// the separated vocals waveform from StemAnalyzer; pitch estimates are
// written into StemFeatures.vocalsPitchHz / vocalsPitchConfidence.
//
// Algorithm steps (§ references are to the YIN paper):
//   1. Difference function d[τ] = Σ_{j=0}^{W/2−1} (x[j] − x[j+τ])²
//                               = r[0] + r[τ] − 2c[τ]
//      where r[τ] = auto-power of x[τ..τ+halfWindow] and
//            c[τ] = cross-correlation of x[0..halfWindow] × x[τ..τ+halfWindow].
//      Computed via vDSP_dotpr for efficiency.
//   2. CMNDF d'[τ] = d[τ] / ((1/τ) × Σ_{j=1}^{τ} d[j])  with d'[0] = 1.
//   3. Find the first τ in [minTau, maxTau] where d'[τ] < threshold (0.15).
//   4. Parabolic interpolation for sub-sample τ accuracy.
//   5. pitch = sampleRate / τ_refined; valid range 80–1000 Hz.
//   6. Confidence = 1 − d'[τ]; threshold at 0.6 → report 0 Hz if below.
//   7. EMA smoothing (decay 0.8) on valid pitches to suppress jitter.
//      Zero immediately when confidence drops below threshold.
//
// Window: 2048 samples.  τ range: sampleRate/1000 to sampleRate/80.
// At 44.1 kHz: τ ∈ [44, 551] samples.
//
// Performance: each process() call makes 2×(maxTau−minTau+1) vDSP_dotpr
// calls of length halfWindow=1024.  On Apple Silicon (~0.2ms per call).
// Called at ~94 Hz from StemAnalyzer.analyze() under its NSLock.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "PitchTracker")

// MARK: - PitchTracker

/// YIN-based pitch tracker for the separated vocals stem.
///
/// Call `process(waveform:)` once per frame with the latest vocals window.
/// Returns (hz: Float, confidence: Float) where hz = 0 means unvoiced.
public final class PitchTracker: @unchecked Sendable {

    // MARK: - Constants

    private let sampleRate: Float
    private let windowSize: Int = 2048
    private let halfWindow: Int = 1024
    /// CMNDF dip threshold.  Values below this are "confident pitch".
    private let yinThreshold: Float = 0.15
    /// Minimum confidence to report a non-zero Hz value.
    private let confidenceThreshold: Float = 0.6
    /// EMA decay for pitch smoothing on stable voiced segments.
    private static let emaDecay: Float = 0.8

    private let minTau: Int     // sampleRate / maxHz (1000 Hz)
    private let maxTau: Int     // sampleRate / minHz (80 Hz), capped at halfWindow − 2

    // MARK: - State

    private var emaHz: Float = 0
    /// Tracks whether the previous frame was voiced so we can seed the EMA from
    /// rawHz on the first voiced frame after silence instead of smoothing from ~0.
    private var wasVoiced: Bool = false

    // MARK: - Pre-allocated buffers

    private var windowBuffer: [Float]
    private var diffBuffer: [Float]
    private var cmndfBuffer: [Float]

    private let lock = NSLock()

    // MARK: - Init

    /// Create a pitch tracker.
    ///
    /// - Parameter sampleRate: Audio sample rate of the vocals stem (default 44100).
    public init(sampleRate: Float = 44100) {
        self.sampleRate = sampleRate
        // τ range for 80–1000 Hz pitch.
        self.minTau = max(2, Int(sampleRate / 1000.0))
        self.maxTau = min(1022, Int(sampleRate / 80.0))  // cap at halfWindow − 2

        self.windowBuffer = [Float](repeating: 0, count: 2048)
        self.diffBuffer   = [Float](repeating: 0, count: 1024)
        self.cmndfBuffer  = [Float](repeating: 0, count: 1024)

        logger.info("PitchTracker init: sampleRate=\(sampleRate), τ=[\(self.minTau)..\(self.maxTau)]")
    }

    // MARK: - Processing

    /// Run YIN pitch detection on the latest vocals waveform slice.
    ///
    /// - Parameter waveform: Mono PCM samples (any length; last 2048 used, zero-padded if shorter).
    /// - Returns: (hz, confidence).  hz = 0 means unvoiced or below confidence threshold.
    public func process(waveform: [Float]) -> (hz: Float, confidence: Float) {
        lock.lock()
        defer { lock.unlock() }

        guard !waveform.isEmpty else {
            emaHz *= Self.emaDecay
            return (hz: 0, confidence: 0)
        }

        // --- Fill windowBuffer ---
        let available = min(windowSize, waveform.count)
        let srcOffset = waveform.count - available
        let padCount  = windowSize - available

        if padCount > 0 {
            // Zero-pad leading samples.
            withUnsafeMutablePointer(to: &windowBuffer[0]) { ptr in
                ptr.initialize(repeating: 0, count: padCount)
            }
        }
        waveform.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            windowBuffer.withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress else { return }
                (dstBase + padCount).update(from: srcBase + srcOffset, count: available)
            }
        }

        // --- Step 1: Difference function d[τ] ---
        // d[τ] = r0 + r[τ] − 2 × c[τ]
        // r0 = auto-power of x[0..halfWindow]
        // r[τ] = auto-power of x[τ..τ+halfWindow]
        // c[τ] = cross-correlation of x[0..halfWindow] × x[τ..τ+halfWindow]
        var r0: Float = 0
        windowBuffer.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            vDSP_svesq(base, 1, &r0, vDSP_Length(halfWindow))
        }
        diffBuffer[0] = 0

        windowBuffer.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            for tau in 1...maxTau {
                var crossCorr: Float = 0
                var rTau:      Float = 0
                vDSP_dotpr(base,       1, base + tau, 1, &crossCorr, vDSP_Length(halfWindow))
                vDSP_svesq(base + tau, 1, &rTau,         vDSP_Length(halfWindow))
                diffBuffer[tau] = r0 + rTau - 2 * crossCorr
            }
        }

        // --- Step 2: CMNDF ---
        // d'[0] = 1; d'[τ] = d[τ] × τ / Σ_{j=1}^{τ} d[j]
        cmndfBuffer[0] = 1.0
        var runningSum: Float = 0
        for tau in 1...maxTau {
            runningSum += diffBuffer[tau]
            cmndfBuffer[tau] = runningSum > 0
                ? diffBuffer[tau] * Float(tau) / runningSum
                : 1.0
        }

        // --- Step 3: Find first LOCAL MINIMUM below threshold in [minTau, maxTau] ---
        // On crossing the threshold, continue advancing while CMNDF keeps decreasing
        // to land at the valley floor before parabolic interpolation (YIN §2.4).
        // Finding just the first sub-threshold point causes catastrophic parabolic
        // extrapolation because it falls on the descending slope, not the minimum.
        var pitchTau = -1
        var tau = minTau
        while tau <= maxTau {
            if cmndfBuffer[tau] < yinThreshold {
                // Slide down to the local minimum.
                while tau + 1 <= maxTau && cmndfBuffer[tau + 1] <= cmndfBuffer[tau] {
                    tau += 1
                }
                pitchTau = tau
                break
            }
            tau += 1
        }

        guard pitchTau > 1 && pitchTau <= maxTau else {
            // No confident pitch found.
            emaHz *= Self.emaDecay
            return (hz: 0, confidence: 0)
        }

        // --- Step 4: Parabolic interpolation ---
        let prev = cmndfBuffer[pitchTau - 1]
        let curr = cmndfBuffer[pitchTau]
        let next = cmndfBuffer[pitchTau + 1]
        let denom = 2.0 * (prev - 2 * curr + next)
        let refinedTau: Float
        if abs(denom) > 1e-8 {
            let delta = (prev - next) / denom
            refinedTau = Float(pitchTau) + delta
        } else {
            refinedTau = Float(pitchTau)
        }

        // --- Step 5–6: Pitch and confidence ---
        let rawHz = refinedTau > 0 ? sampleRate / refinedTau : 0
        let confidence = max(0, 1.0 - curr)

        // Range gate: outside 80–1000 Hz or low confidence → unvoiced.
        if rawHz < 80 || rawHz > 1000 || confidence < confidenceThreshold {
            emaHz *= Self.emaDecay
            wasVoiced = false
            return (hz: 0, confidence: confidence)
        }

        // --- Step 7: EMA smoothing ---
        // On the first voiced frame after silence, seed the EMA directly from rawHz
        // rather than smoothing from near-zero. The EMA would otherwise report ~0.2×rawHz
        // for the first ~20 frames, producing a wrong-hue flash in pitch-driven visuals.
        if wasVoiced {
            emaHz = emaHz * Self.emaDecay + rawHz * (1 - Self.emaDecay)
        } else {
            emaHz = rawHz
        }
        wasVoiced = true

        return (hz: emaHz, confidence: confidence)
    }

    // MARK: - Reset

    /// Reset pitch EMA state.  Call on track change.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        emaHz = 0
        wasVoiced = false
        logger.info("PitchTracker reset")
    }
}
