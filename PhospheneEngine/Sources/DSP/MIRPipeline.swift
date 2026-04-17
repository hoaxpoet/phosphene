// MIRPipeline — Coordinator for all MIR feature extraction.
// Owns the four analyzers (SpectralAnalyzer, BandEnergyProcessor, ChromaExtractor,
// BeatDetector), runs them in sequence, and populates a FeatureVector for GPU upload.
// Chroma, key, and tempo are exposed as CPU-side properties for the Orchestrator.

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
    private var elapsedSeconds: Float = 0
    /// Latest structural prediction from StructuralAnalyzer.
    public private(set) var latestStructuralPrediction: StructuralPrediction = .none
    /// Number of onsets detected per second (for BPM debugging).
    public private(set) var onsetsPerSecond: Int = 0
    private var onsetCountThisSecond: Int = 0
    private var lastOnsetRateTime: Float = 0

    // MARK: - Feature Recording

    private var recordingHandle: FileHandle?
    private var lastRecordTime: Float = 0
    /// Whether recording mode is active.
    public var isRecording: Bool { recordingHandle != nil }
    /// Current track info for recording. Set by the app layer.
    public var currentTrackName: String = ""
    public var currentArtistName: String = ""

    // MARK: - Normalization State

    private var fluxRunningMax: Float = 1e-6
    private static let fluxMaxDecay: Float = 0.999
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

        elapsedSeconds += ctx.deltaTime
        featureStability = min(1.0, max(0.0, (elapsedSeconds - 3.0) / 7.0))

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
        latestStructuralPrediction = structuralAnalyzer.process(
            chroma: ctx.chroma.chroma,
            spectral: StructuralAnalyzer.SpectralSummary(
                centroid: ctx.normalizedCentroid,
                flux: ctx.normalizedFlux,
                rolloff: normalizedRolloff,
                energy: totalEnergy
            ),
            time: ctx.time
        )

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
        // MV-1: Derive deviation primitives from AGC-normalized values.
        fv.bassRel = (fv.bass - 0.5) * 2.0
        fv.bassDev = max(0, fv.bassRel)
        fv.midRel  = (fv.mid - 0.5) * 2.0
        fv.midDev  = max(0, fv.midRel)
        fv.trebRel = (fv.treble - 0.5) * 2.0
        fv.trebDev = max(0, fv.trebRel)
        fv.bassAttRel = (fv.bassAtt - 0.5) * 2.0
        fv.midAttRel  = (fv.midAtt  - 0.5) * 2.0
        fv.trebAttRel = (fv.trebleAtt - 0.5) * 2.0
        return fv
    }

    // MARK: - Recording Mode

    /// Start recording feature vectors to CSV at ~/phosphene_features.csv.
    /// Writes one row per second with timestamp + 10 features.
    public func startRecording() {
        let path = NSHomeDirectory() + "/phosphene_features.csv"
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            logger.error("Failed to create recording file: \(path)")
            return
        }
        let header = "timestamp,track,artist,subBass,lowBass,lowMid,midHigh,highMid,high,"
            + "centroid,flux,majorCorr,minorCorr,stableKey,stableBPM,"
            + "valence,arousal\n"
        handle.write(Data(header.utf8))
        recordingHandle = handle
        lastRecordTime = elapsedSeconds
        logger.info("Recording started: \(path)")
    }

    /// Stop recording and close the file.
    public func stopRecording() {
        recordingHandle?.closeFile()
        recordingHandle = nil
        logger.info("Recording stopped")
    }

    /// Write a feature row if recording and throttle interval has passed.
    /// Called from process() with the current feature values.
    private func writeRecordingRow(
        energy: BandEnergyProcessor.Result,
        centroid: Float,
        flux: Float,
        majorCorr: Float,
        minorCorr: Float
    ) {
        guard let handle = recordingHandle else { return }
        guard elapsedSeconds - lastRecordTime >= 1.0 else { return }
        lastRecordTime = elapsedSeconds

        let track = currentTrackName.replacingOccurrences(of: ",", with: ";")
        let artist = currentArtistName.replacingOccurrences(of: ",", with: ";")
        let row = String(
            format: "%.1f,%@,%@,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%@,%.1f,,\n",
            elapsedSeconds,
            track,
            artist,
            energy.subBass,
            energy.lowBass,
            energy.lowMid,
            energy.midHigh,
            energy.highMid,
            energy.high,
            centroid,
            flux,
            majorCorr,
            minorCorr,
            stableKey ?? "",
            stableBPM ?? 0
        )
        handle.write(Data(row.utf8))
    }

    /// Reset all analyzers and internal state.
    public func reset() {
        logger.info("MIR_RESET: resetting all analyzers (track change)")
        spectralAnalyzer.reset()
        bandEnergyProcessor.reset()
        beatDetector.reset()
        chromaExtractor.resetAccumulators()

        structuralAnalyzer.reset()

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
