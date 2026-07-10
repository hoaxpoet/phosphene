// SignalHealthMonitor — Continuous classification of input-chain health.
//
// Turns the RUNBOOK's manual signal-chain triage catalog into running code.
// Three detectors, evaluated over a rolling 5 s window, published as one
// `SignalHealth` value on a non-realtime queue (ASH.1):
//
//   1. peakBand — peak dBFS classified into healthy / low / critical using the
//      RUNBOOK bands (healthy ≥ −12, low −15…−12, critical < −15). Measures the
//      raw tap PRE-AGC, since AGC normalizes absolute level away downstream.
//
//   2. deadTap — the permission-invalidation trap: the process tap installs
//      successfully and delivers silent zeros with no error. Detected as tap
//      capture staying `.silent` continuously past `deadTapConfirmSeconds`
//      (chosen past AudioInputRouter's [3,10,30]s reinstall backoff), which is
//      far longer than any ordinary between-tracks gap.
//
//   3. sampleRateMismatch — the system output device's nominal rate is outside
//      Phosphene's expected 44.1/48 kHz family (e.g. a 96 kHz interface forces
//      resampling the stem pipeline assumes away).
//
// The monitor OBSERVES; it never steers tap recovery (that coupling is a future
// decision — ASH.1 Do-Not). `ingest` is safe on the real-time audio thread and
// allocation-free per buffer; classification + Core Audio queries + the
// `onHealthChanged` emit all run on the evaluation queue.

import Accelerate
import CoreAudio
import Foundation
import Shared

// MARK: - SignalHealth

/// Immutable snapshot of input-chain health. Published on every state change.
public struct SignalHealth: Sendable, Equatable {

    /// Peak-level classification per the RUNBOOK dBFS bands.
    public enum PeakBand: String, Sendable {
        /// No window measured yet (initial state before the first 5 s window closes).
        case unknown
        /// Peak ≥ −12 dBFS — mastered music on a clean chain.
        case healthy
        /// Peak −15…−12 dBFS — source-app normalization or chain attenuation likely.
        case low
        /// Peak < −15 dBFS (or silence) — degraded chain or no signal.
        case critical
    }

    /// Peak-level band over the most recent window.
    public var peakBand: PeakBand
    /// Peak level over the most recent window, in dBFS (−120 for silence).
    public var peakDBFS: Float
    /// True when the tap has delivered continuous zeros past the dead-tap threshold.
    public var deadTap: Bool
    /// True when the system output device rate is outside the expected 44.1/48 kHz family.
    public var sampleRateMismatch: Bool
    /// System default-output-device nominal sample rate, in Hz (0 if unreadable).
    public var outputSampleRateHz: Double

    public init(peakBand: PeakBand = .unknown,
                peakDBFS: Float = -120,
                deadTap: Bool = false,
                sampleRateMismatch: Bool = false,
                outputSampleRateHz: Double = 0) {
        self.peakBand = peakBand
        self.peakDBFS = peakDBFS
        self.deadTap = deadTap
        self.sampleRateMismatch = sampleRateMismatch
        self.outputSampleRateHz = outputSampleRateHz
    }
}

// MARK: - SignalHealthMonitor

/// Classifies input-chain health over a rolling window. Thread-safe:
/// `ingest(samples:count:)` is realtime-safe; everything else runs off it.
public final class SignalHealthMonitor: @unchecked Sendable {

    // MARK: - Thresholds (RUNBOOK §"Audio levels too low")

    /// Peak dBFS at or above which the chain is healthy.
    public static let healthyFloorDBFS: Float = -12
    /// Peak dBFS below which the chain is critical (between the two: low).
    public static let criticalCeilingDBFS: Float = -15

    // MARK: - Configuration

    private let windowSeconds: CFAbsoluteTime
    private let deadTapConfirmSeconds: CFAbsoluteTime
    private let expectedRates: Set<Int>
    private let timeProvider: () -> CFAbsoluteTime
    private let outputRateProvider: () -> Double
    private let evalQueue: DispatchQueue

    // MARK: - Callback

    /// Invoked on the evaluation queue whenever the classified health changes.
    /// Never called from the realtime audio thread. Hop to the main actor before
    /// touching UI or `@Published` state.
    public var onHealthChanged: ((SignalHealth) -> Void)?

    // MARK: - State (guarded by `lock`)

    private let lock = NSLock()
    private var windowPeak: Float = 0
    private var windowStart: CFAbsoluteTime?
    private var latestWindowPeak: Float = 0
    private var hasClosedWindow = false
    private var signalState: AudioSignalState = .active
    private var silentSince: CFAbsoluteTime?
    private var tapModeActive = true
    private var lastPublished: SignalHealth?

    // MARK: - Init

    /// - Parameters:
    ///   - windowSeconds: Rolling peak-measurement window. Default 5 s.
    ///   - deadTapConfirmSeconds: Continuous `.silent` duration before declaring a
    ///     dead tap. Default 45 s — past AudioInputRouter's [3,10,30]s reinstall
    ///     backoff, so a recoverable tap has had every retry first.
    ///   - expectedRates: Output-device sample rates considered healthy.
    ///   - timeProvider / outputSampleRateProvider: injectable for tests.
    public init(
        windowSeconds: TimeInterval = 5.0,
        deadTapConfirmSeconds: TimeInterval = 45.0,
        expectedRates: Set<Int> = [44_100, 48_000],
        timeProvider: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent,
        outputSampleRateProvider: @escaping () -> Double = SignalHealthMonitor.queryDefaultOutputSampleRate,
        evaluationQueue: DispatchQueue = DispatchQueue(label: "com.phosphene.audio.signalHealth")
    ) {
        self.windowSeconds = windowSeconds
        self.deadTapConfirmSeconds = deadTapConfirmSeconds
        self.expectedRates = expectedRates
        self.timeProvider = timeProvider
        self.outputRateProvider = outputSampleRateProvider
        self.evalQueue = evaluationQueue
    }

    // MARK: - Realtime ingestion

    /// Feed raw interleaved PCM from the tap (pre-AGC). Realtime-safe and
    /// allocation-free per buffer — a single vDSP peak reduction plus the
    /// window-boundary check. The evaluation dispatch fires at most once per
    /// window (~5 s), matching the existing SilenceDetector convention.
    public func ingest(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        let now = timeProvider()
        var boundaryCrossed = false
        lock.withLock {
            let start = windowStart ?? now
            windowStart = start
            if peak > windowPeak { windowPeak = peak }
            if now - start >= windowSeconds {
                latestWindowPeak = windowPeak
                hasClosedWindow = true
                windowPeak = 0
                windowStart = now
                boundaryCrossed = true
            }
        }
        if boundaryCrossed {
            evalQueue.async { [weak self] in self?.evaluate() }
        }
    }

    // MARK: - Context (non-realtime)

    /// Update the tap signal state (from AudioInputRouter's silence detector) and
    /// whether a process-tap mode is active. Re-evaluates dead-tap on transitions.
    /// `tapModeActive` gates dead-tap detection off for local-file modes, where
    /// silence is real musical silence, not a broken tap.
    public func updateContext(signalState newState: AudioSignalState, tapModeActive: Bool) {
        let now = timeProvider()
        lock.withLock {
            self.tapModeActive = tapModeActive
            if newState != signalState {
                signalState = newState
                switch newState {
                case .silent:
                    if silentSince == nil { silentSince = now }
                case .active, .suspect, .recovering:
                    silentSince = nil
                }
            }
        }
        evalQueue.async { [weak self] in self?.evaluate() }
    }

    /// Clear all state — call at the start of a fresh capture session so stale
    /// silence timing or a prior session's health never carries over.
    public func reset() {
        lock.withLock {
            windowPeak = 0
            windowStart = nil
            latestWindowPeak = 0
            hasClosedWindow = false
            signalState = .active
            silentSince = nil
            lastPublished = nil
        }
    }

    // MARK: - Evaluation (evaluation queue)

    private func evaluate() {
        let outputRate = outputRateProvider()
        let now = timeProvider()
        var toPublish: SignalHealth?
        lock.withLock {
            guard hasClosedWindow else { return }
            let (band, db) = Self.classify(peak: latestWindowPeak)
            var dead = false
            if tapModeActive, signalState == .silent, let since = silentSince {
                dead = (now - since) >= deadTapConfirmSeconds
            }
            let mismatch = outputRate > 0 && !expectedRates.contains(Int(outputRate.rounded()))
            let health = SignalHealth(
                peakBand: band,
                peakDBFS: db,
                deadTap: dead,
                sampleRateMismatch: mismatch,
                outputSampleRateHz: outputRate)
            if health != lastPublished {
                lastPublished = health
                toPublish = health
            }
        }
        if let toPublish { onHealthChanged?(toPublish) }
    }

    /// Map a linear peak magnitude to (band, dBFS). Silence reads as critical.
    static func classify(peak: Float) -> (SignalHealth.PeakBand, Float) {
        guard peak > 1e-7 else { return (.critical, -120) }
        let db = 20 * log10f(peak)
        if db >= healthyFloorDBFS { return (.healthy, db) }
        if db >= criticalCeilingDBFS { return (.low, db) }
        return (.critical, db)
    }

    // MARK: - Output-device rate query

    /// Nominal sample rate of the system default output device, or 0 if
    /// unreadable. Core Audio I/O — never call from the realtime thread.
    public static func queryDefaultOutputSampleRate() -> Double {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddr, 0, nil, &size, &deviceID
        ) == noErr, deviceID != 0 else { return 0 }

        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(
            deviceID, &rateAddr, 0, nil, &rateSize, &rate
        ) == noErr else { return 0 }
        return rate
    }
}
