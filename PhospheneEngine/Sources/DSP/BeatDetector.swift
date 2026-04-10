// BeatDetector — 6-band onset detection with adaptive thresholds and tempo estimation.
// Implements the validated onset detection algorithm from the Electron prototype:
// spectral flux per 6 bands, adaptive median threshold, per-band cooldowns,
// grouped beat pulses with exponential decay, and autocorrelation tempo estimation.
// All allocations at init time — per-frame processing is zero-alloc.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BeatDetector")

// MARK: - BeatDetector

/// Detects onsets and estimates tempo from FFT magnitude bins.
///
/// Uses 6-band spectral flux with adaptive median thresholds and per-band cooldowns,
/// producing grouped beat pulses (bass/mid/treble/composite) with exponential decay.
/// Tempo estimation via autocorrelation of the composite onset function.
///
/// Band definitions and tuning constants are from the validated Electron prototype.
public final class BeatDetector: @unchecked Sendable {

    // MARK: - Result

    /// Beat detection output for a single frame.
    public struct Result: Sendable {
        /// Per-band onset flags (6 elements: subBass, lowBass, lowMid, midHigh, highMid, high).
        public var onsets: [Bool]
        /// Grouped bass pulse (subBass OR lowBass onset), 0–1 with decay.
        public var beatBass: Float
        /// Grouped mid pulse (lowMid OR midHigh onset), 0–1 with decay.
        public var beatMid: Float
        /// Grouped treble pulse (highMid OR high onset), 0–1 with decay.
        public var beatTreble: Float
        /// Composite pulse: max of bass/mid/treble.
        public var beatComposite: Float
        /// Estimated tempo in BPM via autocorrelation, nil if insufficient data.
        public var estimatedTempo: Float?
        /// Confidence of autocorrelation tempo estimation, 0–1.
        public var tempoConfidence: Float
        /// Hysteresis-filtered stable BPM from IOI histogram, 0 if not yet stable.
        public var stableBPM: Float
        /// Raw per-second IOI histogram BPM estimate, 0 if not yet computed.
        public var instantBPM: Float
        /// Number of bass onset timestamps in the sliding window (for debugging).
        public var bassOnsetCount: Int
    }

    // MARK: - Band Definitions

    /// 6-band frequency boundaries in Hz.
    private static let bands: [(low: Float, high: Float)] = [
        (20, 80),      // subBass
        (80, 250),     // lowBass
        (250, 1000),   // lowMid
        (1000, 4000),  // midHigh
        (4000, 8000),  // highMid
        (8000, 24000), // high
    ]

    /// Per-band cooldown durations in seconds.
    private static let bandCooldowns: [Float] = [
        0.400, 0.400,  // low bands: 400ms
        0.200, 0.200,  // mid bands: 200ms
        0.150, 0.150,  // high bands: 150ms
    ]

    /// Group cooldown durations in seconds.
    private static let groupCooldowns: [Float] = [0.400, 0.200, 0.150]

    /// Pulse decay rate: pow(0.6813, 30/fps) per frame.
    private static let decayBase: Float = 0.6813

    /// Flux buffer size (50 frames ≈ 0.8s at 60fps).
    private static let fluxBufferSize = 50

    /// Onset history buffer size for tempo estimation (~5s at 60fps).
    private static let onsetHistorySize = 300

    /// Minimum frames before attempting tempo estimation.
    private static let minTempoFrames = 150

    /// Adaptive threshold multiplier: median × this value.
    private static let thresholdMultiplier: Float = 1.5

    // MARK: - Configuration

    public let binCount: Int

    /// Precomputed bin ranges for 6 bands.
    private let bandRanges: [(start: Int, end: Int)]

    // MARK: - State

    /// Previous frame's per-band RMS.
    private var previousBandRMS: [Float]

    /// Whether we have a previous frame.
    private var hasPreviousFrame: Bool = false

    /// Circular buffers for per-band flux history.
    private var fluxBuffers: [[Float]]
    private var fluxHeads: [Int]
    private var fluxCounts: [Int]

    /// Per-band cooldown timers (seconds remaining).
    private var bandCooldownTimers: [Float]

    /// Grouped pulse values (bass, mid, treble).
    private var groupPulses: [Float]

    /// Group cooldown timers (seconds remaining).
    private var groupCooldownTimers: [Float]

    /// Onset history for tempo estimation (composite flux values).
    private var onsetHistory: [Float]
    private var onsetHistoryHead: Int = 0
    private var onsetHistoryCount: Int = 0

    /// Current fps for tempo lag conversion.
    private var currentFps: Float = 60

    /// Debug string from computeStableTempo for diagnostics.
    public private(set) var tempoDebug: String = ""

    // MARK: - Stable Tempo State

    /// Sliding window of onset timestamps (last 10 seconds).
    private static let onsetTimestampWindowSize = 600  // ~10s at 60fps max onsets
    private var onsetTimestamps: [Double]
    private var onsetTimestampHead: Int = 0
    private var onsetTimestampCount: Int = 0

    /// Last 8 per-second tempo estimates for median filtering.
    private static let tempoEstimateBufferSize = 8
    private var tempoEstimates: [Float]
    private var tempoEstimateHead: Int = 0
    private var tempoEstimateCount: Int = 0

    /// Hysteresis-filtered stable BPM.
    private var stableBPM: Float = 0

    /// Raw per-second IOI histogram BPM estimate.
    private var instantBPM: Float = 0

    /// How many consecutive estimates agree with the candidate.
    private var stableConsecutiveCount: Int = 0

    /// The BPM candidate being validated for hysteresis.
    private var candidateBPM: Float = 0

    /// Total elapsed time (seconds) for timestamp tracking.
    private var elapsedTime: Double = 0

    /// When we last computed the IOI-based tempo (once per second).
    private var lastTempoComputeTime: Double = 0

    /// Thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a beat detector.
    ///
    /// - Parameters:
    ///   - binCount: Number of FFT magnitude bins (default 512).
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - fftSize: FFT size (default 1024).
    public init(binCount: Int = 512, sampleRate: Float = 48000, fftSize: Int = 1024) {
        self.binCount = binCount

        let binResolution = sampleRate / Float(fftSize)

        self.bandRanges = Self.bands.map { band in
            let start = max(0, Int(floor(band.low / binResolution)))
            let end = min(binCount, Int(ceil(band.high / binResolution)))
            return (start, end)
        }

        // Pre-allocate all state.
        self.previousBandRMS = [Float](repeating: 0, count: 6)
        self.fluxBuffers = (0..<6).map { _ in [Float](repeating: 0, count: Self.fluxBufferSize) }
        self.fluxHeads = [Int](repeating: 0, count: 6)
        self.fluxCounts = [Int](repeating: 0, count: 6)
        self.bandCooldownTimers = [Float](repeating: 0, count: 6)
        self.groupPulses = [Float](repeating: 0, count: 3)
        self.groupCooldownTimers = [Float](repeating: 0, count: 3)
        self.onsetHistory = [Float](repeating: 0, count: Self.onsetHistorySize)
        self.onsetTimestamps = [Double](repeating: 0, count: Self.onsetTimestampWindowSize)
        self.tempoEstimates = [Float](repeating: 0, count: Self.tempoEstimateBufferSize)

        logger.info("BeatDetector created: \(binCount) bins, 6-band onset detection")
    }

    // MARK: - Processing

    /// Detect onsets and update beat pulses.
    ///
    /// - Parameters:
    ///   - magnitudes: FFT magnitude array.
    ///   - fps: Current frame rate for FPS-independent decay.
    ///   - deltaTime: Seconds since last frame.
    /// - Returns: Onset flags, beat pulses, and tempo estimation.
    public func process(magnitudes: [Float], fps: Float, deltaTime: Float) -> Result {
        lock.lock()
        defer { lock.unlock() }

        let count = min(magnitudes.count, binCount)
        guard count > 0 && fps > 0 && deltaTime > 0 else {
            return Result(
                onsets: [Bool](repeating: false, count: 6),
                beatBass: 0,
                beatMid: 0,
                beatTreble: 0,
                beatComposite: 0,
                estimatedTempo: nil,
                tempoConfidence: 0,
                stableBPM: 0,
                instantBPM: 0,
                bassOnsetCount: 0
            )
        }

        currentFps = fps

        // Compute per-band RMS.
        let currentRMS = computeBandRMS(magnitudes: magnitudes)

        // Compute spectral flux per band (half-wave rectified).
        var bandFlux = [Float](repeating: 0, count: 6)
        if hasPreviousFrame {
            for i in 0..<6 {
                bandFlux[i] = max(0, currentRMS[i] - previousBandRMS[i])
            }
        }

        // Store current RMS for next frame.
        for i in 0..<6 { previousBandRMS[i] = currentRMS[i] }
        hasPreviousFrame = true

        // Update flux buffers and detect onsets.
        var onsets = [Bool](repeating: false, count: 6)

        for i in 0..<6 {
            // Write flux to circular buffer.
            fluxBuffers[i][fluxHeads[i]] = bandFlux[i]
            fluxHeads[i] = (fluxHeads[i] + 1) % Self.fluxBufferSize
            fluxCounts[i] = min(fluxCounts[i] + 1, Self.fluxBufferSize)

            // Decrement cooldown.
            bandCooldownTimers[i] = max(0, bandCooldownTimers[i] - deltaTime)

            // Adaptive threshold: median of buffer × multiplier.
            let threshold = medianOfBuffer(fluxBuffers[i], count: fluxCounts[i]) * Self.thresholdMultiplier

            // Onset detection.
            if bandFlux[i] > threshold && bandCooldownTimers[i] <= 0 && fluxCounts[i] >= 5 {
                onsets[i] = true
                bandCooldownTimers[i] = Self.bandCooldowns[i]
            }
        }

        // Grouped beat pulses.
        // Decay existing pulses.
        let decay = powf(Self.decayBase, 30.0 / fps)
        for i in 0..<3 {
            groupPulses[i] *= decay
            groupCooldownTimers[i] = max(0, groupCooldownTimers[i] - deltaTime)
        }

        // Bass group: subBass (0) OR lowBass (1).
        if (onsets[0] || onsets[1]) && groupCooldownTimers[0] <= 0 {
            groupPulses[0] = 1.0
            groupCooldownTimers[0] = Self.groupCooldowns[0]
        }
        // Mid group: lowMid (2) OR midHigh (3).
        if (onsets[2] || onsets[3]) && groupCooldownTimers[1] <= 0 {
            groupPulses[1] = 1.0
            groupCooldownTimers[1] = Self.groupCooldowns[1]
        }
        // Treble group: highMid (4) OR high (5).
        if (onsets[4] || onsets[5]) && groupCooldownTimers[2] <= 0 {
            groupPulses[2] = 1.0
            groupCooldownTimers[2] = Self.groupCooldowns[2]
        }

        let composite = max(groupPulses[0], max(groupPulses[1], groupPulses[2]))

        // Track elapsed time for stable tempo estimation.
        elapsedTime += Double(deltaTime)

        // Record onset timestamps from strong bass flux peaks for tempo.
        // Use the 75th percentile of the flux buffer as the threshold base.
        // The median of half-wave rectified flux is near-zero (most frames have
        // zero flux), which made the old median-based threshold near-zero and let
        // every positive flux through — the 300ms spacing became the only gate,
        // creating a systematic 97 BPM artifact (310ms IOI → 194 → halved to 97).
        // The 75th percentile is non-zero when there's real activity, and the 2x
        // multiplier ensures only genuine strong beats pass.
        let bassFlux = bandFlux[0] + bandFlux[1]
        let bassP75 = percentileOfBuffer(fluxBuffers[0], count: fluxCounts[0], percentile: 0.75)
                    + percentileOfBuffer(fluxBuffers[1], count: fluxCounts[1], percentile: 0.75)
        let tempoThreshold = bassP75 * 2.0
        if bassFlux > tempoThreshold && fluxCounts[0] >= 5 {
            let lastTs = onsetTimestampCount > 0
                ? onsetTimestamps[(onsetTimestampHead - 1 + Self.onsetTimestampWindowSize)
                                  % Self.onsetTimestampWindowSize]
                : -1.0
            // 150ms minimum spacing = 400 BPM max. Short enough to not alias
            // any real tempo. The threshold does the actual filtering.
            if elapsedTime - lastTs > 0.15 {
                onsetTimestamps[onsetTimestampHead] = elapsedTime
                onsetTimestampHead = (onsetTimestampHead + 1) % Self.onsetTimestampWindowSize
                onsetTimestampCount = min(
                    onsetTimestampCount + 1, Self.onsetTimestampWindowSize
                )
            }
        }

        // Once per second: compute stable tempo via IOI histogram.
        if elapsedTime - lastTempoComputeTime >= 1.0 {
            lastTempoComputeTime = elapsedTime
            computeStableTempo()
        }

        // Update onset history for tempo estimation (composite flux).
        let compositeFlux = bandFlux.reduce(0, +)
        onsetHistory[onsetHistoryHead] = compositeFlux
        onsetHistoryHead = (onsetHistoryHead + 1) % Self.onsetHistorySize
        onsetHistoryCount = min(onsetHistoryCount + 1, Self.onsetHistorySize)

        // Tempo estimation via autocorrelation.
        let (tempo, confidence) = estimateTempo()

        return Result(
            onsets: onsets,
            beatBass: groupPulses[0],
            beatMid: groupPulses[1],
            beatTreble: groupPulses[2],
            beatComposite: composite,
            estimatedTempo: tempo,
            tempoConfidence: confidence,
            stableBPM: stableBPM,
            instantBPM: instantBPM,
            bassOnsetCount: onsetTimestampCount
        )
    }

    /// Reset all internal state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        previousBandRMS = [Float](repeating: 0, count: 6)
        hasPreviousFrame = false
        for i in 0..<6 {
            fluxBuffers[i] = [Float](repeating: 0, count: Self.fluxBufferSize)
            fluxHeads[i] = 0
            fluxCounts[i] = 0
            bandCooldownTimers[i] = 0
        }
        groupPulses = [Float](repeating: 0, count: 3)
        groupCooldownTimers = [Float](repeating: 0, count: 3)
        onsetHistory = [Float](repeating: 0, count: Self.onsetHistorySize)
        onsetHistoryHead = 0
        onsetHistoryCount = 0
        onsetTimestamps = [Double](repeating: 0, count: Self.onsetTimestampWindowSize)
        onsetTimestampHead = 0
        onsetTimestampCount = 0
        tempoEstimates = [Float](repeating: 0, count: Self.tempoEstimateBufferSize)
        tempoEstimateHead = 0
        tempoEstimateCount = 0
        stableBPM = 0
        instantBPM = 0
        stableConsecutiveCount = 0
        candidateBPM = 0
        elapsedTime = 0
        lastTempoComputeTime = 0
    }

    // MARK: - Helpers

    /// Compute RMS of magnitude bins in each of the 6 bands.
    private func computeBandRMS(magnitudes: [Float]) -> [Float] {
        bandRanges.map { range in
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

    /// Compute median of the first `count` elements in a buffer.
    private func medianOfBuffer(_ buffer: [Float], count: Int) -> Float {
        guard count > 0 else { return 0 }
        let slice = Array(buffer.prefix(count)).sorted()
        if count % 2 == 0 {
            return (slice[count / 2 - 1] + slice[count / 2]) / 2.0
        }
        return slice[count / 2]
    }

    /// Compute a given percentile (0–1) of the first `count` elements in a buffer.
    private func percentileOfBuffer(_ buffer: [Float], count: Int, percentile: Float) -> Float {
        guard count > 0 else { return 0 }
        let slice = Array(buffer.prefix(count)).sorted()
        let idx = min(Int(Float(count) * percentile), count - 1)
        return slice[idx]
    }

    // MARK: - Stable Tempo (IOI Histogram)

    /// Compute stable tempo from inter-onset intervals using histogram + hysteresis.
    /// Called once per second from process(). Must be called under lock.
    private func computeStableTempo() {
        // Collect onset timestamps from the last 10 seconds.
        let windowStart = elapsedTime - 10.0
        var recentTimestamps = [Double]()
        recentTimestamps.reserveCapacity(onsetTimestampCount)

        // Diagnostic: track first/last timestamps in buffer for tracing.
        var firstTs: Double = .infinity
        var lastTs: Double = -.infinity

        for i in 0..<onsetTimestampCount {
            let idx = (onsetTimestampHead - onsetTimestampCount + i
                       + Self.onsetTimestampWindowSize) % Self.onsetTimestampWindowSize
            let ts = onsetTimestamps[idx]
            if ts < firstTs { firstTs = ts }
            if ts > lastTs { lastTs = ts }
            if ts >= windowStart {
                recentTimestamps.append(ts)
            }
        }

        guard recentTimestamps.count >= 4 else {
            tempoDebug = String(
                format: "recent<4(%d) e=%.1f ws=%.1f first=%.1f last=%.1f buf=%d",
                recentTimestamps.count,
                elapsedTime,
                windowStart,
                firstTs,
                lastTs,
                onsetTimestampCount
            )
            return
        }

        // Compute inter-onset intervals and histogram into 1-BPM buckets (60–200).
        var histogram = [Int](repeating: 0, count: 141)  // indices 0..140 → BPM 60..200
        var outOfRange = 0
        var inRange = 0

        for i in 1..<recentTimestamps.count {
            let ioi = recentTimestamps[i] - recentTimestamps[i - 1]
            guard ioi > 0.01 else { continue }
            let bpm = 60.0 / ioi
            let bucket = Int(round(bpm)) - 60
            if bucket >= 0 && bucket < 141 {
                histogram[bucket] += 1
                inRange += 1
            } else {
                outOfRange += 1
            }
        }

        // Find peak bucket.
        var peakCount = 0
        var peakBucket = 0
        for i in 0..<141 where histogram[i] > peakCount {
            peakCount = histogram[i]
            peakBucket = i
        }

        guard peakCount >= 2 else {
            tempoDebug = "noPeak(in=\(inRange),out=\(outOfRange),recent=\(recentTimestamps.count))"
            return
        }

        var bestBPM = Float(peakBucket + 60)

        // Octave error correction: find the two strongest peaks. If they're
        // in a ~2:1 ratio, pick the higher one (actual beat rate). Then clamp
        // to 80-160 BPM.
        var secondPeakCount = 0
        var secondPeakBucket = 0
        for idx in 0..<141 {
            if histogram[idx] > secondPeakCount && abs(idx - peakBucket) > 10 {
                secondPeakCount = histogram[idx]
                secondPeakBucket = idx
            }
        }

        let peakBPM1 = Float(peakBucket + 60)
        let peakBPM2 = Float(secondPeakBucket + 60)

        if secondPeakCount > peakCount / 4 {
            let ratio = max(peakBPM1, peakBPM2) / min(peakBPM1, peakBPM2)
            if ratio > 1.8 && ratio < 2.2 {
                // Two peaks in 2:1 ratio — pick the higher BPM (actual beat).
                bestBPM = max(peakBPM1, peakBPM2)
            }
        }

        // Clamp to 80-160 range.
        if bestBPM > 160 { bestBPM /= 2 }
        if bestBPM < 80 { bestBPM *= 2 }

        let newInstant = bestBPM
        instantBPM = newInstant

        // Diagnostic: log successful tempo computation.
        // Show recent count, IOI stats, histogram peak, and pre-clamp BPM.
        let ioiValues = (1..<recentTimestamps.count).map {
            recentTimestamps[$0] - recentTimestamps[$0 - 1]
        }
        let avgIOI = ioiValues.isEmpty ? 0 : ioiValues.reduce(0, +) / Double(ioiValues.count)
        let minIOI = ioiValues.min() ?? 0
        tempoDebug = String(
            format: "ok r=%d bpm=%.0f pk=%d@%d avg_ioi=%.3f min_ioi=%.3f",
            recentTimestamps.count,
            bestBPM,
            peakCount,
            peakBucket + 60,
            avgIOI,
            minIOI
        )

        // Add to tempo estimates circular buffer.
        tempoEstimates[tempoEstimateHead] = newInstant
        tempoEstimateHead = (tempoEstimateHead + 1) % Self.tempoEstimateBufferSize
        tempoEstimateCount = min(tempoEstimateCount + 1, Self.tempoEstimateBufferSize)

        // Compute median of the estimates buffer.
        let validEstimates = Array(tempoEstimates.prefix(tempoEstimateCount)).sorted()
        let median: Float
        if validEstimates.count % 2 == 0 {
            median = (validEstimates[validEstimates.count / 2 - 1]
                      + validEstimates[validEstimates.count / 2]) / 2.0
        } else {
            median = validEstimates[validEstimates.count / 2]
        }

        // Hysteresis: only update stableBPM when filtered estimate agrees for 3+ estimates.
        if abs(median - candidateBPM) <= 5.0 {
            stableConsecutiveCount += 1
        } else {
            candidateBPM = median
            stableConsecutiveCount = 1
        }

        if stableConsecutiveCount >= 3 {
            stableBPM = candidateBPM
        }
    }

    // MARK: - Tempo Estimation

    /// Estimate tempo via autocorrelation of the onset history.
    private func estimateTempo() -> (tempo: Float?, confidence: Float) {
        guard onsetHistoryCount >= Self.minTempoFrames else { return (nil, 0) }

        let fps = currentFps
        guard fps > 0 else { return (nil, 0) }

        // Search BPM range: 60–200 BPM.
        let minLag = Int(60.0 * fps / 200.0)  // ~18 frames at 60fps for 200 BPM
        let maxLag = Int(60.0 * fps / 60.0)   // ~60 frames at 60fps for 60 BPM

        guard minLag > 0 && maxLag > minLag && maxLag < onsetHistoryCount else {
            return (nil, 0)
        }

        // Linearize the circular buffer.
        var linear = [Float](repeating: 0, count: onsetHistoryCount)
        for i in 0..<onsetHistoryCount {
            let idx = (onsetHistoryHead - onsetHistoryCount + i + Self.onsetHistorySize) % Self.onsetHistorySize
            linear[i] = onsetHistory[idx]
        }

        // Autocorrelation for each lag in BPM range.
        var bestCorrelation: Float = 0
        var bestLag = 0

        for lag in minLag...min(maxLag, onsetHistoryCount / 2) {
            var correlation: Float = 0
            let overlapCount = onsetHistoryCount - lag

            // Dot product of signal with itself at offset `lag`.
            vDSP_dotpr(
                linear,
                1,
                Array(linear[lag..<lag + overlapCount]),
                1,
                &correlation,
                vDSP_Length(overlapCount)
            )

            // Normalize by overlap count.
            correlation /= Float(overlapCount)

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        guard bestLag > 0 else { return (nil, 0) }

        var bpm = 60.0 * fps / Float(bestLag)

        // Check if half-lag (double BPM) also has strong correlation.
        // If so, prefer the higher BPM (actual beat, not half-tempo).
        let halfLag = bestLag / 2
        if halfLag >= minLag {
            var halfCorr: Float = 0
            let overlapHalf = onsetHistoryCount - halfLag
            vDSP_dotpr(
                linear,
                1,
                Array(linear[halfLag..<halfLag + overlapHalf]),
                1,
                &halfCorr,
                vDSP_Length(overlapHalf)
            )
            halfCorr /= Float(overlapHalf)
            // If half-lag correlation is at least 60% of best, use it.
            if halfCorr > bestCorrelation * 0.6 {
                bpm = 60.0 * fps / Float(halfLag)
            }
        }

        // Clamp to 80-160 BPM range.
        if bpm > 160 { bpm /= 2 }
        if bpm < 80 { bpm *= 2 }

        // Compute confidence: ratio of best correlation to mean correlation.
        var meanCorrelation: Float = 0
        var count = 0
        for lag in minLag...min(maxLag, onsetHistoryCount / 2) {
            var corr: Float = 0
            let overlapCount = onsetHistoryCount - lag
            vDSP_dotpr(
                linear,
                1,
                Array(linear[lag..<lag + overlapCount]),
                1,
                &corr,
                vDSP_Length(overlapCount)
            )
            corr /= Float(overlapCount)
            meanCorrelation += corr
            count += 1
        }
        meanCorrelation /= Float(max(count, 1))

        let confidence: Float = meanCorrelation > 1e-10
            ? min(bestCorrelation / meanCorrelation / 3.0, 1.0)
            : 0

        return (bpm, confidence)
    }
}
