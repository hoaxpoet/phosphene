// BandEnergyProcessor — 3-band and 6-band energy extraction with AGC and smoothing.
// Computes bass/mid/treble (instant + attenuated) and 6-band energy from FFT magnitudes.
// Uses Milkdrop-style average-tracking AGC and FPS-independent smoothing.
// All allocations happen at init time — per-frame processing is zero-alloc.

import Foundation
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BandEnergyProcessor")

// MARK: - BandEnergyProcessor

/// Extracts 3-band and 6-band energy from FFT magnitudes with AGC and smoothing.
///
/// Band definitions (from validated Electron prototype):
/// - **3-band**: Bass 20–250 Hz, Mid 250–4000 Hz, Treble 4000–20000 Hz
/// - **6-band**: Sub Bass 20–80, Low Bass 80–250, Low Mid 250–1000,
///   Mid High 1000–4000, High Mid 4000–8000, High 8000+
///
/// AGC normalizes output so average levels map to ~0.5, loud moments reach 0.8–1.0.
/// Smoothing is FPS-independent via `pow(rate, 30/fps)`.
public final class BandEnergyProcessor: @unchecked Sendable {

    // MARK: - Result

    /// Band energy output for a single frame.
    public struct Result: Sendable {
        // 3-band instant (fast smoothing)
        public var bass: Float
        public var mid: Float
        public var treble: Float

        // 3-band attenuated (heavy smoothing, slow-flowing motion)
        public var bassAtt: Float
        public var midAtt: Float
        public var trebleAtt: Float

        // 6-band (preserves relative differences via total-energy AGC)
        public var subBass: Float
        public var lowBass: Float
        public var lowMid: Float
        public var midHigh: Float
        public var highMid: Float
        public var high: Float

        /// All-zero result, returned when there is no input or fps is invalid.
        public static let zero = Result(
            bass: 0,
            mid: 0,
            treble: 0,
            bassAtt: 0,
            midAtt: 0,
            trebleAtt: 0,
            subBass: 0,
            lowBass: 0,
            lowMid: 0,
            midHigh: 0,
            highMid: 0,
            high: 0
        )
    }

    // MARK: - Band Definitions

    /// Named frequency band with a low/high cutoff in Hz.
    private struct BandRange {
        let name: String
        let low: Float
        let high: Float
    }

    /// 3-band frequency boundaries in Hz.
    private static let bands3: [BandRange] = [
        BandRange(name: "bass", low: 20, high: 250),
        BandRange(name: "mid", low: 250, high: 4000),
        BandRange(name: "treble", low: 4000, high: 20000),
    ]

    /// 6-band frequency boundaries in Hz.
    private static let bands6: [BandRange] = [
        BandRange(name: "subBass", low: 20, high: 80),
        BandRange(name: "lowBass", low: 80, high: 250),
        BandRange(name: "lowMid", low: 250, high: 1000),
        BandRange(name: "midHigh", low: 1000, high: 4000),
        BandRange(name: "highMid", low: 4000, high: 8000),
        BandRange(name: "high", low: 8000, high: 24000),
    ]

    /// Instant smoothing rates per 3-band (FPS-independent, 30 fps reference).
    private static let instantSmoothers: [Smoother] = [
        Smoother(rate30: 0.65),
        Smoother(rate30: 0.75),
        Smoother(rate30: 0.75)
    ]

    /// Attenuated smoothing rate (heavy smoothing, FPS-independent).
    private static let attenuatedSmoother = Smoother(rate30: 0.95)

    /// 6-band rates share their parent 3-band's smoother.
    /// Order: sub_bass, low_bass, low_mid, mid_high, high_mid, high.
    private static let sixBandSmoothers: [Smoother] = [
        instantSmoothers[0], instantSmoothers[0],   // sub_bass, low_bass → bass rate
        instantSmoothers[1], instantSmoothers[1],   // low_mid, mid_high → mid rate
        instantSmoothers[2], instantSmoothers[2],   // high_mid, high → treble rate
    ]

    // MARK: - Configuration

    public let binCount: Int
    public let sampleRate: Float

    /// Whether the cold-start peak floor (BUG-029 re-open / AGC3.6) is active. Only the **main-mix**
    /// processor (MIRPipeline) sets this — it's what feeds `f.bass` to continuous-energy presets. The
    /// per-stem processors (StemAnalyzer) leave it off: stems have their own cold-start seeding
    /// (BUG-018) and the floor would suppress their energy during the window.
    private let applyColdStartFloor: Bool

    /// Precomputed bin ranges for 3-band: [(startBin, endBin)] exclusive end.
    private let bandRanges3: [(start: Int, end: Int)]

    /// Precomputed bin ranges for 6-band.
    private let bandRanges6: [(start: Int, end: Int)]

    // MARK: - AGC State

    /// Running average for 6-band AGC (total energy, not per-band).
    private var agcRunningAvg: Float = 0

    /// Frame counter for two-speed warmup.
    private var frameCount: Int = 0

    /// Consecutive near-silent frames since the last audible frame (D-148 / BUG-029). Drives the
    /// hold-through-silence gate so only *sustained* silence (an inter-track gap) holds the running
    /// average; brief within-track gaps decay as before.
    private var silentRun: Int = 0

    /// Audible frames since the cold-start window armed (BUG-029 re-open / AGC3.6). The peak floor
    /// below is active while this is < the window length; the window re-arms at each track start
    /// (seed / silence-emergence). −1 means unarmed.
    private var coldStartFrames: Int = -1

    /// Max total energy seen during the current cold-start window (BUG-029 re-open / AGC3.6).
    private var coldStartPeak: Float = 0

    /// Number of frames for fast warmup phase (~1s at 60fps).
    private static let warmupFastFrames = 60

    /// Number of frames for moderate warmup phase (~3s at 60fps).
    private static let warmupModerateFrames = 180

    /// Fast warmup rate.
    private static let agcRateFast: Float = 0.95

    /// Moderate rate after warmup.
    private static let agcRateModerate: Float = 0.992

    /// D-148 / BUG-029 — near-silence threshold as a fraction of the running average. A frame whose
    /// total energy is below this fraction of `agcRunningAvg` is "near-silent." Relative
    /// (self-calibrating) so it never fires during continuous music (where total ≈ average); 0.02 is
    /// ~34 dB below the running level — well into silence / inter-track-gap territory.
    private static let silenceFraction: Float = 0.02

    /// D-148 / BUG-029 — frames of *sustained* near-silence before the running average is HELD
    /// (instead of decayed toward zero). This distinguishes an inter-track gap (sustained silence,
    /// the spike's cause) from a within-track between-beat gap (a few frames of silence in sparse
    /// music — which must keep decaying exactly as before, or sparse-pattern band values shift).
    /// 30 frames ≈ 0.5 s at 60 fps: longer than any musical between-beat gap, far shorter than the
    /// multi-second inter-track silences AGC3.1 measured. Below this count, behaviour is byte-
    /// identical to the prior algorithm.
    private static let sustainedSilenceFrames = 30

    /// BUG-029 re-open (AGC3.6) — cold-start peak floor. The D-148 fix (seed-from-first-audible)
    /// stopped the first-FRAME explosion but NOT the residual the M7 (2026-06-09) exposed: when a
    /// track opens with a QUIET intro, the meter seeds off the intro, so the first LOUD bass hit ~1 s
    /// later — while the meter is still converged low — inflates (live f.bass 3.8). Through Ferrofluid
    /// Ocean's `1.0 + 0.8·clamp(f.bass,0,1)` that holds the spikes at full height for ~0.3 s.
    ///
    /// Fix: during a per-track cold-start *window*, floor the AGC denominator at a fraction of the
    /// loudest energy seen so far, so a sudden loud hit divides by ~its own peak instead of the quiet
    /// intro's average. The floor only BINDS when the running average is far below the peak (a quiet→
    /// loud jump) — for constant-amplitude input it never binds (peak ≈ average), so steady-state and
    /// constant-cold-start are byte-identical; only the quiet-intro→loud-hit case changes. The window
    /// is wall-clock (×fps) and re-arms each track, so it never touches steady state.
    private static let coldStartWindowSeconds: Float = 2.5
    /// Floor = this × the cold-start peak energy. Tuned on the REAL M7 audio (raw_tap.wav, Battles
    /// "SZ2", `tools/agc3/`): un-fixed the first loud hit reads f.bass ≈ 1.67 and locks FFO at max
    /// spike height for ~0.8 s; this floor removes the lock at any value ≥ 0.20. The first-hit reading
    /// scales inversely — 0.20→0.87, 0.25→0.70, 0.30→0.60, 0.60→0.32 (too muted). 0.25 keeps the hit
    /// clearly responsive (≈85 % of full FFO height) without the max-lock. Higher → more muted; lower
    /// → closer to the clamp ceiling. Final value is an M7 (render) call.
    private static let coldStartPeakFraction: Float = 0.25

    // MARK: - Smoothing State

    /// Smoothed 3-band instant values.
    private var smoothedInstant: [Float] = [0, 0, 0]

    /// Smoothed 3-band attenuated values.
    private var smoothedAttenuated: [Float] = [0, 0, 0]

    /// Smoothed 6-band values.
    private var smoothed6Band: [Float] = [0, 0, 0, 0, 0, 0]

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a band energy processor.
    ///
    /// - Parameters:
    ///   - binCount: Number of FFT magnitude bins (default 512).
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - fftSize: FFT size (default 1024).
    ///   - applyColdStartFloor: Enable the cold-start peak floor (main-mix only; default false).
    public init(binCount: Int = 512, sampleRate: Float = 48000, fftSize: Int = 1024,
                applyColdStartFloor: Bool = false) {
        self.binCount = binCount
        self.sampleRate = sampleRate
        self.applyColdStartFloor = applyColdStartFloor

        let binResolution = sampleRate / Float(fftSize)

        // Precompute bin ranges for each band.
        self.bandRanges3 = Self.bands3.map { band in
            let start = max(0, Int(floor(band.low / binResolution)))
            let end = min(binCount, Int(ceil(band.high / binResolution)))
            return (start, end)
        }

        self.bandRanges6 = Self.bands6.map { band in
            let start = max(0, Int(floor(band.low / binResolution)))
            let end = min(binCount, Int(ceil(band.high / binResolution)))
            return (start, end)
        }

        logger.info("BandEnergyProcessor created: \(binCount) bins, 3+6 bands")
    }

    // MARK: - Processing

    /// Compute band energies from FFT magnitude bins.
    ///
    /// - Parameters:
    ///   - magnitudes: FFT magnitude array (should have `binCount` elements).
    ///   - fps: Current frame rate for FPS-independent smoothing.
    /// - Returns: 3-band instant, 3-band attenuated, and 6-band energy values.
    public func process(magnitudes: [Float], fps: Float) -> Result {
        lock.lock()
        defer { lock.unlock() }

        let count = min(magnitudes.count, binCount)
        guard count > 0 && fps > 0 else { return .zero }

        // Compute raw RMS for each band.
        let raw3 = computeRawEnergy(magnitudes: magnitudes, ranges: bandRanges3)
        let raw6 = computeRawEnergy(magnitudes: magnitudes, ranges: bandRanges6)

        // AGC: normalize 6-band against total energy.
        //
        // D-148 / BUG-029 — ease the meter in at each track start. Two cold-start/silence-only
        // changes stop the first audible frame from over-scaling (which spiked f.bass to ~4.0 and
        // popped continuous-energy presets like Ferrofluid Ocean at every track onset):
        //   • seed-from-first-audible — don't seed off leading silence. The old `max(E,1e-6)` at
        //     frame 0 seeded ~0 off the silent pre-roll, so the next audible frame divided by ~0.
        //     Defer the seed until the first frame with energy, then seed from it (mirrors
        //     StemAnalyzer / SAR.1 / BandDeviationTracker).
        //   • hold-through-sustained-silence — across an inter-track gap the running average would
        //     decay toward zero, leaving a tiny denominator for the next onset to over-scale against.
        //     After `sustainedSilenceFrames` consecutive near-silent frames, HOLD the average instead.
        //     The gate matters: a few frames of silence between beats in sparse music must keep
        //     decaying exactly as before (or sparse-pattern band values shift), so only *sustained*
        //     silence (a real track gap) holds.
        // For continuous audible input (frame-0 energy > 1e-6, no sustained sub-`silenceFraction`
        // run) this is byte-identical to the prior algorithm — seed == max(E,1e-6), same EMA, same
        // rate — so the total-energy AGC's mix-density-stability response (D-026) is untouched. The
        // behaviour changes ONLY across a sustained silence (output ~0 there) and in the immediate
        // post-gap ease-in. Regression-locked by AGC3ColdStartSpikeTests.
        let totalRawEnergy = raw6.reduce(0, +)
        let agcRate = frameCount < Self.warmupFastFrames ? Self.agcRateFast : Self.agcRateModerate
        let nearSilent = agcRunningAvg != 0 && totalRawEnergy < Self.silenceFraction * agcRunningAvg
        let wasUnseeded = agcRunningAvg == 0
        let wasSustainedSilence = silentRun >= Self.sustainedSilenceFrames
        silentRun = nearSilent ? silentRun + 1 : 0

        if agcRunningAvg == 0 {
            // Unseeded (session start / pre-audio): seed from the first audible frame, not silence.
            if totalRawEnergy > 0 { agcRunningAvg = totalRawEnergy }
        } else if nearSilent && silentRun >= Self.sustainedSilenceFrames {
            // Sustained silence (inter-track gap): hold the running average (no decay toward zero).
        } else {
            agcRunningAvg = agcRate * agcRunningAvg + (1 - agcRate) * totalRawEnergy
        }

        // The AGC denominator — `agcRunningAvg`, floored during the cold-start window (main-mix only).
        let effectiveAvg = coldStartFlooredAvg(
            totalRawEnergy: totalRawEnergy,
            agcRunningAvg: agcRunningAvg,
            fps: fps,
            wasUnseeded: wasUnseeded,
            wasSustainedSilence: wasSustainedSilence
        )
        let agcScale: Float = effectiveAvg > 1e-10 ? 0.5 / effectiveAvg : 0

        // Apply AGC to both 3-band and 6-band.
        let agc3 = raw3.map { $0 * agcScale }
        let agc6 = raw6.map { $0 * agcScale }

        // FPS-independent smoothing via Shared/Smoother.
        let attRate = Self.attenuatedSmoother.factor(at: fps)
        for i in 0..<3 {
            let instantRate = Self.instantSmoothers[i].factor(at: fps)
            smoothedInstant[i] = instantRate * smoothedInstant[i] + (1 - instantRate) * agc3[i]
            smoothedAttenuated[i] = attRate * smoothedAttenuated[i] + (1 - attRate) * agc3[i]
        }

        for i in 0..<6 {
            let rate = Self.sixBandSmoothers[i].factor(at: fps)
            smoothed6Band[i] = rate * smoothed6Band[i] + (1 - rate) * agc6[i]
        }

        frameCount += 1

        return Result(
            bass: smoothedInstant[0],
            mid: smoothedInstant[1],
            treble: smoothedInstant[2],
            bassAtt: smoothedAttenuated[0],
            midAtt: smoothedAttenuated[1],
            trebleAtt: smoothedAttenuated[2],
            subBass: smoothed6Band[0],
            lowBass: smoothed6Band[1],
            lowMid: smoothed6Band[2],
            midHigh: smoothed6Band[3],
            highMid: smoothed6Band[4],
            high: smoothed6Band[5]
        )
    }

    /// Reset all internal state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        agcRunningAvg = 0
        frameCount = 0
        silentRun = 0
        coldStartFrames = -1
        coldStartPeak = 0
        smoothedInstant = [0, 0, 0]
        smoothedAttenuated = [0, 0, 0]
        smoothed6Band = [0, 0, 0, 0, 0, 0]
    }

    // MARK: - Helpers

    /// The AGC denominator with the cold-start peak floor applied (BUG-029 re-open / AGC3.6). During
    /// a per-track cold-start window (main-mix processor only — `applyColdStartFloor`), floor
    /// `agcRunningAvg` at `coldStartPeakFraction × (loudest energy seen)`, so a loud hit after a quiet
    /// intro divides by ~its own peak (reads "loud" once) instead of the quiet average (inflates → FFO
    /// locks at max). Binds ONLY on a quiet→loud jump (avg ≪ peak) and self-releases as the running
    /// average catches up; for constant input it never binds, so steady-state stays byte-identical.
    /// Off for the per-stem processors (BUG-018 owns their cold-start; the floor would suppress stem
    /// energy in the window). Mutates the window state; call once per frame.
    private func coldStartFlooredAvg(totalRawEnergy: Float, agcRunningAvg: Float, fps: Float,
                                     wasUnseeded: Bool, wasSustainedSilence: Bool) -> Float {
        guard applyColdStartFloor else { return agcRunningAvg }
        // Arm the window at each track start: first audible frame after unseeded (session-start /
        // per-track reset) or after a sustained silence (inter-track gap).
        if totalRawEnergy > 0 && (wasUnseeded || wasSustainedSilence) {
            coldStartFrames = 0
            coldStartPeak = totalRawEnergy
        }
        guard coldStartFrames >= 0 else { return agcRunningAvg }
        coldStartPeak = max(coldStartPeak, totalRawEnergy)
        let floored = max(agcRunningAvg, Self.coldStartPeakFraction * coldStartPeak)
        if totalRawEnergy > 0 { coldStartFrames += 1 }
        if Float(coldStartFrames) >= Self.coldStartWindowSeconds * fps { coldStartFrames = -1 }
        return floored
    }

    /// Compute RMS energy for each band from magnitude bins.
    private func computeRawEnergy(magnitudes: [Float], ranges: [(start: Int, end: Int)]) -> [Float] {
        ranges.map { range in
            let start = range.start
            let end = min(range.end, magnitudes.count)
            let count = end - start
            guard count > 0 else { return Float(0) }

            var rms: Float = 0
            magnitudes.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(count))
            }
            return rms
        }
    }
}
