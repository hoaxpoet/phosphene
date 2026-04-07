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
///
/// Usage:
/// ```swift
/// let pipeline = MIRPipeline()
/// // Each frame:
/// let fv = pipeline.process(magnitudes: fftMagnitudes, fps: 60, time: t, deltaTime: dt)
/// // fv is ready for GPU upload. CPU-side extras:
/// let chroma = pipeline.latestChroma
/// let key = pipeline.estimatedKey
/// let bpm = pipeline.estimatedTempo
/// ```
public final class MIRPipeline: @unchecked Sendable {

    // MARK: - Sub-Analyzers

    /// Spectral centroid, rolloff, and flux.
    public let spectralAnalyzer: SpectralAnalyzer

    /// 3-band and 6-band energy with AGC and smoothing.
    public let bandEnergyProcessor: BandEnergyProcessor

    /// 12-bin chroma vector and key estimation.
    public let chromaExtractor: ChromaExtractor

    /// Onset detection, beat pulses, and tempo estimation.
    public let beatDetector: BeatDetector

    // MARK: - CPU-Side Properties

    /// Latest 12-bin chroma vector (C, C#, D, ..., B). Not in FeatureVector.
    public private(set) var latestChroma: [Float] = [Float](repeating: 0, count: 12)

    /// Latest estimated musical key (e.g. "C major", "A minor"), or nil.
    public private(set) var estimatedKey: String?

    /// Latest key estimation confidence, 0–1.
    public private(set) var keyConfidence: Float = 0

    /// Latest estimated tempo in BPM, or nil if insufficient data.
    public private(set) var estimatedTempo: Float?

    /// Latest tempo estimation confidence, 0–1.
    public private(set) var tempoConfidence: Float = 0

    /// Latest spectral rolloff in Hz.
    public private(set) var spectralRolloff: Float = 0

    /// Latest best Pearson correlation with any major key profile, 0–1.
    public private(set) var latestMajorKeyCorrelation: Float = 0

    /// Latest best Pearson correlation with any minor key profile, 0–1.
    public private(set) var latestMinorKeyCorrelation: Float = 0

    /// Hysteresis-filtered stable key from ChromaExtractor.
    public private(set) var stableKey: String?

    /// Hysteresis-filtered stable BPM from BeatDetector.
    public private(set) var stableBPM: Float?

    /// Raw per-second IOI histogram BPM for debugging.
    public private(set) var instantBPM: Float?

    /// Feature stability ramp: 0.0 for first 3s, linear to 1.0 at 10s.
    public private(set) var featureStability: Float = 0

    /// Raw smoothed spectral flux (not normalized). For mood classifier z-score input.
    public private(set) var rawSmoothedFlux: Float = 0

    /// Raw smoothed spectral centroid in Hz (not normalized). For mood classifier z-score input.
    public private(set) var rawSmoothedCentroid: Float = 0

    /// Elapsed seconds since last reset, for stability ramp.
    private var elapsedSeconds: Float = 0

    /// Number of onsets detected per second (for BPM debugging).
    public private(set) var onsetsPerSecond: Int = 0

    /// Internal onset counter for the current second.
    private var onsetCountThisSecond: Int = 0

    /// Elapsed seconds tracker for onset rate measurement.
    private var lastOnsetRateTime: Float = 0

    // MARK: - Feature Recording

    /// File handle for recording mode (nil = not recording).
    private var recordingHandle: FileHandle?

    /// Last recording write time (to throttle to 1 row/sec).
    private var lastRecordTime: Float = 0

    /// Whether recording mode is active.
    public var isRecording: Bool { recordingHandle != nil }

    // MARK: - Normalization State

    /// Running max for spectral flux normalization.
    private var fluxRunningMax: Float = 1e-6

    /// Decay rate for flux running max (slowly forgets old peaks).
    private static let fluxMaxDecay: Float = 0.999

    /// Nyquist frequency for centroid normalization.
    private let nyquist: Float

    /// Thread safety for CPU-side properties.
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
        let beat = beatDetector.process(magnitudes: magnitudes, fps: fps, deltaTime: deltaTime)

        // Normalize spectral features for FeatureVector (0–1 range).
        // Use smoothed values for stable GPU input.
        let normalizedCentroid = nyquist > 0 ? spectral.smoothedCentroid / nyquist : 0

        // Flux normalization via running max (using smoothed flux).
        lock.lock()
        fluxRunningMax = max(fluxRunningMax * Self.fluxMaxDecay, spectral.smoothedFlux)
        let normalizedFlux = fluxRunningMax > 1e-10 ? spectral.smoothedFlux / fluxRunningMax : 0

        // Update elapsed time and feature stability ramp.
        elapsedSeconds += deltaTime
        featureStability = min(1.0, max(0.0, (elapsedSeconds - 3.0) / 7.0))

        // Update CPU-side properties.
        latestChroma = chroma.chroma
        estimatedKey = chroma.stableKey ?? chroma.estimatedKey
        stableKey = chroma.stableKey
        keyConfidence = chroma.keyConfidence
        estimatedTempo = beat.estimatedTempo
        tempoConfidence = beat.tempoConfidence
        stableBPM = beat.stableBPM > 0 ? beat.stableBPM : nil
        instantBPM = beat.instantBPM > 0 ? beat.instantBPM : nil
        spectralRolloff = spectral.rolloff
        latestMajorKeyCorrelation = chroma.majorKeyCorrelation
        latestMinorKeyCorrelation = chroma.minorKeyCorrelation
        rawSmoothedFlux = spectral.smoothedFlux
        rawSmoothedCentroid = spectral.smoothedCentroid

        // Track onsets per second for BPM debugging.
        if beat.onsets.contains(true) {
            onsetCountThisSecond += 1
        }
        if elapsedSeconds - lastOnsetRateTime >= 1.0 {
            onsetsPerSecond = onsetCountThisSecond
            onsetCountThisSecond = 0
            lastOnsetRateTime = elapsedSeconds
        }

        lock.unlock()

        // Write recording row (throttled to 1/sec inside the method).
        let centroidNorm = nyquist > 0 ? spectral.smoothedCentroid / nyquist : 0
        writeRecordingRow(
            energy: energy, centroid: centroidNorm, flux: spectral.smoothedFlux,
            majorCorr: chroma.majorKeyCorrelation, minorCorr: chroma.minorKeyCorrelation
        )

        // Assemble FeatureVector.
        return FeatureVector(
            bass: energy.bass,
            mid: energy.mid,
            treble: energy.treble,
            bassAtt: energy.bassAtt,
            midAtt: energy.midAtt,
            trebleAtt: energy.trebleAtt,
            subBass: energy.subBass,
            lowBass: energy.lowBass,
            lowMid: energy.lowMid,
            midHigh: energy.midHigh,
            highMid: energy.highMid,
            high: energy.high,
            beatBass: beat.beatBass,
            beatMid: beat.beatMid,
            beatTreble: beat.beatTreble,
            beatComposite: beat.beatComposite,
            spectralCentroid: normalizedCentroid,
            spectralFlux: normalizedFlux,
            valence: 0,   // ML module responsibility
            arousal: 0,   // ML module responsibility
            time: time,
            deltaTime: deltaTime
        )
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
        let header = "timestamp,subBass,lowBass,lowMid,midHigh,highMid,high,"
            + "centroid,flux,majorCorr,minorCorr,stableKey,stableBPM,"
            + "valence,arousal,quadrant\n"
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

        let row = String(
            format: "%.1f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%@,%.1f,,,\n",
            elapsedSeconds,
            energy.subBass, energy.lowBass, energy.lowMid,
            energy.midHigh, energy.highMid, energy.high,
            centroid, flux, majorCorr, minorCorr,
            stableKey ?? "nil",
            stableBPM ?? 0
        )
        handle.write(Data(row.utf8))
    }

    /// Reset all analyzers and internal state.
    public func reset() {
        spectralAnalyzer.reset()
        bandEnergyProcessor.reset()
        beatDetector.reset()
        chromaExtractor.resetAccumulators()

        lock.lock()
        fluxRunningMax = 1e-6
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
