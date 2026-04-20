// StemAnalyzer — Per-stem energy and beat analysis for the live stem pipeline.
// Holds 4× BandEnergyProcessor (one per stem) + 1× BeatDetector on drums.
// Takes mono waveform samples from stem separation, runs a lightweight FFT
// to get magnitudes, then feeds them to existing DSP primitives.
//
// MV-3a (D-028): added per-stem rich metadata computed each frame:
//   - {stem}OnsetRate     — onset events/sec via leaky integrator (0.5s window)
//   - {stem}Centroid      — spectral centroid normalized by Nyquist [0,1]
//   - {stem}AttackRatio   — fastRMS(50ms) / slowRMS(500ms), clamped 0–3
//   - {stem}EnergySlope   — derivative of attenuated energy, FPS-independent
//
// MV-3c (D-028): added vocal pitch tracking via PitchTracker (YIN).
//   - vocalsPitchHz        — YIN autocorrelation estimate, 0 = unvoiced
//   - vocalsPitchConfidence — 0–1 reliability score

import Foundation
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene", category: "dsp")

// MARK: - Protocol

/// Abstracts per-stem analysis for test doubles.
public protocol StemAnalyzing: AnyObject, Sendable {
    /// Analyze 4 stems and produce a StemFeatures snapshot for GPU upload.
    ///
    /// - Parameters:
    ///   - stemWaveforms: Array of 4 mono waveform arrays [vocals, drums, bass, other].
    ///   - fps: Effective frames per second (for smoothing).
    /// - Returns: Packed StemFeatures for buffer(3) binding.
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures

    /// Reset all internal state (e.g., on track change).
    func reset()
}

// MARK: - StemAnalyzer

/// Runs BandEnergyProcessor per stem and BeatDetector on drums.
///
/// The analyzer owns a lightweight vDSP FFT setup to convert stem waveforms
/// into magnitude spectra. This avoids coupling to Metal (FFTProcessor uses
/// UMABuffer). The FFT configuration matches FFTProcessor: 1024-point, 512 bins.
public final class StemAnalyzer: StemAnalyzing, @unchecked Sendable {

    // MARK: - Constants

    /// FFT size matching the main pipeline's FFTProcessor.
    static let fftSize = 1024
    static let binCount = fftSize / 2
    static let log2n = vDSP_Length(log2(Double(fftSize)))

    // MARK: - MV-3a: Per-Stem Rich State

    /// Mutable per-call state for MV-3a rich metadata computation.
    /// One element per stem (index 0=vocals, 1=drums, 2=bass, 3=other).
    struct StemRichState {
        // AttackRatio: EMA-based fast and slow RMS
        var fastRMS: Float = 1e-8     // ~50ms time constant
        var slowRMS: Float = 1e-8     // ~500ms time constant
        // EnergySlope: previous attenuated total energy
        var prevAttEnergy: Float = 0
        // OnsetRate: leaky integrator over ~0.5s
        var onsetAccum: Float = 0
        var prevRMS: Float = 0        // for flux detection
        var fluxEMA: Float = 1e-8     // adaptive threshold
        // Rising-edge detection + refractory period (fixed 2026-04-17).
        // Previous implementation counted every frame with flux > threshold
        // as a separate onset.  At 94 Hz frame rate, a single drum hit
        // spanning 3–5 frames registered as 3–5 onsets, producing 20+
        // onsets/sec in session 2026-04-17T19-31-46Z — saturating
        // downstream density/intensity drivers.  Now an "onset" is a
        // rising-edge transition across the threshold, followed by a
        // 100ms refractory period (max 600 BPM mono-stem detection).
        var aboveThreshold: Bool = false
        var framesSinceOnset: Int = 10_000
    }

    // MARK: - DSP Primitives

    /// Per-stem energy processors: [vocals, drums, bass, other].
    private let energyProcessors: [BandEnergyProcessor]

    /// Beat detector on the drums stem only.
    private let drumsBeatDetector: BeatDetector

    /// Pitch tracker on the vocals stem (MV-3c).
    private let pitchTracker: PitchTracker

    // MARK: - MV-1: Per-Stem EMA Running Averages

    /// Per-stem running average for deviation primitive computation (D-026).
    /// Order: [vocals, drums, bass, other].
    /// Decay ≈ 0.9989 per frame (~10s time constant at 94 Hz).
    ///
    /// Relaxed from 0.995 (τ≈2s) after session 2026-04-17T18-28-01Z diagnosis:
    /// on sustained loud sections (Slint "Good Morning, Captain" outro), a 2s
    /// EMA caught up within seconds and pushed *_energy_dev back toward zero
    /// even though the audio stayed loud.  Presets using dev as a driver
    /// (VolumetricLithograph v5) then read the outro as equivalent to the
    /// verse.  Extending τ to ~10s preserves dev across full musical phrases
    /// while AGC still adapts on section-change timescales.
    ///
    /// Formula: runningAvg = runningAvg * decay + energy * (1 - decay)
    /// Then: energyRel = (energy - runningAvg) * 2.0
    ///       energyDev = max(0, energyRel)
    private var stemRunningAvg: [Float] = [0, 0, 0, 0]
    private static let stemEMADecay: Float = 0.9989

    // MARK: - MV-3a: Rich State

    var richStates: [StemRichState] = [
        StemRichState(), StemRichState(), StemRichState(), StemRichState()
    ]
    let sampleRate: Float
    let nyquist: Float

    // MARK: - vDSP State (reused per call, no per-frame alloc)

    let fftSetup: FFTSetup
    var window: [Float]
    var windowedSamples: [Float]
    var realPart: [Float]
    var imagPart: [Float]
    var magnitudes: [Float]
    private let lock = NSLock()

    // MARK: - Init

    /// Create a stem analyzer.
    ///
    /// - Parameter sampleRate: Audio sample rate (default 44100 Hz, matching stem separator).
    public init(sampleRate: Float = 44100) {
        self.sampleRate = sampleRate
        self.nyquist = sampleRate / 2.0

        // 4 independent energy processors — one per stem.
        self.energyProcessors = (0..<4).map { _ in
            BandEnergyProcessor(binCount: Self.binCount, sampleRate: sampleRate, fftSize: Self.fftSize)
        }
        self.drumsBeatDetector = BeatDetector(
            binCount: Self.binCount, sampleRate: sampleRate, fftSize: Self.fftSize
        )
        self.pitchTracker = PitchTracker(sampleRate: sampleRate)

        // vDSP FFT setup.
        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed for stem analyzer")
        }
        self.fftSetup = setup

        // Pre-allocate working buffers.
        self.window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        self.windowedSamples = [Float](repeating: 0, count: Self.fftSize)
        self.realPart = [Float](repeating: 0, count: Self.binCount)
        self.imagPart = [Float](repeating: 0, count: Self.binCount)
        self.magnitudes = [Float](repeating: 0, count: Self.binCount)

        logger.info("StemAnalyzer initialized (4 energy + 1 beat + 1 pitch tracker)")
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - StemAnalyzing

    public func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures {
        guard stemWaveforms.count == 4 else {
            logger.error("StemAnalyzer expected 4 stems, got \(stemWaveforms.count)")
            return .zero
        }
        lock.lock()
        defer { lock.unlock() }
        let dt = fps > 0 ? 1.0 / fps : (1.0 / 60.0)
        let (vocalsResult, vocalsMags) = analyzeStem(stemWaveforms[0], processor: energyProcessors[0], fps: fps)
        let (drumsResult, _) = analyzeStem(stemWaveforms[1], processor: energyProcessors[1], fps: fps)
        let (bassResult, bassMags) = analyzeStem(stemWaveforms[2], processor: energyProcessors[2], fps: fps)
        let (otherResult, otherMags) = analyzeStem(stemWaveforms[3], processor: energyProcessors[3], fps: fps)
        let drumsMags = computeMagnitudes(from: stemWaveforms[1])
        let beatResult = drumsBeatDetector.process(magnitudes: drumsMags, fps: fps, deltaTime: dt)
        let vocalsE = vocalsResult.bass + vocalsResult.mid + vocalsResult.treble
        let drumsE = drumsResult.bass + drumsResult.mid + drumsResult.treble
        let bassE = bassResult.bass + bassResult.mid + bassResult.treble
        let otherE = otherResult.bass + otherResult.mid + otherResult.treble
        let devs = updateEMAsAndComputeDeviations(vocalsE: vocalsE, drumsE: drumsE, bassE: bassE, otherE: otherE)
        let allResults: [BandEnergyProcessor.Result] = [vocalsResult, drumsResult, bassResult, otherResult]
        let allMags = [vocalsMags, drumsMags, bassMags, otherMags]
        let richAll = computeAllRichFeatures(stemWaveforms: stemWaveforms, results: allResults, mags: allMags, dt: dt)
        let (pitchHz, pitchConf) = pitchTracker.process(waveform: stemWaveforms[0])
        let inputs = StemBandInputs(
            vocalsE: vocalsE,
            vocalsResult: vocalsResult,
            drumsE: drumsE,
            drumsResult: drumsResult,
            beatResult: beatResult,
            bassE: bassE,
            bassResult: bassResult,
            otherE: otherE,
            otherResult: otherResult
        )
        var features = buildBaseStemFeatures(inputs)
        features.vocalsEnergyRel = devs.vocalsRel; features.vocalsEnergyDev = max(0, devs.vocalsRel)
        features.drumsEnergyRel = devs.drumsRel; features.drumsEnergyDev = max(0, devs.drumsRel)
        features.bassEnergyRel = devs.bassRel; features.bassEnergyDev = max(0, devs.bassRel)
        features.otherEnergyRel = devs.otherRel; features.otherEnergyDev = max(0, devs.otherRel)
        applyRichMetadata(to: &features, vocals: richAll[0], drums: richAll[1], bass: richAll[2], other: richAll[3])
        features.vocalsPitchHz = pitchHz
        features.vocalsPitchConfidence = pitchConf
        return features
    }

    // MARK: - Deviation Primitives

    private struct StemDeviations {
        var vocalsRel: Float
        var drumsRel: Float
        var bassRel: Float
        var otherRel: Float
    }

    private func updateEMAsAndComputeDeviations(
        vocalsE: Float, drumsE: Float, bassE: Float, otherE: Float
    ) -> StemDeviations {
        let decay = Self.stemEMADecay
        stemRunningAvg[0] = stemRunningAvg[0] * decay + vocalsE * (1 - decay)
        stemRunningAvg[1] = stemRunningAvg[1] * decay + drumsE * (1 - decay)
        stemRunningAvg[2] = stemRunningAvg[2] * decay + bassE * (1 - decay)
        stemRunningAvg[3] = stemRunningAvg[3] * decay + otherE * (1 - decay)
        return StemDeviations(
            vocalsRel: (vocalsE - stemRunningAvg[0]) * 2.0,
            drumsRel: (drumsE - stemRunningAvg[1]) * 2.0,
            bassRel: (bassE - stemRunningAvg[2]) * 2.0,
            otherRel: (otherE - stemRunningAvg[3]) * 2.0
        )
    }

    // MARK: - Base Feature Builder

    private struct StemBandInputs {
        var vocalsE: Float
        var vocalsResult: BandEnergyProcessor.Result
        var drumsE: Float
        var drumsResult: BandEnergyProcessor.Result
        var beatResult: BeatDetector.Result
        var bassE: Float
        var bassResult: BandEnergyProcessor.Result
        var otherE: Float
        var otherResult: BandEnergyProcessor.Result
    }

    private func buildBaseStemFeatures(_ inp: StemBandInputs) -> StemFeatures {
        StemFeatures(
            vocalsEnergy: inp.vocalsE,
            vocalsBand0: inp.vocalsResult.midHigh,
            vocalsBand1: inp.vocalsResult.highMid,
            vocalsBeat: 0,
            drumsEnergy: inp.drumsE,
            drumsBand0: inp.drumsResult.subBass,
            drumsBand1: inp.drumsResult.midHigh,
            drumsBeat: inp.beatResult.beatBass,
            bassEnergy: inp.bassE,
            bassBand0: inp.bassResult.subBass,
            bassBand1: inp.bassResult.lowBass,
            bassBeat: 0,
            otherEnergy: inp.otherE,
            otherBand0: inp.otherResult.lowMid,
            otherBand1: inp.otherResult.highMid,
            otherBeat: 0
        )
    }

    private func applyRichMetadata(
        to features: inout StemFeatures,
        vocals: StemRichFeatures,
        drums: StemRichFeatures,
        bass: StemRichFeatures,
        other: StemRichFeatures
    ) {
        features.vocalsOnsetRate = vocals.onsetRate; features.vocalsCentroid = vocals.centroid
        features.vocalsAttackRatio = vocals.attackRatio; features.vocalsEnergySlope = vocals.energySlope
        features.drumsOnsetRate = drums.onsetRate;   features.drumsCentroid = drums.centroid
        features.drumsAttackRatio = drums.attackRatio; features.drumsEnergySlope = drums.energySlope
        features.bassOnsetRate = bass.onsetRate;     features.bassCentroid = bass.centroid
        features.bassAttackRatio = bass.attackRatio;   features.bassEnergySlope = bass.energySlope
        features.otherOnsetRate = other.onsetRate;   features.otherCentroid = other.centroid
        features.otherAttackRatio = other.attackRatio; features.otherEnergySlope = other.energySlope
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        for processor in energyProcessors {
            processor.reset()
        }
        drumsBeatDetector.reset()
        pitchTracker.reset()
        // Reset EMA state so deviation primitives don't carry over across tracks.
        stemRunningAvg = [0, 0, 0, 0]
        // Reset MV-3a rich state.
        richStates = [StemRichState(), StemRichState(), StemRichState(), StemRichState()]
        logger.info("StemAnalyzer reset")
    }

    // MARK: - Private Helpers

    /// Run energy analysis on a single stem's waveform.
    /// Returns both the band-energy result and the computed magnitude bins so
    /// callers can reuse them for MV-3a rich features without a second FFT pass.
    private func analyzeStem(
        _ waveform: [Float],
        processor: BandEnergyProcessor,
        fps: Float
    ) -> (result: BandEnergyProcessor.Result, magnitudes: [Float]) {
        let mags = computeMagnitudes(from: waveform)
        let result = processor.process(magnitudes: mags, fps: fps)
        return (result: result, magnitudes: mags)
    }
}
