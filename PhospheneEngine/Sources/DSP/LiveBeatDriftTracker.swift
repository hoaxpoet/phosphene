// swiftlint:disable file_length
// LiveBeatDriftTracker — BPM-anchored phase acquisition (BSAudit.3 / BUG-017).
//
// Replaces the previous cached-grid-anchored EMA drift tracker (DSP.2 S7 →
// CS.1.y.2-redo → reverted 2026-05-24) with a BPM-prior + broadband-peak
// phase acquisition + confidence-accumulator architecture. Design:
// `docs/BPM_ANCHORED_PHASE_ACQUISITION_DESIGN_2026-05-24.md`. Empirical
// justification: `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`.
//
// Architecture (design §6):
//   1. At track start, `installBPMPrior(bpm:character:beatsPerBar:)` seeds the
//      tracker with the cached BPM + rhythm-character metadata. No phase is
//      claimed yet — internal state is `.coldStart`, accentConfidence = 0.
//   2. The first broadband-flux peak observed via `update(broadbandPeak:...)`
//      anchors the BPM prior's phase at that timestamp. Internal state
//      advances to `.acquiring`; accentConfidence starts ramping.
//   3. Each predicted next beat opens an expectation window of ±W around the
//      prediction. In-window peaks confirm (small phase EMA correction +
//      confidence increment). Misses (window passed without a peak) decrement
//      confidence and advance the predictor without phase correction.
//   4. Once accentConfidence ≥ lockThreshold, internal state advances to
//      `.locked` — the production gate that lets MIRPipeline upstream-gate
//      beat-rate accent fields by accentConfidence (design §6.5).
//   5. Confidence drift below dropThreshold demotes to `.degraded` — accents
//      fade smoothly to 0. Acquisition resumes when peaks return.
//
// Per-track tunables (design §6.4):
//   `phaseAcquisitionDifficulty` linearly scales `gain`, `window`, and
//   `lockThreshold` between clean-four-on-the-floor (0) and
//   sparse-syncopated (1) endpoints. The dual-candidate path activates when
//   `octaveRisk ≥ 0.5`: a second candidate at 2×BPM runs in parallel, and
//   after `dualCandidateDecisionAfter` confirmations the higher-confidence
//   candidate wins.
//
// Public state mapping (preserves BUG-007.x consumers, design §6.2):
//   `LockState.unlocked`  ← internal `.coldStart`
//   `LockState.locking`   ← internal `.acquiring` or `.degraded`
//   `LockState.locked`    ← internal `.locked`
//
// CLAUDE.md anchors:
//   - Failed Approach #68 — sub-bass onsets are not a beat-phase reference;
//     the new architecture consumes broadband flux peaks instead.
//   - "Diagnostic infrastructure precedes fidelity claims" — accentConfidence
//     is the diagnostic that lets MIRPipeline gate beat accents honestly.
//
// Thread safety: NSLock-guarded.

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "LiveBeatDriftTracker")

// MARK: - LiveBeatDriftTracker

// swiftlint:disable type_body_length

/// BPM-anchored phase acquisition tracker. Aligns the live `beatPhase01` to a
/// cached BPM + broadband-flux peak stream via the §6.4 confidence accumulator.
public final class LiveBeatDriftTracker: @unchecked Sendable {

    // MARK: - Lock State

    /// Public tracker confidence. Maps from the §6.2 internal state machine
    /// for backward compatibility with existing consumers (`SpectralCartograph`
    /// diagnostic display, BUG-007.x regression tests).
    public enum LockState: Sendable {
        /// No BPM prior installed, or pre-anchor (coldStart).
        case unlocked
        /// Anchored; acquiring or degraded — accentConfidence below lockThreshold.
        case locking
        /// Sustained confirmations; accentConfidence ≥ lockThreshold.
        case locked
    }

    // MARK: - Result

    /// Per-frame output for FeatureVector and the debug overlay.
    public struct Result: Sendable {
        /// Phase in the current beat cycle, [0, 1]. 0 at the just-anchored
        /// beat, ramps to 1 at the next predicted beat.
        public var beatPhase01: Float
        /// Fractional beats until the next predicted beat (1 − beatPhase01).
        public var beatsUntilNext: Float
        /// Phase across the current bar, [0, 1]. 0 at downbeat, ramps linearly.
        public var barPhase01: Float
        /// Beats-per-bar from the installed BPM prior (4 default).
        public var beatsPerBar: Int
        /// Tracker confidence (public mapping of the §6.2 internal state).
        public var lockState: LockState
        /// Phase-acquisition confidence ∈ [0, 1] (design §6.5). MIRPipeline
        /// multiplies the FeatureVector beat-rate accent fields by this to
        /// gate accents until the system has acquired credible phase.
        public var accentConfidence: Float
    }

    // MARK: - Tunables (design §6.4)

    /// Phase EMA blend factor — one third of the residual is absorbed per
    /// confirmation. Fast enough for live drift tracking, slow enough that
    /// off-beat false-positives don't destabilise lock.
    private static let phaseAlpha: Double = 0.3

    /// Confidence decrement per missed expectation window.
    private static let confidenceDecay: Float = 0.10

    /// Confidence below which a `locked` candidate demotes to `.degraded`.
    private static let dropThreshold: Float = 0.3

    /// Initial confidence seed when the first peak anchors the phase. Slightly
    /// above 0 so the soft ramp starts moving immediately.
    private static let anchorConfidenceSeed: Float = 0.1

    /// Endpoints for `phaseAcquisitionDifficulty` linear interpolation (§6.4).
    /// difficulty=0 → easy four-on-the-floor; difficulty=1 → sparse syncopated.
    private static let gainEasy: Float = 0.30
    private static let gainHard: Float = 0.15
    private static let windowEasySeconds: Double = 0.050
    private static let windowHardSeconds: Double = 0.080
    private static let lockEasy: Float = 0.80
    private static let lockHard: Float = 0.50

    /// `octaveRisk` ≥ this enables the dual-candidate path (design §9.2).
    private static let octaveRiskThreshold: Float = 0.5

    /// Confirmations required on either candidate before the dual-candidate
    /// decision fires. Higher-confidence candidate wins.
    private static let dualCandidateDecisionAfter: Int = 4

    // MARK: - BUG-007.4 / .4b / .4c Tunables (preserved)

    /// Matched-confirmation threshold for the BUG-007.4b auto-rotate attempt.
    private static let autoRotateMatchThreshold: Int = 8
    /// Dominance ratio for the single-dominant-slot path.
    private static let autoRotateDominanceRatio: Double = 1.5
    /// Minimum count on the leading slot before rotation fires.
    private static let autoRotateMinDominantCount: Int = 4
    /// Tolerance for the BUG-007.4c kick-on-1+3 close-tie detection.
    private static let autoRotateAlternatingTieRatio: Double = 1.25
    /// Other-slot noise ceiling for the BUG-007.4c alternating-pattern path.
    private static let autoRotateAlternatingNoiseFraction: Double = 0.20

    // MARK: - Diagnostic Trace

    /// Optional per-confirmation trace callback. Set in tests only; never in
    /// production code. Called from within the NSLock — implementations must
    /// not call back into the tracker.
    public var diagnosticTrace: (@Sendable (LiveBeatDriftTraceEntry) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _diagnosticTrace }
        set { lock.lock(); defer { lock.unlock() }; _diagnosticTrace = newValue }
    }
    private var _diagnosticTrace: (@Sendable (LiveBeatDriftTraceEntry) -> Void)?

    // MARK: - Internal State

    private enum InternalState {
        /// Waiting for the first broadband peak to anchor the BPM prior.
        case coldStart
        /// Anchored, building confidence.
        case acquiring
        /// Sustained confirmations — confidence ≥ effective lockThreshold.
        case locked
        /// Was locked; confidence dropped below `dropThreshold`. Public-API
        /// equivalent of `.locking` — accents fade to 0 smoothly.
        case degraded
    }

    /// A single phase candidate. The dual-candidate path tracks two of these
    /// (one at the cached BPM period, one at half that for the octave-risk
    /// case); the single-candidate path uses only `primary`.
    private struct Candidate {
        /// Phase anchor T₀ — time of the most recently acknowledged beat.
        /// Nil pre-anchor.
        var phaseAnchor: Double?
        /// Beat period in seconds (60 / bpm for primary, 30 / bpm for the
        /// half-period alt candidate).
        var period: Double
        /// Phase-acquisition confidence ∈ [0, 1].
        var confidence: Float = 0
        /// Count of in-window peak confirmations on this candidate.
        var matchedPredictions: Int = 0
        /// Count of beat boundaries advanced since the anchor. Modulo
        /// beatsPerBar gives the current slot for bar-phase output.
        var beatsAdvanced: Int = 0
    }

    // MARK: - State (lock-guarded)

    private var bpm: Double = 0
    private var beatsPerBar: Int = 4
    private var character: RhythmCharacter = .neutral

    /// Effective per-track tunables (computed once per `installBPMPrior`).
    private var effectiveGain: Float = 0.25
    private var effectiveWindow: Double = 0.060
    private var effectiveLockThreshold: Float = 0.7

    private var primary: Candidate = Candidate(period: 0)
    private var alt: Candidate?
    /// True once the dual-candidate decision has fired (or the path was never
    /// engaged). After this, only `primary` is consulted.
    private var dualDecided: Bool = true

    private var internalState: InternalState = .coldStart

    // BUG-007.4 auto-rotate state (preserved from prior implementation).
    private var slotOnsetCounts: [Int] = []
    private var autoRotateAttempted: Bool = false
    private var manualRotationPressed: Bool = false
    private var firstConfirmedRawSlot: Int?
    private var _barPhaseOffset: Int = 0

    // BUG-007.6 / visual phase offset (preserved).
    private var _audioOutputLatencyMs: Float = 0
    private var _visualPhaseOffsetMs: Float = 0

    private let lock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - BPM Prior Management

    /// Install or replace the BPM prior. Resets all per-track state.
    ///
    /// - Parameters:
    ///   - bpm: Cached tempo in beats-per-minute. Pass 0 to revert the
    ///     tracker to its unlocked / no-prior state (reactive mode).
    ///   - character: Rhythm-character metadata from preparation. Nil → use
    ///     `RhythmCharacter.neutral` (mid-default tunables).
    ///   - beatsPerBar: Time-signature numerator (4 default).
    public func installBPMPrior(
        bpm: Double,
        character: RhythmCharacter?,
        beatsPerBar: Int = 4
    ) {
        lock.lock(); defer { lock.unlock() }

        let resolvedCharacter = character ?? .neutral
        self.bpm = bpm
        self.beatsPerBar = max(1, beatsPerBar)
        self.character = resolvedCharacter
        resetStateLocked()

        guard bpm > 0 else {
            // Reactive mode — no prior; primary stays zero-period.
            self.primary = Candidate(period: 0)
            self.alt = nil
            self.dualDecided = true
            self.internalState = .coldStart
            logger.info("LiveBeatDriftTracker: BPM prior cleared (reactive mode)")
            return
        }

        let period = 60.0 / bpm
        let difficulty = max(0, min(1, resolvedCharacter.phaseAcquisitionDifficulty))
        effectiveGain = lerp(Self.gainEasy, Self.gainHard, difficulty)
        effectiveWindow = lerp(Self.windowEasySeconds, Self.windowHardSeconds, Double(difficulty))
        effectiveLockThreshold = lerp(Self.lockEasy, Self.lockHard, difficulty)

        self.primary = Candidate(period: period)
        if resolvedCharacter.octaveRisk >= Self.octaveRiskThreshold {
            self.alt = Candidate(period: period * 0.5)   // 2× BPM, half period
            self.dualDecided = false
        } else {
            self.alt = nil
            self.dualDecided = true
        }
        self.slotOnsetCounts = [Int](repeating: 0, count: self.beatsPerBar)
        self.internalState = .coldStart

        let bpmStr = String(format: "%.1f", bpm)
        let gainStr = String(format: "%.2f", effectiveGain)
        let windowMsStr = String(format: "%.0f", effectiveWindow * 1000)
        let lockStr = String(format: "%.2f", effectiveLockThreshold)
        let difficultyStr = String(format: "%.2f", difficulty)
        let octave = resolvedCharacter.octaveRisk >= Self.octaveRiskThreshold ? "dual" : "single"
        let logLine = "LiveBeatDriftTracker: BPM prior \(bpmStr) BPM, "
            + "diff=\(difficultyStr), gain=\(gainStr), window=±\(windowMsStr) ms, "
            + "lockThreshold=\(lockStr), candidates=\(octave)"
        logger.info("\(logLine, privacy: .public)")
    }

    /// Override `beatsPerBar` on the installed prior without resetting phase,
    /// lock, or auto-rotate state. Preserves the metadata-driven meter
    /// override path established by Round 25 (2026-05-15).
    public func overrideBeatsPerBar(_ newValue: Int) {
        lock.lock(); defer { lock.unlock() }
        guard bpm > 0 else { return }
        let clamped = max(1, newValue)
        guard clamped != beatsPerBar else { return }
        let previous = beatsPerBar
        beatsPerBar = clamped
        slotOnsetCounts = [Int](repeating: 0, count: clamped)
        logger.info(
            "LiveBeatDriftTracker beatsPerBar override: \(previous)/X → \(clamped)/X"
        )
    }

    /// Clear phase / confidence / auto-rotate state. Preserves the installed
    /// BPM prior, beatsPerBar, and audio-output-latency tunables.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        resetStateLocked()
    }

    private func resetStateLocked() {
        primary.phaseAnchor = nil
        primary.confidence = 0
        primary.matchedPredictions = 0
        primary.beatsAdvanced = 0
        alt?.phaseAnchor = nil
        alt?.confidence = 0
        alt?.matchedPredictions = 0
        alt?.beatsAdvanced = 0
        slotOnsetCounts = bpm > 0
            ? [Int](repeating: 0, count: beatsPerBar)
            : []
        autoRotateAttempted = false
        manualRotationPressed = false
        firstConfirmedRawSlot = nil
        _barPhaseOffset = 0
        internalState = .coldStart
        // _audioOutputLatencyMs / _visualPhaseOffsetMs intentionally NOT reset
        // — they are platform-class properties surviving track changes.
    }

    // MARK: - Public Accessors

    /// Whether a BPM prior is currently installed.
    public var hasGrid: Bool {
        lock.lock(); defer { lock.unlock() }
        return bpm > 0
    }

    /// Cached BPM from the installed prior, or 0 in reactive mode.
    public var currentBPM: Double {
        lock.lock(); defer { lock.unlock() }
        return bpm
    }

    /// Public lock state via the §6.2 mapping.
    public var currentLockState: LockState {
        lock.lock(); defer { lock.unlock() }
        return externalLockStateLocked()
    }

    /// Current `accentConfidence` (post-rampup smoothing) for diagnostic use.
    public var currentAccentConfidence: Float {
        lock.lock(); defer { lock.unlock() }
        return primary.confidence
    }

    /// Legacy drift readout. The BPM-prior architecture has no drift
    /// primitive — returns 0. Preserved as the existing
    /// `SpectralHistoryBuffer` diagnostic feed publishes a "drift_ms" value
    /// to `SpectralCartograph`; that diagnostic now reads 0 ms in
    /// BPM-prior mode (no drift to display).
    public var currentDriftMs: Double { 0 }

    /// Count of confirmed predictions on the primary candidate. Surfaces
    /// for diagnostic / test inspection.
    public var matchedOnsetCount: Int {
        lock.lock(); defer { lock.unlock() }
        return primary.matchedPredictions
    }

    /// Additional visual phase offset in milliseconds (existing diagnostic
    /// calibration knob, preserved from BUG-007.6 era).
    public var visualPhaseOffsetMs: Float {
        get { lock.lock(); defer { lock.unlock() }; return _visualPhaseOffsetMs }
        set { lock.lock(); defer { lock.unlock() }; _visualPhaseOffsetMs = newValue }
    }

    /// Bar-phase rotation offset (BUG-007.4 user shortcut, Shift+B). Preserves
    /// the existing semantics: external set marks `manualRotationPressed` so
    /// the auto-rotate (BUG-007.4b/c) yields to user intent.
    public var barPhaseOffset: Int {
        get { lock.lock(); defer { lock.unlock() }; return _barPhaseOffset }
        set {
            lock.lock(); defer { lock.unlock() }
            let bpb = max(beatsPerBar, 1)
            _barPhaseOffset = ((newValue % bpb) + bpb) % bpb
            manualRotationPressed = true
        }
    }

    /// Tap-to-output audio latency in milliseconds (BUG-007.6, preserved).
    /// Applied to the display path only — does NOT touch phase acquisition.
    public var audioOutputLatencyMs: Float {
        get { lock.lock(); defer { lock.unlock() }; return _audioOutputLatencyMs }
        set {
            lock.lock(); defer { lock.unlock() }
            _audioOutputLatencyMs = max(-500, min(500, newValue))
        }
    }

    // MARK: - Predicted Beat / Downbeat Times

    /// Drift-adjusted beat times relative to `playbackTime`, computed from the
    /// installed BPM prior + current phase anchor. Returns an empty array
    /// when no prior is installed or the tracker has not yet anchored.
    public func relativeBeatTimes(
        playbackTime: Double,
        count: Int,
        window: Double = 8.0
    ) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard let anchor = primary.phaseAnchor,
              primary.period > 0,
              count > 0 else { return [] }
        return projectBeatsLocked(
            anchor: anchor,
            period: primary.period,
            now: playbackTime,
            count: count,
            window: window
        )
    }

    /// Drift-adjusted downbeat times relative to `playbackTime`. Downbeats
    /// are derived from the installed `beatsPerBar` + `_barPhaseOffset` — the
    /// closest downbeat at-or-before now is `anchor − (beatsAdvanced mod bpb) ×
    /// period` after applying the rotation.
    public func relativeDownbeatTimes(
        playbackTime: Double,
        count: Int,
        window: Double = 8.0
    ) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        guard let anchor = primary.phaseAnchor,
              primary.period > 0,
              count > 0 else { return [] }
        let bpb = max(beatsPerBar, 1)
        let rawSlot = ((primary.beatsAdvanced % bpb) + bpb) % bpb
        let displayedSlot = ((rawSlot + _barPhaseOffset) % bpb + bpb) % bpb
        // Most recent downbeat is `displayedSlot` beats *before* the anchor
        // in the current bar; project bars-worth of period forward / backward.
        let firstDownbeat = anchor - Double(displayedSlot) * primary.period
        let barPeriod = primary.period * Double(bpb)
        var result: [Float] = []
        result.reserveCapacity(min(count, 32))
        // Start at `firstDownbeat`, walk earlier first then later.
        // Earlier downbeats in (now - window) … now:
        var time = firstDownbeat
        while time >= playbackTime - window && result.count < count {
            let rel = Float(time - playbackTime)
            result.append(rel)
            time -= barPeriod
        }
        // Re-sort ascending and append upcoming downbeats.
        result.sort()
        var next = firstDownbeat + barPeriod
        while next <= playbackTime + window && result.count < count {
            result.append(Float(next - playbackTime))
            next += barPeriod
        }
        return result
    }

    // MARK: - Update

    /// Advance one frame.
    ///
    /// - Parameters:
    ///   - broadbandPeak: True when this frame is a `BroadbandPeakDetector` peak.
    ///   - playbackTime: Track-relative playback clock in seconds (Double for
    ///     long-session precision, D-079 / QR.1).
    ///   - deltaTime: Wall-clock seconds since the last `update` call.
    public func update(
        broadbandPeak: Bool,
        playbackTime: Double,
        deltaTime: Float
    ) -> Result {
        lock.lock(); defer { lock.unlock() }

        guard bpm > 0 else {
            // Reactive mode — no BPM prior installed.
            return Result(
                beatPhase01: 0,
                beatsUntilNext: 1,
                barPhase01: 0,
                beatsPerBar: 1,
                lockState: .unlocked,
                accentConfidence: 0
            )
        }

        let pt = playbackTime
        _ = deltaTime   // reserved for future per-frame decays

        let peakTime: Double? = broadbandPeak ? pt : nil

        // Step 1: drive the primary candidate.
        let primaryConfirmed = stepCandidateLocked(
            candidate: &primary, peakTime: peakTime, currentTime: pt
        )

        // Step 2: drive the alt candidate (dual-candidate octave-risk path).
        if var alternative = alt, !dualDecided {
            _ = stepCandidateLocked(
                candidate: &alternative, peakTime: peakTime, currentTime: pt
            )
            alt = alternative
            decideDualCandidateLocked()
        }

        // Step 3: update internal state from primary confidence.
        updateInternalStateLocked()

        // Step 4: auto-rotate accumulator (BUG-007.4b/c). Only on confirmations
        // against the (winning) primary candidate.
        if primaryConfirmed {
            accumulateAutoRotateLocked()
        }

        // Step 5: compute display output.
        let displayShift = Double(_visualPhaseOffsetMs + _audioOutputLatencyMs) / 1000.0
        let phase = computePhaseLocked(at: pt + displayShift)

        emitDiagnosticTraceLocked(
            onsetTime: pt,
            confirmed: primaryConfirmed,
            peakTime: peakTime
        )

        return Result(
            beatPhase01: phase.beatPhase01,
            beatsUntilNext: phase.beatsUntilNext,
            barPhase01: phase.barPhase01,
            beatsPerBar: beatsPerBar,
            lockState: externalLockStateLocked(),
            accentConfidence: primary.confidence
        )
    }

    // MARK: - Candidate Stepping (design §6.4)

    /// Advance one candidate by one frame. Returns true when a confirmation
    /// fired this frame. Caller must hold the lock.
    private func stepCandidateLocked(
        candidate: inout Candidate,
        peakTime: Double?,
        currentTime pt: Double
    ) -> Bool {
        guard candidate.period > 0 else { return false }

        // Pre-anchor: the first peak anchors the BPM prior's phase.
        guard let anchor = candidate.phaseAnchor else {
            if let pulseTime = peakTime {
                candidate.phaseAnchor = pulseTime
                candidate.confidence = Self.anchorConfidenceSeed
                candidate.matchedPredictions = 0
                candidate.beatsAdvanced = 0
            }
            return false
        }

        let nextPredicted = anchor + candidate.period
        let windowLow = nextPredicted - effectiveWindow
        let windowHigh = nextPredicted + effectiveWindow

        // Miss: window passed without a peak.
        if pt > windowHigh {
            candidate.phaseAnchor = nextPredicted   // advance, no phase correction
            candidate.confidence = max(0, candidate.confidence - Self.confidenceDecay)
            candidate.beatsAdvanced += 1
            return false
        }

        // Confirm: in-window peak.
        if let pulseTime = peakTime, pulseTime >= windowLow, pulseTime <= windowHigh {
            let residual = pulseTime - nextPredicted
            candidate.phaseAnchor = nextPredicted + Self.phaseAlpha * residual
            candidate.confidence = min(1.0, candidate.confidence + effectiveGain)
            candidate.matchedPredictions += 1
            candidate.beatsAdvanced += 1
            return true
        }

        return false
    }

    // MARK: - Dual-Candidate Decision (design §9.2)

    private func decideDualCandidateLocked() {
        guard !dualDecided, let alternative = alt else { return }
        let trigger = max(primary.matchedPredictions, alternative.matchedPredictions)
        guard trigger >= Self.dualCandidateDecisionAfter else { return }
        if alternative.confidence > primary.confidence {
            // Alt won — promote it to primary.
            let bpmStr = String(format: "%.1f", 60.0 / alternative.period)
            logger.info(
                "LiveBeatDriftTracker: dual-candidate decision — alt wins at \(bpmStr) BPM"
            )
            primary = alternative
            bpm = 60.0 / alternative.period
            slotOnsetCounts = [Int](repeating: 0, count: beatsPerBar)
            firstConfirmedRawSlot = nil
        } else {
            logger.info(
                "LiveBeatDriftTracker: dual-candidate decision — primary wins"
            )
        }
        alt = nil
        dualDecided = true
    }

    // MARK: - Internal State

    private func updateInternalStateLocked() {
        switch internalState {
        case .coldStart:
            if primary.phaseAnchor != nil {
                internalState = .acquiring
            }
        case .acquiring:
            if primary.confidence >= effectiveLockThreshold {
                internalState = .locked
            }
        case .locked:
            if primary.confidence < Self.dropThreshold {
                internalState = .degraded
            }
        case .degraded:
            if primary.confidence >= effectiveLockThreshold {
                internalState = .locked
            }
        }
    }

    private func externalLockStateLocked() -> LockState {
        switch internalState {
        case .coldStart: return .unlocked
        case .acquiring, .degraded: return .locking
        case .locked: return .locked
        }
    }

    // MARK: - Phase Output

    private struct PhaseTriple {
        let beatPhase01: Float
        let beatsUntilNext: Float
        let barPhase01: Float
    }

    private func computePhaseLocked(at displayTime: Double) -> PhaseTriple {
        guard let anchor = primary.phaseAnchor, primary.period > 0 else {
            return PhaseTriple(beatPhase01: 0, beatsUntilNext: 1, barPhase01: 0)
        }
        let bpb = max(beatsPerBar, 1)
        let elapsedFromAnchor = displayTime - anchor
        let beatsFrac = elapsedFromAnchor / primary.period
        // Floor / fractional split — works for negative elapsed too (pre-anchor
        // display sample shouldn't fire here, but guard anyway).
        let floored = floor(beatsFrac)
        let phase01 = Float(max(0, min(1, beatsFrac - floored)))

        // Bar-slot tracking: primary.beatsAdvanced counts confirmations + misses
        // since the anchor. The slot at the *anchor* (beat 0 in our coordinate
        // system) is 0; the slot of the most-recently-advanced beat is
        // `beatsAdvanced mod beatsPerBar`. As `displayTime` advances inside
        // beat #N, the current slot is the same value.
        let rawSlot = ((primary.beatsAdvanced % bpb) + bpb) % bpb
        let displayedSlot = ((rawSlot + _barPhaseOffset) % bpb + bpb) % bpb
        let barPhaseRaw = (Double(displayedSlot) + Double(phase01)) / Double(bpb)
        let barPhase01 = Float(barPhaseRaw - floor(barPhaseRaw))

        return PhaseTriple(
            beatPhase01: phase01,
            beatsUntilNext: max(0, 1 - phase01),
            barPhase01: barPhase01
        )
    }

    // MARK: - BUG-007.4 / .4b / .4c Auto-Rotate (preserved)

    private func accumulateAutoRotateLocked() {
        let bpb = max(beatsPerBar, 1)
        guard slotOnsetCounts.count == bpb else { return }
        let rawSlot = ((primary.beatsAdvanced % bpb) + bpb) % bpb
        slotOnsetCounts[rawSlot] += 1
        if firstConfirmedRawSlot == nil {
            firstConfirmedRawSlot = rawSlot
        }
        maybeAutoRotateLocked()
    }

    private func maybeAutoRotateLocked() {
        guard !autoRotateAttempted,
              !manualRotationPressed,
              primary.matchedPredictions >= Self.autoRotateMatchThreshold,
              !slotOnsetCounts.isEmpty else {
            return
        }
        autoRotateAttempted = true
        let bpb = slotOnsetCounts.count
        guard bpb >= 2 else { return }

        var dominantSlot = 0
        var topCount = slotOnsetCounts[0]
        for idx in slotOnsetCounts.indices where slotOnsetCounts[idx] > topCount {
            topCount = slotOnsetCounts[idx]
            dominantSlot = idx
        }
        var runnerUpSlot = -1
        var runnerUp = 0
        for idx in slotOnsetCounts.indices
            where idx != dominantSlot && slotOnsetCounts[idx] > runnerUp {
            runnerUp = slotOnsetCounts[idx]
            runnerUpSlot = idx
        }
        guard topCount >= Self.autoRotateMinDominantCount else { return }
        let chosen = chooseAutoRotateSlotLocked(
            dominantSlot: dominantSlot,
            topCount: topCount,
            runnerUpSlot: runnerUpSlot,
            runnerUp: runnerUp,
            totalOnsets: slotOnsetCounts.reduce(0, +)
        )
        guard let pick = chosen else { return }
        _barPhaseOffset = ((bpb - pick) % bpb + bpb) % bpb
        let countsStr = slotOnsetCounts.map(String.init).joined(separator: ",")
        logger.info(
            "BUG-007.4 auto-rotate: counts=[\(countsStr)] chosen=\(pick) → offset=\(self._barPhaseOffset)"
        )
    }

    private func chooseAutoRotateSlotLocked(
        dominantSlot: Int, topCount: Int,
        runnerUpSlot: Int, runnerUp: Int,
        totalOnsets: Int
    ) -> Int? {
        let dominanceFloor = max(Double(runnerUp), 1.0) * Self.autoRotateDominanceRatio
        if Double(topCount) >= dominanceFloor {
            return dominantSlot
        }
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
        if let first = firstConfirmedRawSlot, first == dominantSlot || first == runnerUpSlot {
            return first
        }
        return dominantSlot
    }

    // MARK: - Predicted Beat Projection

    private func projectBeatsLocked(
        anchor: Double,
        period: Double,
        now: Double,
        count: Int,
        window: Double
    ) -> [Float] {
        // Find the integer beat-index nearest at-or-before `now`.
        let beatsFromAnchor = (now - anchor) / period
        let kAtOrBefore = Int(floor(beatsFromAnchor))
        var result: [Float] = []
        result.reserveCapacity(min(count, 32))
        // Past beats (negative relative time) walking backward.
        var k = kAtOrBefore
        while result.count < count {
            let bt = anchor + Double(k) * period
            let rel = Float(bt - now)
            if rel < Float(-window) { break }
            if rel <= 0 { result.append(rel) }
            k -= 1
        }
        result.sort()
        // Upcoming beats walking forward.
        var nextK = kAtOrBefore + 1
        while result.count < count {
            let bt = anchor + Double(nextK) * period
            let rel = Float(bt - now)
            if rel > Float(window) { break }
            result.append(rel)
            nextK += 1
        }
        return result
    }

    // MARK: - Diagnostic Trace

    private func emitDiagnosticTraceLocked(
        onsetTime: Double,
        confirmed: Bool,
        peakTime: Double?
    ) {
        guard let cb = _diagnosticTrace, peakTime != nil else { return }
        let entry = LiveBeatDriftTraceEntry(
            onsetTime: onsetTime,
            phaseAnchorMs: primary.phaseAnchor.map { $0 * 1000 },
            accentConfidence: primary.confidence,
            matchedPredictions: primary.matchedPredictions,
            lockState: externalLockStateLocked()
        )
        cb(entry)
    }
}

// swiftlint:enable type_body_length

// MARK: - Diagnostic Trace Entry

/// Per-confirmation trace entry captured when `diagnosticTrace` is set on a
/// `LiveBeatDriftTracker`. Gated at call sites — zero overhead in production.
public struct LiveBeatDriftTraceEntry: Sendable {
    /// Playback time when the broadband peak fired (seconds).
    public let onsetTime: Double
    /// Current phase anchor (T₀) in milliseconds, or nil pre-anchor.
    public let phaseAnchorMs: Double?
    /// `accentConfidence` after this update.
    public let accentConfidence: Float
    /// `matchedPredictions` counter after this update.
    public let matchedPredictions: Int
    /// Public lock state after this update.
    public let lockState: LiveBeatDriftTracker.LockState
}

// MARK: - Linear Interpolation

private func lerp(_ start: Float, _ end: Float, _ alpha: Float) -> Float {
    start + (end - start) * max(0, min(1, alpha))
}

private func lerp(_ start: Double, _ end: Double, _ alpha: Double) -> Double {
    start + (end - start) * max(0, min(1, alpha))
}
