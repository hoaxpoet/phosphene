// MIRPipeline — Coordinator for all MIR feature extraction.
// Owns the four analyzers (SpectralAnalyzer, BandEnergyProcessor, ChromaExtractor,
// BeatDetector), runs them in sequence, and populates a FeatureVector for GPU upload.
// Chroma, key, and tempo are exposed as CPU-side properties for the Orchestrator.
// swiftlint:disable file_length

import Foundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "MIRPipeline")

// MARK: - MIRPipeline

/// Coordinates all MIR feature extraction and produces a `FeatureVector` per frame.
public final class MIRPipeline: @unchecked Sendable {

    // MARK: - Sub-Analyzers

    public let spectralAnalyzer: SpectralAnalyzer
    public let bandEnergyProcessor: BandEnergyProcessor
    public let chromaExtractor: ChromaExtractor
    public let beatDetector: BeatDetector
    public let structuralAnalyzer: StructuralAnalyzer
    /// MV-3b: Beat phase predictor — used in reactive mode (no offline grid).
    /// Live tracks fall back to this when `liveDriftTracker.hasGrid == false`.
    public let beatPredictor: BeatPredictor

    /// DSP.2 S7: drift tracker against an offline `BeatGrid`. Owns the live
    /// `beatPhase01` / `beatsUntilNext` for tracks with cached Beat This!
    /// analysis. Created once at init; populated via `setBeatGrid(_:)` on
    /// track change. Empty grid → tracker returns zero phase and the pipeline
    /// falls back to `beatPredictor` in `buildFeatureVector`.
    public let liveDriftTracker: LiveBeatDriftTracker

    // MARK: - CPU-Side Properties

    /// Latest 12-bin chroma vector (C, C#, D, ..., B). Not in FeatureVector.
    public private(set) var latestChroma: [Float] = [Float](repeating: 0, count: 12)
    /// Latest estimated musical key, or nil.
    public private(set) var estimatedKey: String?
    /// Latest key estimation confidence, 0-1.
    public private(set) var keyConfidence: Float = 0
    /// Latest estimated tempo in BPM, or nil if insufficient data.
    public private(set) var estimatedTempo: Float?
    /// Latest tempo estimation confidence, 0-1.
    public private(set) var tempoConfidence: Float = 0
    /// Latest spectral rolloff in Hz.
    public private(set) var spectralRolloff: Float = 0
    /// Latest best Pearson correlation with any major key profile, 0-1.
    public private(set) var latestMajorKeyCorrelation: Float = 0
    /// Latest best Pearson correlation with any minor key profile, 0-1.
    public private(set) var latestMinorKeyCorrelation: Float = 0
    /// Hysteresis-filtered stable key from ChromaExtractor.
    public private(set) var stableKey: String?
    /// Hysteresis-filtered stable BPM from BeatDetector.
    public private(set) var stableBPM: Float?
    /// Raw per-second IOI histogram BPM for debugging.
    public private(set) var instantBPM: Float?
    /// Number of bass onset timestamps in the BeatDetector's sliding window.
    public private(set) var bassOnsetCount: Int = 0
    /// Debug string from BeatDetector tempo estimation.
    public private(set) var tempoDebug: String = ""
    /// Feature stability ramp: 0.0 for first 3s, linear to 1.0 at 10s.
    public private(set) var featureStability: Float = 0
    /// Raw smoothed spectral flux (not normalized). For mood classifier z-score input.
    public private(set) var rawSmoothedFlux: Float = 0
    /// Raw smoothed spectral centroid in Hz (not normalized). For mood classifier z-score input.
    public private(set) var rawSmoothedCentroid: Float = 0
    /// Track-relative playback clock in seconds. Reset to 0 on track change.
    ///
    /// Stored as `Double` (D-079, QR.1) so per-frame `+= deltaTime`
    /// accumulation has stable resolution over a long session. At Float
    /// precision the ULP at 30 minutes is ≈ 240 µs — smaller than the ±30 ms
    /// tight-match window used by `LiveBeatDriftTracker`, but a guaranteed
    /// monotonic drift that compounds over hours of listening. Consumers
    /// that need a Float (FeatureVector field, BeatSyncSnapshot CSV column)
    /// cast at the read site, not the storage site.
    public private(set) var elapsedSeconds: Double = 0
    /// Latest structural prediction from StructuralAnalyzer.
    public private(set) var latestStructuralPrediction: StructuralPrediction = .none
    /// Number of onsets detected per second (for BPM debugging).
    public private(set) var onsetsPerSecond: Int = 0
    private var onsetCountThisSecond: Int = 0
    private var lastOnsetRateTime: Double = 0

    // MARK: - Feature Recording

    var recordingHandle: FileHandle?
    var lastRecordTime: Double = 0
    /// Whether recording mode is active.
    public var isRecording: Bool { recordingHandle != nil }
    /// Current track info for recording. Set by the app layer.
    public var currentTrackName: String = ""
    public var currentArtistName: String = ""

    // MARK: - CSP.3 — FFO cold-start fix toggle

    /// Toggle for the CSP.3 Ferrofluid Ocean cold-start fix. App layer reads
    /// `UserDefaults.standard.bool(forKey: "ffoColdStartFixEnabled")` at
    /// VisualizerEngine init and applies via this property. Default `true` —
    /// CSP.3 is the experiment arm of Matt's A/B. To run the off-side
    /// without recompiling:
    /// ```
    /// defaults write com.phosphene.app ffoColdStartFixEnabled -bool NO
    /// ```
    ///
    /// **When false**, `buildFeatureVector` writes `trackElapsedS = 100.0`
    /// instead of the real elapsed time, so the FFO shader's
    /// `smoothstep(0.5, 14, trackElapsedS)` returns 1.0 — the cold-start
    /// crossfade collapses to the warm path. Combined with the app layer
    /// also writing `cachedBassProportion = 0.25` (pivot) when off,
    /// `fo_spike_strength` reduces exactly to the pre-CSP.3 formula
    /// `1.0 + 0.35 * stems.bass_energy_dev`. A/B-able from the same build.
    public var ffoColdStartFixEnabled: Bool = true

    // MARK: - Normalization State

    private var fluxRunningMax: Float = 1e-6
    private static let fluxMaxDecay: Float = 0.999
    /// MV-1 / D-146 (BUG-027): per-band running-average pivot for the deviation
    /// primitives. Each band's deviation is measured against its own recent
    /// average (mirroring StemAnalyzer's per-stem EMA), not a fixed 0.5 — the
    /// total-energy AGC centres each band below 0.5, which left the fixed-pivot
    /// midDev/trebDev structurally dead. Updated in `buildFeatureVector`, reset
    /// on track change.
    private var bandDeviationTracker = BandDeviationTracker()
    /// FBS Stage 1 (D-153) — steady first-note-anchored beat pulse. Tempo is
    /// installed by `setBeatGrid`; the anchor resets per track in `reset()`;
    /// the per-frame output lands on `FeatureVector.pulsePhase01/pulseAmp01`.
    private let beatPulseClock = BeatPulseClock()
    private let nyquist: Float
    private let lock = NSLock()

    // MARK: - Init

    /// Create a MIR pipeline with default configuration.
    ///
    /// - Parameters:
    ///   - binCount: Number of FFT magnitude bins (default 512).
    ///   - sampleRate: Sample rate in Hz (default 48000).
    ///   - fftSize: FFT size (default 1024).
    public init(binCount: Int = 512, sampleRate: Float = 48000, fftSize: Int = 1024) {
        self.spectralAnalyzer = SpectralAnalyzer(
            binCount: binCount, sampleRate: sampleRate, fftSize: fftSize
        )
        self.bandEnergyProcessor = BandEnergyProcessor(
            binCount: binCount, sampleRate: sampleRate, fftSize: fftSize
        )
        self.chromaExtractor = ChromaExtractor(
            binCount: binCount, sampleRate: sampleRate, fftSize: fftSize
        )
        self.beatDetector = BeatDetector(
            binCount: binCount, sampleRate: sampleRate, fftSize: fftSize
        )
        self.structuralAnalyzer = StructuralAnalyzer()
        self.beatPredictor = BeatPredictor()
        self.liveDriftTracker = LiveBeatDriftTracker()
        self.nyquist = sampleRate / 2.0

        logger.info("MIRPipeline created: \(binCount) bins, \(sampleRate) Hz")
    }

    // MARK: - Processing

    /// Run all analyzers and produce a populated FeatureVector.
    ///
    /// - Parameters:
    ///   - magnitudes: FFT magnitude array (512 bins from 1024-point FFT).
    ///   - fps: Current frame rate for FPS-independent smoothing/decay.
    ///   - time: Seconds since visualization start.
    ///   - deltaTime: Seconds since last frame.
    /// - Returns: FeatureVector with all audio-derived fields populated.
    ///   `valence` and `arousal` are left at 0 (ML module responsibility).
    public func process(
        magnitudes: [Float],
        fps: Float,
        time: Float,
        deltaTime: Float
    ) -> FeatureVector {

        // Run all four analyzers.
        let spectral = spectralAnalyzer.process(magnitudes: magnitudes)
        let energy = bandEnergyProcessor.process(magnitudes: magnitudes, fps: fps)
        let chroma = chromaExtractor.process(magnitudes: magnitudes)
        let beat = beatDetector.process(
            magnitudes: magnitudes, fps: fps, deltaTime: deltaTime
        )

        // Normalize spectral features for FeatureVector (0-1 range).
        let normalizedCentroid = nyquist > 0
            ? spectral.smoothedCentroid / nyquist : 0
        let normalizedFlux = normalizeFlux(spectral.smoothedFlux)

        // Bundle intermediate results for helper methods.
        let context = ProcessContext(
            spectral: spectral,
            energy: energy,
            chroma: chroma,
            beat: beat,
            normalizedCentroid: normalizedCentroid,
            normalizedFlux: normalizedFlux,
            time: time,
            deltaTime: deltaTime
        )

        // Update CPU-side properties under lock.
        updateCPUSideProperties(context)

        // Run structural analysis and write recording row.
        updateStructuralAnalysis(context)

        return buildFeatureVector(context)
    }

    // MARK: - Process Helpers

    /// Bundles intermediate analyzer results for passing between helper methods.
    private struct ProcessContext {
        let spectral: SpectralAnalyzer.Result
        let energy: BandEnergyProcessor.Result
        let chroma: ChromaExtractor.Result
        let beat: BeatDetector.Result
        let normalizedCentroid: Float
        let normalizedFlux: Float
        let time: Float
        let deltaTime: Float
    }

    /// Normalize spectral flux via running-max AGC.
    private func normalizeFlux(_ smoothedFlux: Float) -> Float {
        lock.lock()
        fluxRunningMax = max(
            fluxRunningMax * Self.fluxMaxDecay, smoothedFlux
        )
        let result = fluxRunningMax > 1e-10
            ? smoothedFlux / fluxRunningMax : 0
        lock.unlock()
        return result
    }

    /// Update all CPU-side properties from analyzer results (under lock).
    private func updateCPUSideProperties(_ ctx: ProcessContext) {
        lock.lock()

        elapsedSeconds += Double(ctx.deltaTime)
        featureStability = Float(min(1.0, max(0.0, (elapsedSeconds - 3.0) / 7.0)))

        latestChroma = ctx.chroma.chroma
        estimatedKey = ctx.chroma.stableKey ?? ctx.chroma.estimatedKey
        stableKey = ctx.chroma.stableKey
        keyConfidence = ctx.chroma.keyConfidence
        estimatedTempo = ctx.beat.estimatedTempo
        tempoConfidence = ctx.beat.tempoConfidence
        stableBPM = ctx.beat.stableBPM > 0 ? ctx.beat.stableBPM : nil
        instantBPM = ctx.beat.instantBPM > 0 ? ctx.beat.instantBPM : nil
        bassOnsetCount = ctx.beat.bassOnsetCount
        tempoDebug = beatDetector.tempoDebug
        spectralRolloff = ctx.spectral.rolloff
        latestMajorKeyCorrelation = ctx.chroma.majorKeyCorrelation
        latestMinorKeyCorrelation = ctx.chroma.minorKeyCorrelation
        rawSmoothedFlux = ctx.spectral.smoothedFlux
        rawSmoothedCentroid = ctx.spectral.smoothedCentroid

        if ctx.beat.onsets.contains(true) {
            onsetCountThisSecond += 1
        }
        if elapsedSeconds - lastOnsetRateTime >= 1.0 {
            onsetsPerSecond = onsetCountThisSecond
            onsetCountThisSecond = 0
            lastOnsetRateTime = elapsedSeconds
        }

        lock.unlock()
    }

    /// Run structural analysis and write a recording row.
    private func updateStructuralAnalysis(_ ctx: ProcessContext) {
        let normalizedRolloff = nyquist > 0 ? ctx.spectral.rolloff / nyquist : 0
        let totalEnergy = (ctx.energy.bass + ctx.energy.mid + ctx.energy.treble) / 3.0
        // BUG-040: the analyzer's clock is the pipeline's OWN track-relative
        // `elapsedSeconds` — NEVER `ctx.time`. The live caller hardwires
        // `time: 0` (VisualizerEngine+Audio passes 0; fv.time is populated
        // separately), which froze the analyzer's clock at zero: boundary
        // timestamps came out NEGATIVE (0 − frames-from-end/fps ≈ −0.3 s),
        // section durations were ±0.x s noise, and confidence was
        // structurally pinned low. `elapsedSeconds` resets on `reset()`
        // exactly when `structuralAnalyzer.reset()` fires, so the clock and
        // the frame counter stay in the same (track-relative) timebase.
        lock.lock()
        let structuralTime = Float(elapsedSeconds)   // D-079: Double store, Float at the read site
        lock.unlock()
        let prediction = structuralAnalyzer.process(
            chroma: ctx.chroma.chroma,
            spectral: StructuralAnalyzer.SpectralSummary(
                centroid: ctx.normalizedCentroid,
                flux: ctx.normalizedFlux,
                rolloff: normalizedRolloff,
                energy: totalEnergy
            ),
            time: structuralTime
        )
        // Published-property write goes under the lock like every other
        // CPU-side property (BUG-035 related finding; class is @unchecked Sendable).
        lock.lock()
        latestStructuralPrediction = prediction
        lock.unlock()

        let centroidNorm = nyquist > 0
            ? ctx.spectral.smoothedCentroid / nyquist : 0
        writeRecordingRow(
            energy: ctx.energy,
            centroid: centroidNorm,
            flux: ctx.spectral.smoothedFlux,
            majorCorr: ctx.chroma.majorKeyCorrelation,
            minorCorr: ctx.chroma.minorKeyCorrelation
        )
    }

    /// Assemble a FeatureVector from analyzer results.
    ///
    /// MV-1: deviation primitives (bassRel, bassDev, etc.) are derived here
    /// from the AGC-normalized energy fields. Formula: xRel = (x - 0.5) * 2.0,
    /// xDev = max(0, xRel). These are stable across mix-density changes because
    /// the AGC numerator and denominator track together (D-026).
    ///
    /// MV-3b: beatPhase01 and beatsUntilNext are populated from BeatPredictor
    /// each frame, enabling anticipatory motion in preset shaders (D-028).
    /// Derive the deviation primitives against each band's own running average (D-146 / BUG-027)
    /// and write them into the FeatureVector. The total-energy AGC (fv.bass/mid/treble) is
    /// untouched — only the *Rel/*Dev derivation moves off the fixed 0.5 pivot. Mirrors
    /// StemAnalyzer's per-stem EMA so the long-dead midDev/trebDev fire on real music again.
    private func applyBandDeviations(to fv: inout FeatureVector) {
        let out = bandDeviationTracker.derive(BandDeviationTracker.BandEnergies(
            bass: fv.bass,
            mid: fv.mid,
            treble: fv.treble,
            bassAtt: fv.bassAtt,
            midAtt: fv.midAtt,
            trebleAtt: fv.trebleAtt
        ))
        fv.bassRel = out.bassRel
        fv.bassDev = out.bassDev
        fv.midRel = out.midRel
        fv.midDev = out.midDev
        fv.trebRel = out.trebRel
        fv.trebDev = out.trebDev
        fv.bassAttRel = out.bassAttRel
        fv.midAttRel = out.midAttRel
        fv.trebAttRel = out.trebAttRel
    }

    private func buildFeatureVector(_ ctx: ProcessContext) -> FeatureVector {
        var fv = FeatureVector(
            bass: ctx.energy.bass,
            mid: ctx.energy.mid,
            treble: ctx.energy.treble,
            bassAtt: ctx.energy.bassAtt,
            midAtt: ctx.energy.midAtt,
            trebleAtt: ctx.energy.trebleAtt,
            subBass: ctx.energy.subBass,
            lowBass: ctx.energy.lowBass,
            lowMid: ctx.energy.lowMid,
            midHigh: ctx.energy.midHigh,
            highMid: ctx.energy.highMid,
            high: ctx.energy.high,
            beatBass: ctx.beat.beatBass,
            beatMid: ctx.beat.beatMid,
            beatTreble: ctx.beat.beatTreble,
            beatComposite: ctx.beat.beatComposite,
            spectralCentroid: ctx.normalizedCentroid,
            spectralFlux: ctx.normalizedFlux,
            valence: 0,   // ML module responsibility
            arousal: 0,   // ML module responsibility
            time: ctx.time,
            deltaTime: ctx.deltaTime
        )
        // CSP.3 — track-relative elapsed seconds for shader-side cold-start
        // crossfade. Reset to 0 by reset() on track change. Double storage,
        // Float upload (D-079 / QR.1). When `ffoColdStartFixEnabled` is OFF,
        // write 100.0 so the FFO shader's smoothstep(0.5, 14, ...) returns
        // 1.0 — the cold-start path collapses to the warm path, restoring
        // pre-CSP.3 behaviour without recompiling.
        fv.trackElapsedS = ffoColdStartFixEnabled ? Float(elapsedSeconds) : 100.0
        // MV-1 / D-146 (BUG-027): derive deviation primitives against each band's own
        // running average (per-band EMA), not a fixed 0.5 pivot — see applyBandDeviations.
        applyBandDeviations(to: &fv)
        // FBS Stage 1 (D-153) — steady first-note-anchored beat pulse. Anchored
        // at the track's first audible frame, ticking at the cached-grid tempo,
        // never drift-corrected (deliberately independent of liveDriftTracker —
        // its correction wanders 50–90 ms over the opening, Stage 0 finding).
        let pulse = beatPulseClock.update(
            energySum: fv.bass + fv.mid + fv.treble,
            time: elapsedSeconds,
            deltaTime: ctx.deltaTime
        )
        fv.pulsePhase01 = pulse.phase01
        fv.pulseAmp01 = pulse.amp01
        // DSP.2 S7: prefer the offline-grid drift tracker when a cached
        // `BeatGrid` is installed.  In reactive mode (no grid), fall back to
        // the legacy `BeatPredictor` IIR estimator.
        if liveDriftTracker.hasGrid {
            let driftResult = liveDriftTracker.update(
                subBassOnset: ctx.beat.onsets[0],
                playbackTime: elapsedSeconds,   // Double (QR.1 / D-079)
                deltaTime: ctx.deltaTime
            )
            fv.beatPhase01    = driftResult.beatPhase01
            fv.beatsUntilNext = driftResult.beatsUntilNext
            fv.barPhase01     = driftResult.barPhase01
            fv.beatsPerBar    = Float(driftResult.beatsPerBar)
        } else {
            let predictorResult = beatPredictor.update(
                subBassOnset: ctx.beat.onsets[0],
                beatMid: ctx.beat.beatMid,
                beatComposite: ctx.beat.beatComposite,
                stableBPM: stableBPM ?? 0,
                time: ctx.time,
                deltaTime: ctx.deltaTime
            )
            fv.beatPhase01    = predictorResult.beatPhase01
            fv.beatsUntilNext = predictorResult.beatsUntilNext
            fv.barPhase01     = 0   // reactive: no downbeat info
            fv.beatsPerBar    = 4   // assume 4/4 until BeatGrid available
        }
        return fv
    }

    // MARK: - Live Drift Grid

    /// Install or clear the offline `BeatGrid` consumed by `liveDriftTracker`.
    /// Pass `nil` (or `.empty`) to revert to reactive-mode behaviour, which
    /// uses `BeatPredictor` for `beatPhase01` / `beatsUntilNext`.
    /// Call from the app layer on track change after consulting `StemCache`.
    public func setBeatGrid(_ grid: BeatGrid?) {
        liveDriftTracker.setGrid(grid ?? .empty)
        beatPulseClock.setTempo(bpm: grid?.bpm)   // FBS Stage 1 (D-153)
        logger.info("MIR_BEAT_GRID: set (\(grid?.beats.count ?? 0) beats)")
    }

    /// Set the offline `BeatGrid` AND seed the drift EMA with the calibrated
    /// per-track offset (BUG-007.8). Used by the prepared-cache install path.
    public func setBeatGrid(_ grid: BeatGrid?, initialDriftMs: Double) {
        liveDriftTracker.setGrid(grid ?? .empty, initialDriftMs: initialDriftMs)
        beatPulseClock.setTempo(bpm: grid?.bpm)   // FBS Stage 1 (D-153)
        let driftStr = String(format: "%+.1f", initialDriftMs)
        logger.info("MIR_BEAT_GRID: set (\(grid?.beats.count ?? 0) beats, initialDrift=\(driftStr) ms)")
    }

    /// Reset all analyzers and internal state.
    public func reset() {
        logger.info("MIR_RESET: resetting all analyzers (track change)")
        spectralAnalyzer.reset()
        bandEnergyProcessor.reset()
        beatDetector.reset()
        chromaExtractor.resetAccumulators()
        structuralAnalyzer.reset()
        beatPredictor.reset()
        liveDriftTracker.reset()
        bandDeviationTracker.reset()
        // FBS Stage 1 (D-153) — new track, new first-note anchor. Tempo is
        // intentionally NOT cleared here: `setBeatGrid` is the sole tempo
        // authority and the track-change call order between `reset()` and the
        // grid install differs across the LF / streaming paths.
        beatPulseClock.resetAnchor()

        lock.lock()
        fluxRunningMax = 1e-6
        latestStructuralPrediction = .none
        latestChroma = [Float](repeating: 0, count: 12)
        estimatedKey = nil
        stableKey = nil
        keyConfidence = 0
        estimatedTempo = nil
        tempoConfidence = 0
        stableBPM = nil
        instantBPM = nil
        spectralRolloff = 0
        latestMajorKeyCorrelation = 0
        latestMinorKeyCorrelation = 0
        elapsedSeconds = 0
        featureStability = 0
        rawSmoothedFlux = 0
        rawSmoothedCentroid = 0
        onsetsPerSecond = 0
        onsetCountThisSecond = 0
        lastOnsetRateTime = 0
        lastRecordTime = 0
        lock.unlock()
    }
}
