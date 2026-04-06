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
        let normalizedCentroid = nyquist > 0 ? spectral.centroid / nyquist : 0

        // Flux normalization via running max.
        lock.lock()
        fluxRunningMax = max(fluxRunningMax * Self.fluxMaxDecay, spectral.flux)
        let normalizedFlux = fluxRunningMax > 1e-10 ? spectral.flux / fluxRunningMax : 0

        // Update CPU-side properties.
        latestChroma = chroma.chroma
        estimatedKey = chroma.estimatedKey
        keyConfidence = chroma.keyConfidence
        estimatedTempo = beat.estimatedTempo
        tempoConfidence = beat.tempoConfidence
        spectralRolloff = spectral.rolloff
        lock.unlock()

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

    /// Reset all analyzers and internal state.
    public func reset() {
        spectralAnalyzer.reset()
        bandEnergyProcessor.reset()
        beatDetector.reset()

        lock.lock()
        fluxRunningMax = 1e-6
        latestChroma = [Float](repeating: 0, count: 12)
        estimatedKey = nil
        keyConfidence = 0
        estimatedTempo = nil
        tempoConfidence = 0
        spectralRolloff = 0
        lock.unlock()
    }
}
