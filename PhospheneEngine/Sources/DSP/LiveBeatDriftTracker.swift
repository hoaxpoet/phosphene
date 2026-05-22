// swiftlint:disable file_length
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

// MARK: - Diagnostic Trace (BUG_007_DIAGNOSIS)

/// Per-onset trace entry captured when `diagnosticTrace` is set on a
/// `LiveBeatDriftTracker`. Gated at call sites — zero overhead in production.
public struct LiveBeatDriftTraceEntry: Sendable {
    /// Playback time when the sub_bass onset fired (seconds).
    public let onsetTime: Double
    /// Nearest grid beat found within `driftSearchWindow`, or nil.
    public let nearestBeat: Double?
    /// `nearest - onsetTime` when a beat was found, else nil.
    public let instantDriftMs: Double?
    /// Smoothed drift immediately before this onset (ms).
    public let prevDriftMs: Double
    /// Smoothed drift after EMA update (ms). Equal to `prevDriftMs` when no beat found.
    public let newDriftMs: Double
    /// Whether `abs(instantDrift − prevDrift) < strictMatchWindow`.
    public let isTightMatch: Bool
    /// `matchedOnsets` counter after this update.
    public let matchedOnsets: Int
    /// `consecutiveMisses` counter after this update.
    public let consecutiveMisses: Int
    /// Lock state after this update.
    public let lockState: LiveBeatDriftTracker.LockState
}

// MARK: - LiveBeatDriftTracker

// swiftlint:disable type_body_length

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
    /// Tight match window floor (BUG-007.5 part 2): minimum acceptable tight-gate
    /// half-width. The acquisition path uses this exact value; the retention path
    /// uses an adaptive window between this floor and `tightMatchWindowCeiling`,
    /// derived from the running stddev of recent `instantDrift − drift` deviations.
    private static let strictMatchWindow: Double = 0.030
    /// Tight match window ceiling (BUG-007.5 part 2). Adaptive window cannot
    /// exceed this — protects against drift-tracking failure on truly chaotic
    /// onset streams (e.g. B.O.B. polyrhythmic detection noise) where running
    /// stddev gets large and would otherwise mask a genuinely-broken lock.
    private static let tightMatchWindowCeiling: Double = 0.080
    /// Adaptive-window K factor: `effectiveWindow = K × stddev`. K=2 covers ~95 %
    /// of a normal distribution. Higher K = more permissive retention; lower K =
    /// stricter lock. K=2 chosen empirically against the 2026-05-07T20-34-57Z
    /// data: MC σ≈12 ms → window ≈ 24 ms (still bounded), HUMBLE σ≈25 ms → 50 ms.
    private static let tightMatchWindowK: Double = 2.0
    /// Capacity of the ring buffer of recent `instantDrift − drift` values used
    /// to compute adaptive σ. 16 onsets ≈ 13 s at 76 BPM, ≈ 7 s at 120 BPM.
    private static let driftDeviationRingCapacity: Int = 16
    /// Minimum samples in the ring before the adaptive window kicks in. Below
    /// this, the floor `strictMatchWindow` is used. Prevents single-sample noise
    /// from widening the gate during initial lock acquisition.
    private static let driftDeviationMinSamples: Int = 4
    /// Matched onsets required to reach `.locked`.
    private static let lockThreshold: Int = 4

    /// Matched-onset threshold for the BUG-007.4b auto-rotate attempt. After this
    /// many tight onsets, the tracker checks the per-slot kick-density histogram
    /// and rotates `barPhaseOffset` so the dominant slot becomes "1". 8 matches
    /// ≈ 4 s at 120 BPM — fast enough that the visual jumps into place quickly,
    /// slow enough that the histogram is statistically meaningful (2 onsets per
    /// slot in 4/4). One-shot: once attempted (whether or not it found a winner),
    /// the auto-rotate doesn't fire again on the current track. Manual `Shift+B`
    /// preempts it entirely if pressed before the threshold is reached.
    private static let autoRotateMatchThreshold: Int = 8
    /// Dominance ratio for BUG-007.4b auto-rotate: the leading slot must hold
    /// at least this many times more onsets than the runner-up to qualify as a
    /// clear "1" candidate. Tracks where kick is on every beat (four-on-the-floor)
    /// produce ratio ~1.0 → no clear winner → auto-rotate is a no-op (manual
    /// `Shift+B` remains the fallback). 1.5 chosen to admit kick-on-1+3 hip-hop
    /// patterns while rejecting near-uniform distributions.
    private static let autoRotateDominanceRatio: Double = 1.5
    /// Minimum onsets required for the leading slot before auto-rotate fires.
    /// Sub-threshold = "not enough data," skip and try again at next match. Prevents
    /// premature rotation on a 1-onset histogram.
    private static let autoRotateMinDominantCount: Int = 4
    /// Tolerance for the kick-on-1+3 close-tie detection (BUG-007.4c). Top and
    /// runner-up are considered "tied" if their counts are within this ratio of
    /// each other (e.g. 4 vs 5 = 1.25× → tied). Most rock/hip-hop tracks have
    /// kick on 1+3 with slight emphasis on 1; allowing up to 1.25× covers normal
    /// variance while still detecting clear-winner cases (which take the original
    /// `autoRotateDominanceRatio` path).
    private static let autoRotateAlternatingTieRatio: Double = 1.25
    /// Floor (as fraction of top count) below which "other" slots are considered
    /// near-zero for kick-on-1+3 detection (BUG-007.4c). With 8 onsets on slots
    /// 0+2, slots 1+3 should sum to ≤ 20 % of slot 0's count to qualify as the
    /// alternating pattern. Looser fraction admits noise; tighter rejects valid
    /// kick-on-1+3 with occasional hi-hat-as-bass false positives.
    private static let autoRotateAlternatingNoiseFraction: Double = 0.20
    /// Floor for the BPM-aware lock-release gate (BUG-007.5 part 1 + part 3).
    /// At fast tempos (120+ BPM, 500 ms beat period) the gate stays at this
    /// floor — 2.5 s ≈ 5 beats. At slow tempos (HUMBLE half-time at 76 BPM,
    /// 790 ms period) the gate scales up to `lockReleaseBeatMultiplier × period`
    /// so 4–5 consecutive sparse onsets don't trip it. See BUG-007.5 part 3 —
    /// `effectiveLockReleaseSecondsLocked()` returns `max(this, multiplier × medianPeriod)`.
    private static let lockReleaseTimeSecondsFloor: Double = 2.5
    /// Beat-period multiplier for the BPM-aware lock-release gate (BUG-007.5 pt 3).
    /// Lock drops only after 4 × medianBeatPeriod of non-tight events. At 120 BPM
    /// this gives 2.0 s (clamped up to 2.5 s floor); at 76 BPM half-time it gives
    /// 3.16 s — enough headroom for HUMBLE-class sparse onset streams that
    /// produce 3–4 consecutive non-tight events during instrumental breaks.
    private static let lockReleaseBeatMultiplier: Double = 4.0

    // MARK: - Tunables (Cold-Start Phase Acquisition — BUG-017 / CS.1.y)

    /// Onsets required before a cold-start phase correction can resolve early
    /// (before the deadline). Three agreeing onsets at a known tempo pin the
    /// phase robustly against a single syncopated onset.
    private static let coldStartMinOnsets: Int = 3
    /// Relaxed onset requirement at the deadline — two agreeing onsets are
    /// accepted as a last resort so slow, sparse-kick tracks (HUMBLE, 76 BPM)
    /// still get corrected within the budget.
    private static let coldStartDeadlineMinOnsets: Int = 2
    /// Circular resultant-length threshold [0, 1] for a "confident cluster".
    /// Below it the acquisition declines rather than risk applying a wrong
    /// gross correction — the BUG-017 design's confidence gate.
    ///
    /// 0.95 ≈ a cluster tighter than ±25 ms (circular σ). Calibrated against
    /// the `LiveDriftValidation` love_rehab integration test: the live sub-bass
    /// onset detector's first ~3 s are warmup-noisy and produce a *ramp* of
    /// residuals (measured −153 / −117 / −35 ms) whose 3-onset circular
    /// resultant is ≈ 0.82 — a false-confident cluster. A genuine on-beat
    /// cluster (synthetic, or CS.1's within-track MAD ~15 ms) gives R ≈ 0.99.
    /// 0.95 rejects the warmup ramp while admitting a real cluster.
    private static let coldStartMinResultant: Double = 0.95
    /// Minimum |correction − seeded drift| worth applying. Below this the grid
    /// is already well-phased: the steady-state EMA handles the rest, so the
    /// acquisition resolves as a no-op and the steady-state lock progress is
    /// preserved untouched. Equal to the EMA onset search window — errors below
    /// it are EMA-correctable and already inside the ±50 ms product bar.
    private static let coldStartApplyThresholdSeconds: Double = 0.050
    /// Hard budget: the cold-start correction lands by this playback time or
    /// the acquisition declines (Matt-ratified 2026-05-22 — "up to ~3 s").
    private static let coldStartDeadlineSeconds: Double = 3.0
    /// Defensive cap on the residual ring — acquisition normally resolves well
    /// before this many onsets accumulate.
    private static let coldStartMaxResiduals: Int = 12

    /// Default audio output latency (BUG-007.6) for new tracker instances.
    /// 0 by default — engine-level neutral. Production wiring (`MIRPipeline.init`
    /// in the app layer, or any other live-tap context) should set this to a
    /// platform-appropriate value. Internal Mac speakers measured ~50 ms during
    /// the 2026-05-07T18-21-37Z session; AirPods / Bluetooth would be much higher.
    /// Tunable via `,`/`.` dev shortcuts at runtime.
    private static let defaultAudioOutputLatencyMs: Float = 0.0

    // MARK: - Diagnostic (BUG_007_DIAGNOSIS)

    /// Optional per-onset trace callback. Set in tests only; never in production code.
    /// Called from within the NSLock — implementations must not call back into the tracker.
    public var diagnosticTrace: (@Sendable (LiveBeatDriftTraceEntry) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _diagnosticTrace }
        set { lock.lock(); defer { lock.unlock() }; _diagnosticTrace = newValue }
    }
    private var _diagnosticTrace: (@Sendable (LiveBeatDriftTraceEntry) -> Void)?

    // MARK: - State (lock-guarded)

    private var grid: BeatGrid = .empty
    private var medianPeriod: Double = 0.5  // 120 BPM default
    private var drift: Double = 0
    private var matchedOnsets: Int = 0
    /// Diagnostic counter — preserved for `LiveBeatDriftTraceEntry` reporting.
    /// Lock decisions no longer use this; see `firstNonTightMatchTime` (BUG-007.5).
    private var consecutiveMisses: Int = 0
    /// Playback time of the first non-tight match in the current run (BUG-007.5).
    /// Cleared when a tight match arrives. Used for time-based lock release —
    /// when `pt − firstNonTightMatchTime > lockReleaseTimeSeconds`, lock drops.
    private var firstNonTightMatchTime: Double?
    private var lastOnsetTime: Double = -1.0
    /// Ring of recent `instantDrift − drift` values (signed seconds) for the
    /// variance-adaptive tight gate (BUG-007.5 part 2). Reset on `setGrid` / `reset`.
    private var driftDeviationRing: [Double] = []
    /// Per-slot kick-density histogram for BUG-007.4b auto-rotate. Sized to
    /// `grid.beatsPerBar` on `setGrid`. Each tight onset increments the bin
    /// at `timing.beatsSinceDownbeat % beatsPerBar` (raw, *before* `_barPhaseOffset`
    /// rotation — we measure where the actual kicks are landing in Beat This!'s
    /// coordinate system, then derive the offset that makes the dominant slot "1").
    private var slotOnsetCounts: [Int] = []
    /// True after the BUG-007.4b auto-rotate attempt has fired (either rotated
    /// or determined no clear winner). One-shot per track.
    private var autoRotateAttempted: Bool = false
    /// True after the user pressed `Shift+B` (or `barPhaseOffset` was set
    /// externally). Suppresses any pending auto-rotate so user intent wins.
    private var manualRotationPressed: Bool = false
    /// Raw slot (`beatsSinceDownbeat`) of the *first* tight onset in the current
    /// track (BUG-007.4c). Used as the tiebreaker when the kick-on-1+3 pattern
    /// is detected: two slots have similar high counts and the first tight onset
    /// usually lands on the song's downbeat (most listeners start playback at
    /// or near a strong-beat moment). Reset to nil on `setGrid` / `reset`.
    private var firstTightOnsetRawSlot: Int?
    /// Cold-start phase-acquisition residuals (BUG-017 / CS.1.y): the signed
    /// nearest-beat offset of each of the first live sub-bass onsets, wrapped
    /// into [−P/2, P/2]. Aggregated by circular mean to estimate the cold-start
    /// phase error. Reset on `setGrid` / `reset`.
    private var coldStartResiduals: [Double] = []
    /// True once cold-start acquisition has resolved for the current track —
    /// whether by applying a correction, a no-op, or a decline. One-shot.
    private var coldStartResolved: Bool = false
    /// Backing store for `coldStartCorrectionApplied`.
    private var _coldStartCorrectionApplied: Bool = false
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

    /// Snapshot of the currently-installed grid. Returns `.empty` if none.
    /// Used by BUG-007.9 hybrid runtime recalibration to feed the grid
    /// into a fresh `GridOnsetCalibrator` invocation on tap audio.
    public var currentGrid: BeatGrid {
        lock.lock(); defer { lock.unlock() }
        return grid
    }

    /// Number of tight (within-window) onset matches accumulated on the
    /// current track. Read-only — exposed so the app layer can gate the
    /// BUG-007.9 runtime recalibration trigger on lock acquisition.
    public var matchedOnsetCount: Int {
        lock.lock(); defer { lock.unlock() }
        return matchedOnsets
    }

    /// Diagnostic (BUG-017 / CS.1.y): `true` once cold-start phase acquisition
    /// has applied a *gross* phase correction on the current track. Stays
    /// `false` while still acquiring, or if acquisition resolved as a no-op
    /// (grid already well-phased) or a decline (no confident onset cluster).
    /// Read-only — for the regression tests and the debug overlay. Reset on
    /// `setGrid` / `reset`.
    public var coldStartCorrectionApplied: Bool {
        lock.lock(); defer { lock.unlock() }
        return _coldStartCorrectionApplied
    }

    /// Override the drift EMA with a calibrated value (BUG-007.9). Used by
    /// the hybrid runtime recalibration path: after ~15 s of tap audio is
    /// available, re-run `GridOnsetCalibrator` against the actual playback
    /// audio (not the prep-time preview) and apply the result here. This
    /// replaces the prep-time bias from `setGrid(_:initialDriftMs:)` with a
    /// runtime-accurate value computed from the audio the listener actually
    /// hears, eliminating preview-vs-tap encoding mismatch.
    /// Clamps to ±500 ms.
    public func applyCalibration(driftMs: Double) {
        lock.lock(); defer { lock.unlock() }
        let clampedMs = max(-500.0, min(500.0, driftMs))
        let oldDriftMs = drift * 1000.0
        drift = clampedMs / 1000.0
        let oldStr = String(format: "%+.1f", oldDriftMs)
        let newStr = String(format: "%+.1f", clampedMs)
        logger.info("BUG-007.9 runtime recalibration: drift \(oldStr) → \(newStr) ms")
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

    /// Bar-phase rotation offset (BUG-007.4 dev shortcut). Range 0..(beatsPerBar-1).
    /// Rotates the visible "which beat is 1" labelling for the current track without
    /// touching beat-phase or drift. Used to confirm the Spotify-clip-phase hypothesis:
    /// Beat This! identifies bar phase *of the 30 s preview clip*; if the clip didn't
    /// start on a song bar boundary, the displayed "1" lands on a non-downbeat. Cycle
    /// with `Shift+B` until "1" lines up with the song's perceived downbeat.
    /// Reset to 0 on `setGrid` / `reset`. Default 0.
    public var barPhaseOffset: Int {
        get { lock.lock(); defer { lock.unlock() }; return _barPhaseOffset }
        set {
            lock.lock(); defer { lock.unlock() }
            let bpb = max(grid.beatsPerBar, 1)
            _barPhaseOffset = ((newValue % bpb) + bpb) % bpb   // wrap into [0, bpb)
            // BUG-007.4b: external setter signals user intent — preempt auto-rotate.
            manualRotationPressed = true
        }
    }
    private var _barPhaseOffset: Int = 0

    /// Tap-to-output audio latency in milliseconds (BUG-007.6). The audio captured
    /// at the system tap reaches the listener's speaker some ms later (CoreAudio
    /// output buffer + DAC + driver). Applied to the *display path only* — visual
    /// orb fires L ms later than it would otherwise, aligning visual to when the
    /// listener actually hears the audio. Does NOT touch onset matching or drift
    /// estimation (those operate on tap-time onsets and would be made worse by
    /// adding L there — see BUG-007.6 analysis). Range clamped to ±500 ms; tunable
    /// via `,`/`.` dev shortcuts. Persists across track changes — it's a system
    /// property (output device latency), not a per-track property.
    public var audioOutputLatencyMs: Float {
        get { lock.lock(); defer { lock.unlock() }; return _audioOutputLatencyMs }
        set {
            lock.lock(); defer { lock.unlock() }
            _audioOutputLatencyMs = max(-500, min(500, newValue))
        }
    }
    private var _audioOutputLatencyMs: Float = LiveBeatDriftTracker.defaultAudioOutputLatencyMs

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
        setGrid(newGrid, initialDriftMs: 0)
    }

    /// Install a new grid AND seed the drift EMA at a known offset (BUG-007.8).
    /// Used by the prepared-cache install path to apply
    /// `CachedTrackData.gridOnsetOffsetMs` — the per-track grid-vs-onset offset
    /// measured at preparation time by `GridOnsetCalibrator`. Pre-loading drift
    /// to the calibrated value means the visual fires correctly from frame 1
    /// instead of waiting ~4 onsets for the EMA to converge from zero.
    /// Live-analysis grids pass 0 (no preparation-time calibration available).
    public func setGrid(_ newGrid: BeatGrid, initialDriftMs: Double) {
        lock.lock(); defer { lock.unlock() }
        self.grid = newGrid
        let median = newGrid.medianBeatPeriod
        self.medianPeriod = median > 0 ? median : 0.5
        resetStateLocked()
        // BUG-007.4b: size the per-slot kick-density histogram to the grid's meter.
        // resetStateLocked already cleared old contents.
        slotOnsetCounts = [Int](repeating: 0, count: max(newGrid.beatsPerBar, 1))
        // BUG-007.8: seed drift EMA with the calibrated offset (clamped ±500 ms
        // for safety — values outside that range indicate a calibration error).
        let clampedMs = max(-500.0, min(500.0, initialDriftMs))
        self.drift = clampedMs / 1000.0
        let beatCount = newGrid.beats.count
        let bpmStr = String(format: "%.1f", newGrid.bpm)
        let driftStr = String(format: "%+.1f", clampedMs)
        let meter = newGrid.beatsPerBar
        logger.info(
            "LiveBeatDriftTracker grid: \(beatCount) beats, \(bpmStr) BPM, \(meter)/X, initialDrift=\(driftStr) ms"
        )
    }

    /// Override `beatsPerBar` on the installed grid without resetting drift,
    /// lock, or onset state. Used by the metadata-driven meter-correction
    /// path (Round 25, 2026-05-15): the ML beat detector's auto-detected
    /// meter is sometimes wrong on odd time-signature tracks (e.g. Pink
    /// Floyd's Money classified as 2/X instead of 7/X). When external
    /// metadata (Spotify `/audio-features` `time_signature`) provides a
    /// more reliable value, we override the meter here. No-op when no
    /// grid is installed or `newValue` matches the current `beatsPerBar`.
    public func overrideBeatsPerBar(_ newValue: Int) {
        lock.lock(); defer { lock.unlock() }
        guard !grid.beats.isEmpty else { return }
        let clamped = max(1, newValue)
        guard clamped != grid.beatsPerBar else { return }
        let previous = grid.beatsPerBar
        self.grid = grid.overridingBeatsPerBar(clamped)
        // Resize the slot-onset histogram for the new meter. Drift / lock
        // state preserved — only the meter changes.
        slotOnsetCounts = [Int](repeating: 0, count: max(clamped, 1))
        logger.info(
            "LiveBeatDriftTracker beatsPerBar override: \(previous)/X → \(clamped)/X"
        )
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
        firstNonTightMatchTime = nil
        lastOnsetTime = -1.0
        driftDeviationRing.removeAll(keepingCapacity: true)   // BUG-007.5 pt 2
        slotOnsetCounts.removeAll(keepingCapacity: true)      // BUG-007.4b
        autoRotateAttempted = false                            // BUG-007.4b
        manualRotationPressed = false                          // BUG-007.4b
        firstTightOnsetRawSlot = nil                           // BUG-007.4c
        _barPhaseOffset = 0   // BUG-007.4: cleared on track change so each track starts fresh
        coldStartResiduals.removeAll(keepingCapacity: true)    // BUG-017 / CS.1.y
        coldStartResolved = false                              // BUG-017 / CS.1.y
        _coldStartCorrectionApplied = false                    // BUG-017 / CS.1.y
        // _audioOutputLatencyMs intentionally NOT reset — it's a system property.
    }

    // MARK: - Update

    /// Advance one frame. Pass the per-frame sub_bass onset boolean from
    /// `BeatDetector.Result.onsets[0]`, the playback time in seconds since
    /// track start (same domain as `BeatGrid.beats`), and the wall-clock
    /// `deltaTime` since the last call.
    ///
    /// `playbackTime` is `Double` (D-079, QR.1) so long-session callers
    /// (`MIRPipeline.elapsedSeconds`) keep their full precision through the
    /// onset-matching and lock-state path.
    public func update(
        subBassOnset: Bool,
        playbackTime: Double,
        deltaTime: Float
    ) -> Result {
        lock.lock(); defer { lock.unlock() }

        // Reactive-mode fallback: no grid → caller must use BeatPredictor.
        guard !grid.beats.isEmpty else {
            return Result(beatPhase01: 0, beatsUntilNext: 1, barPhase01: 0, beatsPerBar: 1, lockState: .unlocked)
        }

        // BUG-007.6: audio output latency does NOT touch the matching path.
        // Matching uses the unmodified `playbackTime`. The latency is applied to
        // display time only — visual orb fires later by L ms so it aligns with
        // when the listener actually hears the audio (tap captures L ms before
        // speaker output). The diagnostic drift readout reflects detection-delay
        // bias (typically negative), not output latency.
        let pt = playbackTime
        let dt = Double(max(deltaTime, 0.001))

        // BUG-017 / CS.1.y: cold-start phase acquisition. Runs before the
        // steady-state EMA so a one-shot gross phase correction lands first;
        // the triggering onset then feeds the EMA at the corrected phase.
        acquireColdStartPhaseLocked(subBassOnset: subBassOnset, at: pt)

        if subBassOnset {
            lastOnsetTime = pt
            let prevDrift = drift
            if let nearest = grid.nearestBeat(
                to: pt + drift, within: Self.driftSearchWindow
            ) {
                let instantDrift = nearest - pt
                drift = (1 - Self.onsetAlpha) * drift + Self.onsetAlpha * instantDrift

                // BUG-007.5 part 2 — variance-adaptive tight gate. After a few
                // onsets, the gate widens to ±2σ of recent deviations so noisy
                // tracks (HUMBLE half-time, MC verse) hold lock without trip-
                // ping the time gate. Acquisition path uses the floor (30 ms)
                // until ≥ `driftDeviationMinSamples` deviations have accumulated.
                let signedDeviation = instantDrift - drift
                pushDriftDeviationLocked(signedDeviation)
                let acquired = matchedOnsets >= Self.lockThreshold
                let window = acquired ? effectiveTightWindowLocked() : Self.strictMatchWindow
                let isTight = abs(signedDeviation) < window
                if isTight {
                    matchedOnsets = min(matchedOnsets + 1, Int.max - 1)
                    consecutiveMisses = 0
                    firstNonTightMatchTime = nil   // BUG-007.5: reset time gate on tight match
                    // BUG-007.4b: accumulate per-slot kick-density on tight matches only.
                    // Use the *raw* `beatsSinceDownbeat` (before `_barPhaseOffset` rotation)
                    // so we measure where the actual onsets land in Beat This!'s coordinate
                    // system. Auto-rotate then maps the dominant raw slot to the displayed "1".
                    if let timing = grid.localTiming(at: nearest) {
                        let bpb = max(grid.beatsPerBar, 1)
                        let rawSlot = ((timing.beatsSinceDownbeat % bpb) + bpb) % bpb
                        if rawSlot < slotOnsetCounts.count {
                            slotOnsetCounts[rawSlot] += 1
                        }
                        // BUG-007.4c: capture the very first tight onset's slot
                        // as the kick-on-1+3 tiebreaker. Most tracks start with
                        // a clear downbeat (or the first kick we see is on the
                        // song's "1" of the bar after the intro).
                        if firstTightOnsetRawSlot == nil {
                            firstTightOnsetRawSlot = rawSlot
                        }
                    }
                    maybeAutoRotateBarPhaseLocked()
                } else {
                    consecutiveMisses += 1
                    if firstNonTightMatchTime == nil { firstNonTightMatchTime = pt }
                }
                // swiftlint:disable:next line_length
                emitDiagnosticTrace(onset: pt, nearest: nearest, instantDrift: instantDrift, prevDrift: prevDrift, isTight: isTight)
            } else {
                consecutiveMisses += 1
                if firstNonTightMatchTime == nil { firstNonTightMatchTime = pt }
                emitDiagnosticTrace(onset: pt, nearest: nil, instantDrift: nil, prevDrift: prevDrift, isTight: false)
            }
        }

        // No-onset drift decay toward 0 when the input has gone quiet.
        applyNoOnsetDriftDecayLocked(pt: pt, dt: dt)

        let lockState = computeLockStateLocked(at: pt)
        // BUG-007.6 + existing visualPhaseOffsetMs: shift display time by
        // (audioOutputLatency + visualPhaseOffset). Audio reaches speaker L ms
        // after tap; visual fires L ms later so visual matches speaker timing.
        // visualPhaseOffsetMs is the fine-tune knob ([/] shortcut, ±10 ms);
        // audioOutputLatencyMs is the platform-class constant (,/. shortcut, ±5 ms).
        let displayShiftS = Double(_visualPhaseOffsetMs + _audioOutputLatencyMs) / 1000.0
        let displayTime = pt + drift + displayShiftS
        let phase = computePhase(at: displayTime)

        return Result(
            beatPhase01: phase.beatPhase01,
            beatsUntilNext: phase.beatsUntilNext,
            barPhase01: phase.barPhase01,
            beatsPerBar: grid.beatsPerBar,
            lockState: lockState
        )
    }

    // MARK: - No-Onset Decay

    /// Decay `drift` toward 0 when no onset has arrived for longer than two
    /// median beat periods (per-frame EMA, τ = `decayTau`). Prevents runaway
    /// drift on silent input. Extracted from `update()` (CS.1.y) — no
    /// behavioural change. Caller must hold the lock.
    private func applyNoOnsetDriftDecayLocked(pt: Double, dt: Double) {
        guard lastOnsetTime >= 0, (pt - lastOnsetTime) > 2.0 * medianPeriod else { return }
        let decayAlpha = dt / (Self.decayTau + dt)
        drift *= (1 - decayAlpha)
    }

    // MARK: - Cold-Start Phase Acquisition (BUG-017 / CS.1.y)

    /// Cold-start phase acquisition step. Collects the live sub-bass onset's
    /// phase residual and resolves the one-shot gross correction once a
    /// confident onset cluster forms (or the budget expires). No-op once
    /// resolved. Caller must hold the lock.
    ///
    /// The cached grid's tempo is reliable (Beat This!) but its phase is set
    /// from an arbitrary preview-clip excerpt, so it carries a per-track ±½-beat
    /// error (BUG-017). The steady-state EMA's ±50 ms onset search window
    /// cannot see a gross error; this routine measures it from the first live
    /// onsets and applies it directly.
    private func acquireColdStartPhaseLocked(subBassOnset: Bool, at pt: Double) {
        guard !coldStartResolved else { return }
        if subBassOnset {
            coldStartResiduals.append(coldStartResidualLocked(onsetTime: pt))
            if coldStartResiduals.count > Self.coldStartMaxResiduals {
                coldStartResiduals.removeFirst(coldStartResiduals.count - Self.coldStartMaxResiduals)
            }
        }
        maybeResolveColdStartLocked(at: pt)
    }

    /// Signed offset from `onsetTime` to the nearest cached grid beat, wrapped
    /// into [−P/2, P/2] (P = `medianPeriod`). Positive ⇒ the grid beat is later
    /// than the onset. One onset's estimate of the cold-start phase error.
    /// Unlike `BeatGrid.nearestBeat(to:within:)` it has no match window — a
    /// gross cold-start error is exactly what the ±50 ms steady-state window
    /// cannot see. Caller must hold the lock.
    private func coldStartResidualLocked(onsetTime pt: Double) -> Double {
        guard !grid.beats.isEmpty else { return 0 }
        let period = medianPeriod > 0 ? medianPeriod : 0.5
        var lo = 0
        var hi = grid.beats.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if grid.beats[mid] < pt { lo = mid + 1 } else { hi = mid }
        }
        var residual = grid.beats[lo] - pt
        for cand in [lo - 1, lo + 1] where cand >= 0 && cand < grid.beats.count {
            let candidate = grid.beats[cand] - pt
            if abs(candidate) < abs(residual) { residual = candidate }
        }
        // Wrap into [−P/2, P/2] so an onset before beats[0] (the grid is only
        // forward-extrapolated) still yields a meaningful phase residual.
        return residual - period * (residual / period).rounded()
    }

    /// Circular mean and resultant length of the collected cold-start
    /// residuals over the beat period. `mean` ∈ (−P/2, P/2] is the aggregate
    /// phase-error estimate; `resultant` ∈ [0, 1] is the cluster-tightness
    /// confidence (1 = identical residuals, 0 = uniformly scattered /
    /// antipodal). Standard directional statistics — the phase-estimation
    /// stage of a two-stage beat tracker (cf. Ellis 2007). Caller holds the lock.
    private func coldStartCircularStatsLocked() -> (mean: Double, resultant: Double) {
        guard !coldStartResiduals.isEmpty else { return (0, 0) }
        let period = medianPeriod > 0 ? medianPeriod : 0.5
        var sumCos = 0.0
        var sumSin = 0.0
        for residual in coldStartResiduals {
            let theta = 2.0 * .pi * residual / period
            sumCos += cos(theta)
            sumSin += sin(theta)
        }
        let count = Double(coldStartResiduals.count)
        let resultant = (sumCos * sumCos + sumSin * sumSin).squareRoot() / count
        let mean = atan2(sumSin, sumCos) * period / (2.0 * .pi)
        return (mean, resultant)
    }

    /// Decide whether cold-start acquisition can resolve this frame. Resolves
    /// (one-shot) when a confident onset cluster has formed
    /// (`n ≥ coldStartMinOnsets` ∧ `R ≥ coldStartMinResultant`), or at the
    /// deadline. A confident cluster applies a gross correction (or no-ops when
    /// it is too small to matter); a deadline with no confident cluster
    /// declines, leaving the seeded phase untouched (honest limitation for
    /// rhythmless / syncopated / wrong-tempo material). Caller holds the lock.
    private func maybeResolveColdStartLocked(at pt: Double) {
        let onsetCount = coldStartResiduals.count
        let deadlineReached = pt >= Self.coldStartDeadlineSeconds
        let minNeeded = deadlineReached
            ? Self.coldStartDeadlineMinOnsets
            : Self.coldStartMinOnsets
        if onsetCount >= minNeeded {
            let stats = coldStartCircularStatsLocked()
            if stats.resultant >= Self.coldStartMinResultant {
                applyColdStartCorrectionLocked(correction: stats.mean, resultant: stats.resultant)
                return
            }
        }
        if deadlineReached {
            coldStartResolved = true
            let deadlineStr = String(format: "%.1f", Self.coldStartDeadlineSeconds)
            logger.info("BUG-017 cold-start: declined — no confident cluster within \(deadlineStr)s (\(onsetCount) onsets)")
        }
    }

    /// Apply (or no-op) the cold-start gross phase correction. A correction at
    /// or above `coldStartApplyThresholdSeconds` re-seeds `drift` and resets the
    /// steady-state lock machinery so tracking restarts cleanly from the
    /// corrected phase — mechanically the same as a fresh `setGrid` re-seed. A
    /// sub-threshold correction is a no-op: the grid is already well-phased and
    /// the steady-state tracker keeps its progress. User bar-phase intent
    /// (`Shift+B`) is preserved either way. Caller must hold the lock.
    private func applyColdStartCorrectionLocked(correction: Double, resultant: Double) {
        coldStartResolved = true
        let onsetCount = coldStartResiduals.count
        let delta = abs(correction - drift)
        let rStr = String(format: "%.2f", resultant)
        guard delta >= Self.coldStartApplyThresholdSeconds else {
            let deltaStr = String(format: "%.0f", delta * 1000)
            // swiftlint:disable:next line_length
            logger.info("BUG-017 cold-start: resolved as no-op — grid within \(deltaStr) ms of correct phase (R=\(rStr), \(onsetCount) onsets)")
            return
        }
        let oldStr = String(format: "%+.0f", drift * 1000.0)
        let newStr = String(format: "%+.0f", correction * 1000.0)
        resetLockStateForColdStartLocked()
        drift = correction
        _coldStartCorrectionApplied = true
        // swiftlint:disable:next line_length
        logger.info("BUG-017 cold-start: applied gross phase correction — drift \(oldStr) → \(newStr) ms (R=\(rStr), \(onsetCount) onsets)")
    }

    /// Reset the steady-state lock machinery (matched onsets, deviation ring,
    /// slot histogram, auto-rotate one-shot) so it restarts cleanly from a
    /// cold-start phase correction. Does NOT touch `drift` (the caller
    /// re-seeds it), the installed grid, the cold-start latch, `lastOnsetTime`
    /// (the triggering onset re-sets it), or user bar-phase intent
    /// (`_barPhaseOffset` / `manualRotationPressed` — preserved). Caller holds
    /// the lock.
    private func resetLockStateForColdStartLocked() {
        matchedOnsets = 0
        consecutiveMisses = 0
        firstNonTightMatchTime = nil
        driftDeviationRing.removeAll(keepingCapacity: true)
        slotOnsetCounts = [Int](repeating: 0, count: max(grid.beatsPerBar, 1))
        autoRotateAttempted = false
        firstTightOnsetRawSlot = nil
    }

    // MARK: - Helpers

    /// Auto-rotate `_barPhaseOffset` once per track based on the kick-density
    /// histogram in `slotOnsetCounts`. Fires when:
    ///   - `matchedOnsets >= autoRotateMatchThreshold` (lock has stabilised)
    ///   - The user has not manually rotated this track yet
    ///   - The auto-rotate has not already attempted on this track
    ///
    /// Two paths:
    ///   - **BUG-007.4b** (single dominant slot): top count ≥ 1.5× runner-up.
    ///     Picks the dominant raw slot and rotates to displayed "1".
    ///   - **BUG-007.4c** (kick-on-1+3 alternating pattern): top and runner-up
    ///     within 1.25× of each other AND other slots near zero. Tiebreaker:
    ///     `firstTightOnsetRawSlot` if it matches one of the two leaders;
    ///     else falls back to the dominant.
    ///
    /// Otherwise (no signal — four-on-the-floor with equal density on all
    /// slots), leaves the offset alone. Manual `Shift+B` remains the fallback.
    /// Caller must hold the lock.
    private func maybeAutoRotateBarPhaseLocked() {
        guard !autoRotateAttempted,
              !manualRotationPressed,
              matchedOnsets >= Self.autoRotateMatchThreshold,
              !slotOnsetCounts.isEmpty else {
            return
        }
        autoRotateAttempted = true   // one-shot regardless of outcome
        let bpb = slotOnsetCounts.count
        guard bpb >= 2 else { return }   // 1/X meter has nothing to rotate
        // Find dominant slot and runner-up.
        var dominantSlot = 0
        var topCount = slotOnsetCounts[0]
        for idx in slotOnsetCounts.indices where slotOnsetCounts[idx] > topCount {
            topCount = slotOnsetCounts[idx]
            dominantSlot = idx
        }
        var runnerUpSlot = -1
        var runnerUp = 0
        for idx in slotOnsetCounts.indices where idx != dominantSlot && slotOnsetCounts[idx] > runnerUp {
            runnerUp = slotOnsetCounts[idx]
            runnerUpSlot = idx
        }
        guard topCount >= Self.autoRotateMinDominantCount else { return }
        let chosenSlot = chooseAutoRotateSlotLocked(
            dominantSlot: dominantSlot,
            topCount: topCount,
            runnerUpSlot: runnerUpSlot,
            runnerUp: runnerUp,
            totalOnsets: slotOnsetCounts.reduce(0, +)
        )
        guard let chosen = chosenSlot else { return }
        // Rotate so the chosen slot maps to displayed slot 0:
        //   displayedSlot = (rawSlot + offset) mod bpb = 0 ⇒ offset = −rawSlot mod bpb
        _barPhaseOffset = ((bpb - chosen) % bpb + bpb) % bpb
        let countsStr = slotOnsetCounts.map(String.init).joined(separator: ",")
        logger.info(
            "BUG-007.4 auto-rotate: counts=[\(countsStr)] chosen=\(chosen) → offset=\(self._barPhaseOffset)"
        )
    }

    /// Pick the slot to rotate to "1" (or return nil to leave the offset alone).
    /// Implements BUG-007.4b (single dominant) + BUG-007.4c (alternating-pattern
    /// tiebreaker). Caller must hold the lock; pure given the inputs.
    private func chooseAutoRotateSlotLocked(
        dominantSlot: Int, topCount: Int,
        runnerUpSlot: Int, runnerUp: Int,
        totalOnsets: Int
    ) -> Int? {
        // BUG-007.4b: clear single dominant slot.
        let dominanceFloor = max(Double(runnerUp), 1.0) * Self.autoRotateDominanceRatio
        if Double(topCount) >= dominanceFloor {
            return dominantSlot
        }
        // BUG-007.4c: kick-on-1+3 alternating pattern.
        // Need: runner-up has enough hits, top/runner counts are within tie ratio,
        // and the rest of the slots are negligible (other-slot total ≤ 20 % of top).
        guard runnerUp >= Self.autoRotateMinDominantCount,
              runnerUpSlot >= 0 else {
            return nil
        }
        let tieRatioMet =
            Double(topCount) <= Double(runnerUp) * Self.autoRotateAlternatingTieRatio
            && Double(runnerUp) <= Double(topCount) * Self.autoRotateAlternatingTieRatio
        let othersCount = totalOnsets - topCount - runnerUp
        let noiseCeiling = max(2, Int(Self.autoRotateAlternatingNoiseFraction * Double(topCount)))
        let othersAreNoise = othersCount <= noiseCeiling
        guard tieRatioMet, othersAreNoise else { return nil }
        // Tiebreaker: pick whichever of {dominantSlot, runnerUpSlot} matches
        // `firstTightOnsetRawSlot` (typically the song's downbeat). If first-onset
        // doesn't match either, fall back to the dominant slot.
        if let first = firstTightOnsetRawSlot, first == dominantSlot || first == runnerUpSlot {
            return first
        }
        return dominantSlot
    }

    /// Push a signed `instantDrift − drift` value into the variance ring buffer
    /// (BUG-007.5 part 2). Caps at `driftDeviationRingCapacity`, dropping oldest.
    /// Caller must hold the lock.
    private func pushDriftDeviationLocked(_ deviation: Double) {
        driftDeviationRing.append(deviation)
        if driftDeviationRing.count > Self.driftDeviationRingCapacity {
            driftDeviationRing.removeFirst(driftDeviationRing.count - Self.driftDeviationRingCapacity)
        }
    }

    /// Compute the variance-adaptive tight window (BUG-007.5 part 2). Returns
    /// `clamp(2 × σ, strictMatchWindow, tightMatchWindowCeiling)` once
    /// `driftDeviationMinSamples` samples are present, otherwise the floor.
    /// σ uses the unbiased (sample) estimator so small-sample variance isn't
    /// underestimated. Caller must hold the lock.
    private func effectiveTightWindowLocked() -> Double {
        guard driftDeviationRing.count >= Self.driftDeviationMinSamples else {
            return Self.strictMatchWindow
        }
        let count = Double(driftDeviationRing.count)
        let mean = driftDeviationRing.reduce(0, +) / count
        var sumSq = 0.0
        for sample in driftDeviationRing {
            let delta = sample - mean
            sumSq += delta * delta
        }
        // Sample variance (n−1 divisor) — slightly more conservative for small n.
        let variance = sumSq / max(count - 1, 1)
        let sigma = variance.squareRoot()
        let raw = Self.tightMatchWindowK * sigma
        return min(max(raw, Self.strictMatchWindow), Self.tightMatchWindowCeiling)
    }

    private func emitDiagnosticTrace(
        onset pt: Double,
        nearest: Double?,
        instantDrift: Double?,
        prevDrift: Double,
        isTight: Bool
    ) {
        guard let cb = _diagnosticTrace else { return }
        let entry = LiveBeatDriftTraceEntry(
            onsetTime: pt,
            nearestBeat: nearest,
            instantDriftMs: instantDrift.map { $0 * 1000 },
            prevDriftMs: prevDrift * 1000,
            newDriftMs: drift * 1000,
            isTightMatch: isTight,
            matchedOnsets: matchedOnsets,
            consecutiveMisses: consecutiveMisses,
            lockState: computeLockState()
        )
        cb(entry)
    }

    /// Lock-state computation using the BPM-aware time-based release gate
    /// (BUG-007.5 parts 1 + 3). `now` is the current latency-shifted playback
    /// time. Lock is retained while *time since the first non-tight match* in
    /// the current run is below `effectiveLockReleaseSecondsLocked()`, which
    /// scales with grid period so HUMBLE-class half-time tracks (790 ms period)
    /// get a wider gate than fast tracks (120+ BPM, 500 ms period).
    private func computeLockStateLocked(at now: Double) -> LockState {
        guard matchedOnsets >= Self.lockThreshold else {
            return (matchedOnsets > 0 || lastOnsetTime >= 0) ? .locking : .unlocked
        }
        if let firstMissAt = firstNonTightMatchTime,
           now - firstMissAt > effectiveLockReleaseSecondsLocked() {
            return .locking
        }
        return .locked
    }

    /// Convenience for callers without a current `pt` (e.g. the public
    /// `currentLockState` getter). Uses `lastOnsetTime` as a stale clock —
    /// good enough between onset events; readers care about the steady state.
    private func computeLockState() -> LockState {
        let now = max(lastOnsetTime, 0)
        return computeLockStateLocked(at: now)
    }

    /// BPM-aware lock-release window (BUG-007.5 part 3). Returns the larger of:
    ///   - `lockReleaseTimeSecondsFloor` (2.5 s) — the minimum window for fast tracks,
    ///   - `lockReleaseBeatMultiplier × medianPeriod` (4 × beat period) — scaled
    ///     for sparse-onset tracks where 4 consecutive non-tight events are not
    ///     yet a "lost lock" signal.
    /// At 120 BPM (medianPeriod 0.5 s), returns max(2.5, 2.0) = 2.5 (floor).
    /// At 76 BPM half-time (period 0.79 s), returns max(2.5, 3.16) = 3.16 (BPM-aware).
    /// At 60 BPM (period 1.0 s), returns max(2.5, 4.0) = 4.0 (BPM-aware).
    private func effectiveLockReleaseSecondsLocked() -> Double {
        let bpmAware = Self.lockReleaseBeatMultiplier * medianPeriod
        return max(Self.lockReleaseTimeSecondsFloor, bpmAware)
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
        // BUG-007.4 dev shortcut: rotate by `_barPhaseOffset` so the user can
        // confirm the Spotify-clip-phase hypothesis via Shift+B.
        let bpb = max(grid.beatsPerBar, 1)
        let rotatedBeatsSinceDB = (timing.beatsSinceDownbeat + _barPhaseOffset) % bpb
        let barPhaseRaw = (Double(rotatedBeatsSinceDB) + Double(phase01)) / Double(bpb)
        let barPhase01 = Float(barPhaseRaw - floor(barPhaseRaw))

        return PhaseTriple(
            beatPhase01: phase01,
            beatsUntilNext: max(0, 1 - phase01),
            barPhase01: barPhase01
        )
    }
}

// swiftlint:enable type_body_length
