// PitchTracker — YIN autocorrelation-based pitch detector for vocal stems.
//
// Implements the YIN algorithm (de Cheveigné & Kawahara, 2002) using vDSP
// dot-product for the difference function.  No ML required.  The input is
// the separated vocals waveform from StemAnalyzer; pitch estimates are
// written into StemFeatures.vocalsPitchHz / vocalsPitchConfidence.
//
// **2026-05-19 fix (P0 — vocalsPitchConfidence was 0 % in every session).**
// The tracker accumulates incoming samples into an internal 2048-sample
// ring buffer; YIN runs on the full buffer once it's been filled at least
// once. Callers can pass any window size (live path: 1024; SessionPreparer:
// 1024; unit tests: 2048+) and the tracker reassembles a valid YIN window
// across calls. Before the fix, the live caller passed 1024-sample windows
// directly to YIN — `fillWindow()` zero-padded the first half of the
// internal buffer, making the cross-correlation in the difference function
// structurally zero (`base[0..1024]` was all zeros, so dotpr = 0 for every
// τ), so the CMNDF never dipped below the 0.15 threshold and `findMinimum`
// always returned -1 → `(hz: 0, confidence: 0)` every frame. The bug was
// invisible to PitchTrackerTests because the tests pass full 2048-sample
// windows directly. Same test/prod parity gap as Aurora Veil's recent
// cascade — CLAUDE.md "test in production-grade pipeline" rule applies.
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

    /// Total samples accumulated into `windowBuffer` since the last `reset()`,
    /// saturating at `windowSize`. YIN only runs once the buffer has been
    /// filled at least once — before that, the older half of the ring buffer
    /// holds the zero-initialised baseline and the correlation would be
    /// degenerate (this was the pre-2026-05-19 bug).
    private var samplesAccumulated: Int = 0

    // MARK: - Pre-allocated buffers

    /// 2048-sample ring buffer. Callers can pass any window size to `process`;
    /// each call shifts older samples left and appends the incoming chunk at
    /// the tail. YIN reads the full buffer once `samplesAccumulated >= windowSize`.
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

        appendToRingBuffer(waveform)
        // YIN requires a full 2048-sample window. Before the buffer has been
        // filled at least once, the older half holds the zero-initialised
        // baseline and the correlation is degenerate (this was the
        // pre-2026-05-19 bug — the live path passed 1024-sample windows
        // directly so half the buffer was always zeros).
        guard samplesAccumulated >= windowSize else {
            return (hz: 0, confidence: 0)
        }

        computeDifferenceFunction()
        computeCMNDF()

        let pitchTau = findMinimum()
        guard pitchTau > 1 && pitchTau <= maxTau else {
            emaHz *= Self.emaDecay
            return (hz: 0, confidence: 0)
        }

        let refinedTau = parabolicRefinement(at: pitchTau)
        let rawHz      = refinedTau > 0 ? sampleRate / refinedTau : 0
        let confidence = max(0, 1.0 - cmndfBuffer[pitchTau])

        if rawHz < 80 || rawHz > 1000 || confidence < confidenceThreshold {
            emaHz *= Self.emaDecay
            wasVoiced = false
            return (hz: 0, confidence: confidence)
        }

        // On the first voiced frame after silence, seed from rawHz (not from near-zero EMA).
        if wasVoiced {
            emaHz = emaHz * Self.emaDecay + rawHz * (1 - Self.emaDecay)
        } else {
            emaHz = rawHz
        }
        wasVoiced = true
        return (hz: emaHz, confidence: confidence)
    }

    // MARK: - YIN Algorithm Steps

    /// Append incoming waveform samples to the internal ring buffer, shifting
    /// older samples left to make room. The buffer always holds the most
    /// recent `windowSize` samples after this call. Callers can pass any
    /// number of samples — 1024 (live path / SessionPreparer), 2048 (unit
    /// tests), or anything else — and the accumulator produces a valid YIN
    /// window over multiple calls.
    private func appendToRingBuffer(_ waveform: [Float]) {
        let incoming = waveform.count
        if incoming >= windowSize {
            // Incoming is larger than the buffer — replace entirely with the
            // most recent `windowSize` samples.
            let srcOffset = incoming - windowSize
            waveform.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                windowBuffer.withUnsafeMutableBufferPointer { dst in
                    guard let dstBase = dst.baseAddress else { return }
                    dstBase.update(from: srcBase + srcOffset, count: windowSize)
                }
            }
            samplesAccumulated = windowSize
            return
        }
        // Shift existing buffer left by `incoming` samples to discard the
        // oldest data, then copy the new samples to the freed tail.
        let keepCount = windowSize - incoming
        windowBuffer.withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress else { return }
            // memmove-style shift (handles overlap correctly).
            for i in 0..<keepCount {
                dstBase[i] = dstBase[i + incoming]
            }
        }
        waveform.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            windowBuffer.withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress else { return }
                (dstBase + keepCount).update(from: srcBase, count: incoming)
            }
        }
        samplesAccumulated = min(windowSize, samplesAccumulated + incoming)
    }

    private func computeDifferenceFunction() {
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
                var rTau: Float = 0
                vDSP_dotpr(base, 1, base + tau, 1, &crossCorr, vDSP_Length(halfWindow))
                vDSP_svesq(base + tau, 1, &rTau, vDSP_Length(halfWindow))
                diffBuffer[tau] = r0 + rTau - 2 * crossCorr
            }
        }
    }

    private func computeCMNDF() {
        cmndfBuffer[0] = 1.0
        var runningSum: Float = 0
        for tau in 1...maxTau {
            runningSum += diffBuffer[tau]
            cmndfBuffer[tau] = runningSum > 0
                ? diffBuffer[tau] * Float(tau) / runningSum
                : 1.0
        }
    }

    /// Returns the τ at the first CMNDF local minimum below `yinThreshold`, or -1 if none found.
    private func findMinimum() -> Int {
        var tau = minTau
        while tau <= maxTau {
            if cmndfBuffer[tau] < yinThreshold {
                while tau + 1 <= maxTau && cmndfBuffer[tau + 1] <= cmndfBuffer[tau] {
                    tau += 1
                }
                return tau
            }
            tau += 1
        }
        return -1
    }

    private func parabolicRefinement(at tau: Int) -> Float {
        let prev = cmndfBuffer[tau - 1]
        let curr = cmndfBuffer[tau]
        let next = cmndfBuffer[tau + 1]
        let denom = 2.0 * (prev - 2 * curr + next)
        guard abs(denom) > 1e-8 else { return Float(tau) }
        return Float(tau) + (prev - next) / denom
    }

    // MARK: - Reset

    /// Reset pitch EMA state. Call on track change.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        emaHz = 0
        wasVoiced = false
        samplesAccumulated = 0
        // Clear the ring buffer so the next track doesn't carry residual
        // samples from the previous one.
        for i in 0..<windowBuffer.count { windowBuffer[i] = 0 }
        logger.info("PitchTracker reset")
    }
}
