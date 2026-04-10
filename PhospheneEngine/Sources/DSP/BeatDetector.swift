// BeatDetector — 6-band onset detection with adaptive thresholds and tempo estimation.
// Spectral flux per 6 bands, adaptive median threshold, per-band cooldowns,
// grouped beat pulses with exponential decay. Zero-alloc per-frame processing.

import Foundation
import Accelerate
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BeatDetector")

// MARK: - BeatDetector

/// Detects onsets and estimates tempo from FFT magnitude bins using 6-band spectral flux
/// with adaptive median thresholds, per-band cooldowns, and grouped beat pulses with
/// exponential decay. Band definitions and tuning constants from the Electron prototype.
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
    static let onsetHistorySize = 300

    /// Minimum frames before attempting tempo estimation.
    static let minTempoFrames = 150

    /// Adaptive threshold multiplier: median × this value.
    private static let thresholdMultiplier: Float = 1.5

    // MARK: - Configuration

    public let binCount: Int

    /// Precomputed bin ranges for 6 bands.
    let bandRanges: [(start: Int, end: Int)]

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
    var onsetHistory: [Float]
    var onsetHistoryHead: Int = 0
    var onsetHistoryCount: Int = 0

    /// Current fps for tempo lag conversion.
    var currentFps: Float = 60

    /// Debug string from computeStableTempo for diagnostics.
    public var tempoDebug: String = ""

    // MARK: - Stable Tempo State

    /// Sliding window of onset timestamps (last 10 seconds).
    static let onsetTimestampWindowSize = 600  // ~10s at 60fps max onsets
    var onsetTimestamps: [Double]
    var onsetTimestampHead: Int = 0
    var onsetTimestampCount: Int = 0

    /// Last 8 per-second tempo estimates for median filtering.
    static let tempoEstimateBufferSize = 8
    var tempoEstimates: [Float]
    var tempoEstimateHead: Int = 0
    var tempoEstimateCount: Int = 0

    /// Hysteresis-filtered stable BPM.
    var stableBPM: Float = 0

    /// Raw per-second IOI histogram BPM estimate.
    var instantBPM: Float = 0

    /// How many consecutive estimates agree with the candidate.
    var stableConsecutiveCount: Int = 0

    /// The BPM candidate being validated for hysteresis.
    var candidateBPM: Float = 0

    /// Total elapsed time (seconds) for timestamp tracking.
    var elapsedTime: Double = 0

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

        // Compute per-band spectral flux.
        let bandFlux = computeBandFlux(magnitudes: magnitudes)

        // Detect per-band onsets from flux.
        let onsets = detectOnsets(bandFlux: bandFlux, deltaTime: deltaTime)

        // Update grouped beat pulses.
        let composite = updateGroupPulses(onsets: onsets, fps: fps, deltaTime: deltaTime)

        // Track elapsed time and record onset timestamps for tempo.
        elapsedTime += Double(deltaTime)
        recordOnsetTimestamps(bandFlux: bandFlux)

        // Once per second: compute stable tempo via IOI histogram.
        if elapsedTime - lastTempoComputeTime >= 1.0 {
            lastTempoComputeTime = elapsedTime
            computeStableTempo()
        }

        // Update onset history and estimate tempo via autocorrelation.
        updateOnsetHistory(bandFlux: bandFlux)
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

    // MARK: - Process Helpers

    /// Compute half-wave rectified spectral flux per band.
    private func computeBandFlux(magnitudes: [Float]) -> [Float] {
        let currentRMS = computeBandRMS(magnitudes: magnitudes)

        var bandFlux = [Float](repeating: 0, count: 6)
        if hasPreviousFrame {
            for i in 0..<6 {
                bandFlux[i] = max(0, currentRMS[i] - previousBandRMS[i])
            }
        }

        for i in 0..<6 { previousBandRMS[i] = currentRMS[i] }
        hasPreviousFrame = true
        return bandFlux
    }

    /// Detect per-band onsets from spectral flux values.
    private func detectOnsets(bandFlux: [Float], deltaTime: Float) -> [Bool] {
        var onsets = [Bool](repeating: false, count: 6)

        for i in 0..<6 {
            fluxBuffers[i][fluxHeads[i]] = bandFlux[i]
            fluxHeads[i] = (fluxHeads[i] + 1) % Self.fluxBufferSize
            fluxCounts[i] = min(fluxCounts[i] + 1, Self.fluxBufferSize)

            bandCooldownTimers[i] = max(0, bandCooldownTimers[i] - deltaTime)

            let threshold = medianOfBuffer(
                fluxBuffers[i], count: fluxCounts[i]
            ) * Self.thresholdMultiplier

            if bandFlux[i] > threshold && bandCooldownTimers[i] <= 0
                && fluxCounts[i] >= 5 {
                onsets[i] = true
                bandCooldownTimers[i] = Self.bandCooldowns[i]
            }
        }
        return onsets
    }

    /// Update grouped beat pulses (bass/mid/treble) and return composite.
    private func updateGroupPulses(
        onsets: [Bool], fps: Float, deltaTime: Float
    ) -> Float {
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

        return max(groupPulses[0], max(groupPulses[1], groupPulses[2]))
    }

    /// Record bass onset timestamps for IOI-based tempo estimation.
    /// Uses 75th percentile threshold (median is near-zero for half-wave rectified flux).
    private func recordOnsetTimestamps(bandFlux: [Float]) {
        let bassFlux = bandFlux[0] + bandFlux[1]
        let bassP75 = percentileOfBuffer(
            fluxBuffers[0], count: fluxCounts[0], percentile: 0.75
        ) + percentileOfBuffer(
            fluxBuffers[1], count: fluxCounts[1], percentile: 0.75
        )
        let tempoThreshold = bassP75 * 2.0
        guard bassFlux > tempoThreshold && fluxCounts[0] >= 5 else { return }

        let lastTs = onsetTimestampCount > 0
            ? onsetTimestamps[
                (onsetTimestampHead - 1 + Self.onsetTimestampWindowSize)
                % Self.onsetTimestampWindowSize
            ]
            : -1.0

        // 150ms minimum spacing = 400 BPM max.
        guard elapsedTime - lastTs > 0.15 else { return }
        onsetTimestamps[onsetTimestampHead] = elapsedTime
        onsetTimestampHead = (onsetTimestampHead + 1) % Self.onsetTimestampWindowSize
        onsetTimestampCount = min(
            onsetTimestampCount + 1, Self.onsetTimestampWindowSize
        )
    }

    /// Append composite flux to the onset history buffer.
    private func updateOnsetHistory(bandFlux: [Float]) {
        let compositeFlux = bandFlux.reduce(0, +)
        onsetHistory[onsetHistoryHead] = compositeFlux
        onsetHistoryHead = (onsetHistoryHead + 1) % Self.onsetHistorySize
        onsetHistoryCount = min(onsetHistoryCount + 1, Self.onsetHistorySize)
    }
}
