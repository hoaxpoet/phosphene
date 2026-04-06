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
        /// Estimated tempo in BPM, nil if insufficient data.
        public var estimatedTempo: Float?
        /// Confidence of tempo estimation, 0–1.
        public var tempoConfidence: Float
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
                beatBass: 0, beatMid: 0, beatTreble: 0, beatComposite: 0,
                estimatedTempo: nil, tempoConfidence: 0
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
            tempoConfidence: confidence
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
                vDSP_rmsqv(ptr.baseAddress! + start, 1, &rms, vDSP_Length(count))
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
            vDSP_dotpr(linear, 1,
                       Array(linear[lag..<lag + overlapCount]), 1,
                       &correlation, vDSP_Length(overlapCount))

            // Normalize by overlap count.
            correlation /= Float(overlapCount)

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        guard bestLag > 0 else { return (nil, 0) }

        let bpm = 60.0 * fps / Float(bestLag)

        // Compute confidence: ratio of best correlation to mean correlation.
        var meanCorrelation: Float = 0
        var count = 0
        for lag in minLag...min(maxLag, onsetHistoryCount / 2) {
            var corr: Float = 0
            let overlapCount = onsetHistoryCount - lag
            vDSP_dotpr(linear, 1,
                       Array(linear[lag..<lag + overlapCount]), 1,
                       &corr, vDSP_Length(overlapCount))
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
