// LiveBeatDriftTracker — Drift cross-correlation against an offline BeatGrid.
//
// Phase DSP.2 S7. Replaces BeatPredictor's IIR rising-edge tracker for tracks
// that have a cached `BeatGrid` from Beat This! offline analysis. The cached
// grid is the ground truth for beat timing; this tracker only follows playback
// clock drift and dropped-frame jitter so the live `beatPhase01` stays aligned
// with the beats the user actually hears.
//
// Algorithm:
//   1. On each sub_bass onset (BeatDetector.Result.onsets[0] == true), find
//      the nearest cached beat to (playbackTime + currentDrift) within ±50 ms.
//      If matched, EMA-update drift toward (nearestBeat − playbackTime).
//   2. Each frame: phase = ((playbackTime + drift − beats[idx]) / period),
//      clamped [0, 1], where idx is the beat at-or-before (playbackTime + drift).
//   3. If no onset within the search window for > 2× medianBeatPeriod, decay
//      drift toward 0 with the same time-constant (no runaway).
//   4. lockState progresses unlocked → locking → locked once 4 onsets have
//      contributed within ±30 ms of cached beats; back to .locking on 3
//      consecutive misses; .unlocked when no grid is installed.
//
// Reactive-mode fallback: when `setGrid(.empty)` is called (no offline analysis
// succeeded), the tracker emits zero phase / unlocked state and the MIRPipeline
// integration falls back to BeatPredictor.
//
// Thread safety: NSLock-guarded.

import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "LiveBeatDriftTracker")

// MARK: - LiveBeatDriftTracker

/// Aligns live `beatPhase01` to a cached offline `BeatGrid` via drift tracking.
public final class LiveBeatDriftTracker: @unchecked Sendable {

    // MARK: - Lock State

    /// Tracker confidence — exposed for the debug overlay.
    public enum LockState: Sendable {
        /// No grid installed (reactive mode).
        case unlocked
        /// Grid installed; fewer than 4 matched onsets, or recent miss streak.
        case locking
        /// Grid installed; ≥ 4 matched onsets, miss streak below release threshold.
        case locked
    }

    // MARK: - Result

    /// Per-frame output for FeatureVector and the debug overlay.
    public struct Result: Sendable {
        /// Phase in the current beat cycle, [0, 1]. 0 at the cached beat, 1 at
        /// the next cached beat. Snaps to 0 at each beat boundary.
        public var beatPhase01: Float
        /// Fractional beats until the next predicted beat (1 − beatPhase01).
        public var beatsUntilNext: Float
        /// Phase across the current bar, [0, 1]. 0 at downbeat, ramps linearly.
        /// Computed as `(beatsSinceDownbeat + beatPhase01) / beatsPerBar`.
        public var barPhase01: Float
        /// Time-signature numerator from the installed BeatGrid (e.g. 4 for 4/4).
        /// 1 when no grid is installed (reactive-mode fallback).
        public var beatsPerBar: Int
        /// Tracker confidence.
        public var lockState: LockState
    }

    // MARK: - Tunables

    /// Search window for matching an onset to a cached beat: ±50 ms.
    static let driftSearchWindow: Double = 0.05
    /// Per-onset EMA blend factor: each matched onset moves drift this fraction
    /// toward the freshly-measured `instantDrift`. After 4 matched onsets the
    /// drift is within ~13% of equilibrium; after 8 within ~1.7%.
    private static let onsetAlpha: Double = 0.4
    /// No-onset decay time-constant. When no onset has matched for > 2 ×
    /// medianBeatPeriod, drift decays toward 0 with this τ (seconds).
    private static let decayTau: Double = 1.0
    /// Tight match window for the lock counter: ±30 ms.
    private static let strictMatchWindow: Double = 0.030
    /// Matched onsets required to reach `.locked`.
    private static let lockThreshold: Int = 4
    /// Consecutive misses to drop `.locked` back to `.locking`.
    private static let lockReleaseMisses: Int = 3

    // MARK: - State (lock-guarded)

    private var grid: BeatGrid = .empty
    private var medianPeriod: Double = 0.5  // 120 BPM default
    private var drift: Double = 0
    private var matchedOnsets: Int = 0
    private var consecutiveMisses: Int = 0
    private var lastOnsetTime: Double = -1.0
    private let lock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - Grid Management

    /// Whether a non-empty grid is installed.
    public var hasGrid: Bool {
        lock.lock(); defer { lock.unlock() }
        return !grid.beats.isEmpty
    }

    /// BPM from the installed grid, or 0 when no grid is present.
    public var currentBPM: Double {
        lock.lock(); defer { lock.unlock() }
        return grid.bpm
    }

    /// Current tracker confidence. `.unlocked` when no grid is installed.
    public var currentLockState: LockState {
        lock.lock(); defer { lock.unlock() }
        return computeLockState()
    }

    /// Current drift in milliseconds (positive = beats arrive earlier than expected).
    /// 0 when no grid is installed.
    public var currentDriftMs: Double {
        lock.lock(); defer { lock.unlock() }
        return drift * 1000.0
    }

    /// Additional visual phase offset in milliseconds, applied to the displayed
    /// `beatPhase01` / `barPhase01` without affecting onset matching or drift tracking.
    /// Positive = shift phases forward (visual beat fires earlier).
    /// Developer-only diagnostic calibration — default 0.
    public var visualPhaseOffsetMs: Float {
        get { lock.lock(); defer { lock.unlock() }; return _visualPhaseOffsetMs }
        set { lock.lock(); defer { lock.unlock() }; _visualPhaseOffsetMs = newValue }
    }
    private var _visualPhaseOffsetMs: Float = 0

    /// Drift-adjusted downbeat times relative to `playbackTime`, limited to `count`
    /// downbeats within ±`window` seconds of now. Positive = upcoming, negative = past.
    /// Returns an empty array when no grid is installed.
    public func relativeDownbeatTimes(playbackTime: Double, count: Int, window: Double = 8.0) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard !grid.downbeats.isEmpty else { return [] }
        var result: [Float] = []
        result.reserveCapacity(min(count, 16))
        let adjustedNow = playbackTime + drift
        var lo = 0
        var hi = grid.downbeats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if grid.downbeats[mid] < adjustedNow - window { lo = mid + 1 } else { hi = mid }
        }
        for i in lo..<grid.downbeats.count {
            let rel = Float(grid.downbeats[i] - adjustedNow)
            if rel > Float(window) { break }
            if result.count >= count { break }
            result.append(rel)
        }
        return result
    }

    /// Drift-adjusted beat times relative to `playbackTime`, limited to `count`
    /// beats within ±`window` seconds of now. Positive = upcoming, negative = past.
    /// Returns an empty array when no grid is installed.
    public func relativeBeatTimes(playbackTime: Double, count: Int, window: Double = 8.0) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard !grid.beats.isEmpty else { return [] }
        var result: [Float] = []
        result.reserveCapacity(min(count, 32))
        let adjustedNow = playbackTime + drift
        // Binary-search start index to avoid scanning the full grid.
        var lo = 0
        var hi = grid.beats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if grid.beats[mid] < adjustedNow - window { lo = mid + 1 } else { hi = mid }
        }
        for i in lo..<grid.beats.count {
            let rel = Float(grid.beats[i] - adjustedNow)
            if rel > Float(window) { break }
            if result.count >= count { break }
            result.append(rel)
        }
        return result
    }

    /// Install a new grid and reset drift state. `.empty` puts the tracker into
    /// the reactive-mode fallback (emits zero phase / `.unlocked`).
    public func setGrid(_ newGrid: BeatGrid) {
        lock.lock(); defer { lock.unlock() }
        self.grid = newGrid
        let median = newGrid.medianBeatPeriod
        self.medianPeriod = median > 0 ? median : 0.5
        resetStateLocked()
        let beatCount = newGrid.beats.count
        let bpmStr = String(format: "%.1f", newGrid.bpm)
        logger.info("LiveBeatDriftTracker grid set: \(beatCount) beats, \(bpmStr) BPM, \(newGrid.beatsPerBar)/X")
    }

    /// Clear drift / onset / lock state. Does NOT clear the installed grid.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        resetStateLocked()
    }

    private func resetStateLocked() {
        drift = 0
        matchedOnsets = 0
        consecutiveMisses = 0
        lastOnsetTime = -1.0
    }

    // MARK: - Update

    /// Advance one frame. Pass the per-frame sub_bass onset boolean from
    /// `BeatDetector.Result.onsets[0]`, the playback time in seconds since
    /// track start (same domain as `BeatGrid.beats`), and the wall-clock
    /// `deltaTime` since the last call.
    public func update(
        subBassOnset: Bool,
        playbackTime: Float,
        deltaTime: Float
    ) -> Result {
        lock.lock(); defer { lock.unlock() }

        // Reactive-mode fallback: no grid → caller must use BeatPredictor.
        guard !grid.beats.isEmpty else {
            return Result(beatPhase01: 0, beatsUntilNext: 1, barPhase01: 0, beatsPerBar: 1, lockState: .unlocked)
        }

        let pt = Double(playbackTime)
        let dt = Double(max(deltaTime, 0.001))

        if subBassOnset {
            lastOnsetTime = pt
            if let nearest = grid.nearestBeat(
                to: pt + drift, within: Self.driftSearchWindow
            ) {
                let instantDrift = nearest - pt
                drift = (1 - Self.onsetAlpha) * drift + Self.onsetAlpha * instantDrift

                // Tight-match counter for lock progression. The instant drift
                // landing within ±30 ms of the smoothed drift means the onset
                // sat tightly on the cached beat.
                if abs(instantDrift - drift) < Self.strictMatchWindow {
                    matchedOnsets = min(matchedOnsets + 1, Int.max - 1)
                    consecutiveMisses = 0
                } else {
                    consecutiveMisses += 1
                }
            } else {
                consecutiveMisses += 1
            }
        }

        // No-onset decay toward 0 when the input has gone quiet for longer
        // than two median beat periods. Per-frame EMA with τ = 1 s.
        if lastOnsetTime >= 0 && (pt - lastOnsetTime) > 2.0 * medianPeriod {
            let decayAlpha = dt / (Self.decayTau + dt)
            drift *= (1 - decayAlpha)
        }

        let lockState = computeLockState()
        // Apply visual phase offset to the display phase only; onset matching
        // and drift estimation always use the real (unshifted) playback time.
        let displayTime = pt + drift + Double(_visualPhaseOffsetMs) / 1000.0
        let phase = computePhase(at: displayTime)

        return Result(
            beatPhase01: phase.beatPhase01,
            beatsUntilNext: phase.beatsUntilNext,
            barPhase01: phase.barPhase01,
            beatsPerBar: grid.beatsPerBar,
            lockState: lockState
        )
    }

    // MARK: - Helpers

    private func computeLockState() -> LockState {
        if matchedOnsets >= Self.lockThreshold && consecutiveMisses < Self.lockReleaseMisses {
            return .locked
        }
        if matchedOnsets > 0 || lastOnsetTime >= 0 {
            return .locking
        }
        return .unlocked
    }

    private struct PhaseTriple {
        let beatPhase01: Float
        let beatsUntilNext: Float
        let barPhase01: Float
    }

    private func computePhase(at time: Double) -> PhaseTriple {
        guard let timing = grid.localTiming(at: time),
              let idx = grid.beatIndex(at: time) else {
            return PhaseTriple(beatPhase01: 0, beatsUntilNext: 1, barPhase01: 0)
        }
        let beatTime = grid.beats[idx]
        let period = max(timing.period, 1e-6)
        let rawPhase = (time - beatTime) / period
        let phase01 = Float(max(0, min(1, rawPhase)))

        // Bar phase: linear ramp across `beatsPerBar` beats since the last
        // downbeat. Falls back to 0 when no downbeats are present.
        let bpb = max(grid.beatsPerBar, 1)
        let barPhaseRaw = (Double(timing.beatsSinceDownbeat) + Double(phase01)) / Double(bpb)
        let barPhase01 = Float(barPhaseRaw - floor(barPhaseRaw))

        return PhaseTriple(
            beatPhase01: phase01,
            beatsUntilNext: max(0, 1 - phase01),
            barPhase01: barPhase01
        )
    }
}
