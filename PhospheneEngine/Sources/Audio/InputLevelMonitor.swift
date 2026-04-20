// InputLevelMonitor — Continuous signal-quality assessment of the audio tap.
//
// Diagnoses degraded input by measuring two properties that cannot be fixed
// downstream by AGC:
//
//   1. Peak dBFS — rolling maximum over a ~30s window.  Mastered music at a
//      clean output path should peak at −3 to −6 dBFS.  Chronically lower
//      peaks (−15 dBFS or worse) indicate source-app normalization (Spotify
//      Normalize Volume, Apple Music Sound Check), low system volume, or
//      a virtual loopback driver (BlackHole) in the output chain.
//
//   2. Spectral balance — fraction of total energy in sub (20-250 Hz),
//      mid (250-4 kHz), and treble (4-20 kHz) bands.  A full-bandwidth
//      stereo mix has treble at ~5-20% of total.  A BT/AirPlay codec
//      (SBC/AAC/aptX) or aggressive DSP collapses treble to <2%, which
//      cripples downstream onset detection and stem separation even
//      though the "signal present" check still passes.
//
// Session 2026-04-17T19-31-46Z diagnosed an output chain routed through
// Multi-Output Device (BlackHole + Mac mini Speakers): peaks at −20 dBFS,
// treble fraction at 0.1%.  Neither problem surfaces in the existing
// SilenceDetector (which only distinguishes silent from non-silent) or
// in post-AGC feature values (which normalise away absolute level).
//
// The monitor produces a SignalQuality grade (green/yellow/red) with a
// human-readable reason string so the operator knows whether to fix the
// audio-source setup or look for a bug in Phosphene.
//
// Thread-safety: `submit` is called from the Core Audio IO proc (raw
// samples) and the background analysis queue (FFT magnitudes).  All
// mutable state is guarded by NSLock.  `currentSnapshot()` returns a
// Sendable copy suitable for the UI thread.

import Accelerate
import Foundation
import Shared

// MARK: - SignalQuality

/// Three-tier quality grade surfaced by `InputLevelMonitor`.
public enum SignalQuality: String, Sendable {
    case green
    case yellow
    case red
    case unknown
}

// MARK: - InputLevelSnapshot

/// Immutable Sendable snapshot of the monitor's current state.
/// The UI and session logger read this; the monitor writes it.
public struct InputLevelSnapshot: Sendable, Equatable {

    /// Rolling peak, in dBFS (0 dBFS = digital full scale, −∞ = silence).
    public let peakDBFS: Float

    /// Rolling RMS, in dBFS.
    public let rmsDBFS: Float

    /// Fraction of total spectral energy in the 20-250 Hz band.  [0, 1].
    public let subRatio: Float

    /// Fraction of total spectral energy in the 250-4000 Hz band.  [0, 1].
    public let midRatio: Float

    /// Fraction of total spectral energy in the 4000-20000 Hz band.  [0, 1].
    public let trebleRatio: Float

    /// Overall quality grade.  `.unknown` before enough samples accumulate.
    public let quality: SignalQuality

    /// Short human-readable explanation ("OK", "low peak: check Spotify Normalize",
    /// "treble <2%: check output device is wired, not Bluetooth/AirPlay", etc.).
    public let reason: String

    /// Frames submitted since monitor creation — used to guard early reads.
    public let frameCount: Int

    public init(peakDBFS: Float = -120,
                rmsDBFS: Float = -120,
                subRatio: Float = 0,
                midRatio: Float = 0,
                trebleRatio: Float = 0,
                quality: SignalQuality = .unknown,
                reason: String = "warming up",
                frameCount: Int = 0) {
        self.peakDBFS = peakDBFS
        self.rmsDBFS = rmsDBFS
        self.subRatio = subRatio
        self.midRatio = midRatio
        self.trebleRatio = trebleRatio
        self.quality = quality
        self.reason = reason
        self.frameCount = frameCount
    }
}

// MARK: - InputLevelMonitor

/// Tracks audio tap quality in real time and publishes a classification.
/// Cheap enough to run on every audio callback (a few vDSP ops); spectral
/// classification piggybacks on the FFT magnitudes the pipeline already
/// computes.
public final class InputLevelMonitor: @unchecked Sendable {

    // MARK: - Thresholds

    /// Peak dBFS below which we warn.
    /// −9 dBFS is the target floor for mastered music with normalization off.
    /// Anything chronically below indicates attenuation in the output chain.
    public static let peakWarningDBFS: Float = -9
    public static let peakCriticalDBFS: Float = -15

    /// Treble energy fraction is kept for informational display only.
    /// Classification thresholds were removed after session 2026-04-17T21-05-47Z,
    /// where raw_tap.wav analysis of Oxytocin — a bass-heavy modern production
    /// with minimal high-frequency content by design — showed the chain was
    /// clean but the squared-magnitude fraction read as 0.01-0.2% treble and
    /// wrongly fired "Bluetooth/AirPlay codec" warnings.  A single bass-heavy
    /// track cannot distinguish itself from a band-limited chain; that
    /// discrimination requires averaging across many tracks, which is out
    /// of scope for a per-session monitor.  Peak dBFS remains the reliable
    /// signal — chain-wide attenuation is genre-independent.

    /// Minimum samples before a classification is emitted (avoids
    /// flapping during warmup).
    public static let warmupFrames: Int = 60  // ~0.6s at 94 Hz

    // MARK: - State

    private let lock = NSLock()

    // Peak — tracked as a running maximum with a slow decay so transient
    // outliers count but sustained low levels still dominate the reading.
    // Decay is applied per submission; at 94 Hz with decay=0.9995 the
    // time constant is ~21s, matching the 30s rolling window described
    // in the header.
    private var peakEnvelope: Float = 0

    // RMS — EMA with ~3s time constant.
    private var rmsEnvelope: Float = 0

    // Spectral balance — EMAs over band-summed magnitudes².
    // EMA decay 0.9 per submission (analysis queue) gives ~1s smoothing
    // at typical analysis rate.
    private var subEnergyEMA: Float = 0
    private var midEnergyEMA: Float = 0
    private var trebleEnergyEMA: Float = 0

    private var totalFrames: Int = 0
    private var snapshot: InputLevelSnapshot = InputLevelSnapshot()

    // Hysteresis: require a grade to persist for `gradeSwitchFrames`
    // analysis-queue updates before the public snapshot adopts it.
    // Without this, the classifier flapped between yellow↔red at every
    // EMA wobble on borderline signals (session 20-05-00Z logged ~18
    // transitions in 3 minutes).  At ~94 Hz analysis updates, 30 frames
    // ≈ 0.3s — long enough to absorb noise, short enough to catch real
    // output-device changes.
    private var pendingQuality: SignalQuality = .unknown
    private var pendingCount: Int = 0
    private static let gradeSwitchFrames: Int = 30

    // Per-submission constants — set on init, avoids parameter threading.
    private let sampleRate: Float

    public init(sampleRate: Float = 48_000) {
        self.sampleRate = sampleRate
    }

    // MARK: - Raw sample ingestion (audio thread)

    /// Feed the raw interleaved PCM samples from the tap callback.
    /// Computes peak + RMS on an absolute-value basis.
    /// Safe to call from the Core Audio IO proc.
    public func submitSamples(pointer: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }

        // Peak (max abs) — vDSP_maxmgv handles sign.
        var peak: Float = 0
        vDSP_maxmgv(pointer, 1, &peak, vDSP_Length(count))

        // RMS.
        var rms: Float = 0
        vDSP_rmsqv(pointer, 1, &rms, vDSP_Length(count))

        lock.withLock {
            // Peak envelope: rise instantly, decay slowly.
            peakEnvelope = max(peak, peakEnvelope * 0.9995)
            // RMS EMA.
            rmsEnvelope = rmsEnvelope * 0.95 + rms * 0.05
            totalFrames &+= 1
        }
    }

    // MARK: - FFT magnitude ingestion (analysis queue)

    /// Feed pre-computed FFT magnitudes (after AGC-free raw magnitude path).
    /// Bins are [0, binCount) mapping linearly to [0, Nyquist].
    /// Called on the serial analysis queue after each FFT.
    public func submitMagnitudes(_ magnitudes: [Float], sampleRate: Float) {
        guard !magnitudes.isEmpty else { return }

        let binCount = magnitudes.count
        let nyquist = sampleRate * 0.5
        let binWidth = nyquist / Float(binCount)

        func bandEnergy(loHz: Float, hiHz: Float) -> Float {
            let loBin = max(0, Int(loHz / binWidth))
            let hiBin = min(binCount - 1, Int(hiHz / binWidth))
            guard hiBin > loBin else { return 0 }
            var sum: Float = 0
            magnitudes.withUnsafeBufferPointer { buf in
                guard let baseAddress = buf.baseAddress else { return }
                vDSP_svesq(
                    baseAddress + loBin,
                    1,
                    &sum,
                    vDSP_Length(hiBin - loBin)
                )
            }
            return sum
        }

        let sub = bandEnergy(loHz: 20, hiHz: 250)
        let mid = bandEnergy(loHz: 250, hiHz: 4_000)
        let tre = bandEnergy(loHz: 4_000, hiHz: min(20_000, nyquist))

        lock.withLock {
            // 1s EMA on spectral bands (analysis queue ~94 Hz, α=0.1).
            subEnergyEMA    = subEnergyEMA * 0.9 + sub * 0.1
            midEnergyEMA    = midEnergyEMA * 0.9 + mid * 0.1
            trebleEnergyEMA = trebleEnergyEMA * 0.9 + tre * 0.1

            recomputeSnapshotLocked()
        }
    }

    // MARK: - Snapshot

    /// Return a thread-safe copy of the current quality state.
    public func currentSnapshot() -> InputLevelSnapshot {
        lock.withLock { snapshot }
    }

    // MARK: - Classification

    private func recomputeSnapshotLocked() {
        let peak = peakEnvelope
        let rms = rmsEnvelope

        let total = subEnergyEMA + midEnergyEMA + trebleEnergyEMA
        let subR = total > 1e-10 ? subEnergyEMA / total : 0
        let midR = total > 1e-10 ? midEnergyEMA / total : 0
        let treR = total > 1e-10 ? trebleEnergyEMA / total : 0

        let peakDB: Float = peak > 1e-9 ? 20 * log10f(peak) : -120
        let rmsDB: Float = rms > 1e-9 ? 20 * log10f(rms) : -120

        let (quality, reason): (SignalQuality, String)
        if totalFrames < Self.warmupFrames {
            (quality, reason) = (.unknown, "warming up")
        } else if peak < 1e-6 {
            (quality, reason) = (.red, "no signal — check output device / app is playing")
        } else if peakDB < Self.peakCriticalDBFS {
            let dBStr = String(format: "peak %.0f dBFS", peakDB)
            let hint = "output routed through Multi-Output/BlackHole, or Spotify Normalize on, or system volume low"
            (quality, reason) = (.red, "\(dBStr) — \(hint)")
        } else if peakDB < Self.peakWarningDBFS {
            (quality, reason) = (.yellow, String(format:
                "peak %.0f dBFS — raise system volume, check source-app normalization",
                peakDB))
        } else {
            // Treble ratio is shown for reference only — many modern productions
            // are genuinely bass-heavy and register below 1% without any chain
            // issue (Billie Eilish / Oxytocin verified clean at 0.2% treble).
            let msg = String(format: "peak %.0f dBFS, treble %.2f%% — OK", peakDB, 100 * treR)
            (quality, reason) = (.green, msg)
        }

        // Hysteresis: only publish a new quality if the candidate has
        // persisted for `gradeSwitchFrames` updates.  Keeps the public
        // grade stable and stops log flapping.
        if quality == snapshot.quality {
            pendingQuality = snapshot.quality
            pendingCount = 0
        } else if quality == pendingQuality {
            pendingCount &+= 1
        } else {
            pendingQuality = quality
            pendingCount = 1
        }
        let publishedQuality = (pendingCount >= Self.gradeSwitchFrames
                                || snapshot.quality == .unknown)
            ? quality : snapshot.quality
        let publishedReason = publishedQuality == quality ? reason : snapshot.reason

        snapshot = InputLevelSnapshot(
            peakDBFS: peakDB,
            rmsDBFS: rmsDB,
            subRatio: subR,
            midRatio: midR,
            trebleRatio: treR,
            quality: publishedQuality,
            reason: publishedReason,
            frameCount: totalFrames
        )
    }

    /// Reset all envelopes — call when capture restarts (new tap install).
    public func reset() {
        lock.withLock {
            peakEnvelope = 0
            rmsEnvelope = 0
            subEnergyEMA = 0
            midEnergyEMA = 0
            trebleEnergyEMA = 0
            totalFrames = 0
            snapshot = InputLevelSnapshot()
        }
    }
}
