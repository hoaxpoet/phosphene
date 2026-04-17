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
    private static let fftSize = 1024
    private static let binCount = fftSize / 2
    private static let log2n = vDSP_Length(log2(Double(fftSize)))

    // MARK: - MV-3a: Per-Stem Rich State

    /// Mutable per-call state for MV-3a rich metadata computation.
    /// One element per stem (index 0=vocals, 1=drums, 2=bass, 3=other).
    private struct StemRichState {
        // AttackRatio: EMA-based fast and slow RMS
        var fastRMS: Float = 1e-8     // ~50ms time constant
        var slowRMS: Float = 1e-8     // ~500ms time constant
        // EnergySlope: previous attenuated total energy
        var prevAttEnergy: Float = 0
        // OnsetRate: leaky integrator over ~0.5s
        var onsetAccum: Float = 0
        var prevRMS: Float = 0        // for flux detection
        var fluxEMA: Float = 1e-8     // adaptive threshold
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
    /// Decay ≈ 0.995 per frame (~2.1s time constant at 94 Hz).
    /// Formula: runningAvg = runningAvg * decay + energy * (1 - decay)
    /// Then: energyRel = (energy - runningAvg) * 2.0
    ///       energyDev = max(0, energyRel)
    private var stemRunningAvg: [Float] = [0, 0, 0, 0]
    private static let stemEMADecay: Float = 0.995

    // MARK: - MV-3a: Rich State

    private var richStates: [StemRichState] = [
        StemRichState(), StemRichState(), StemRichState(), StemRichState()
    ]
    private let sampleRate: Float
    private let nyquist: Float

    // MARK: - vDSP State (reused per call, no per-frame alloc)

    private let fftSetup: FFTSetup
    private var window: [Float]
    private var windowedSamples: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private var magnitudes: [Float]
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

        // Analyze each stem.
        let vocalsResult = analyzeStem(stemWaveforms[0], processor: energyProcessors[0], fps: fps)
        let drumsResult  = analyzeStem(stemWaveforms[1], processor: energyProcessors[1], fps: fps)
        let bassResult   = analyzeStem(stemWaveforms[2], processor: energyProcessors[2], fps: fps)
        let otherResult  = analyzeStem(stemWaveforms[3], processor: energyProcessors[3], fps: fps)

        // Beat detection on drums stem only.
        let drumsMags = computeMagnitudes(from: stemWaveforms[1])
        let beatResult = drumsBeatDetector.process(magnitudes: drumsMags, fps: fps, deltaTime: dt)

        // Compute total energy per stem (scalar used for StemFeatures.xEnergy).
        let vocalsE = vocalsResult.bass + vocalsResult.mid + vocalsResult.treble
        let drumsE  = drumsResult.bass  + drumsResult.mid  + drumsResult.treble
        let bassE   = bassResult.bass   + bassResult.mid   + bassResult.treble
        let otherE  = otherResult.bass  + otherResult.mid  + otherResult.treble

        // MV-1: Update per-stem EMA running averages and derive deviation primitives.
        let decay = Self.stemEMADecay
        stemRunningAvg[0] = stemRunningAvg[0] * decay + vocalsE * (1 - decay)
        stemRunningAvg[1] = stemRunningAvg[1] * decay + drumsE  * (1 - decay)
        stemRunningAvg[2] = stemRunningAvg[2] * decay + bassE   * (1 - decay)
        stemRunningAvg[3] = stemRunningAvg[3] * decay + otherE  * (1 - decay)

        let vRel = (vocalsE - stemRunningAvg[0]) * 2.0
        let dRel = (drumsE  - stemRunningAvg[1]) * 2.0
        let bRel = (bassE   - stemRunningAvg[2]) * 2.0
        let oRel = (otherE  - stemRunningAvg[3]) * 2.0

        // MV-3a: Compute rich per-stem metadata.
        // Pass the stem magnitudes and waveforms to the helper.
        let vocalsMags = computeMagnitudes(from: stemWaveforms[0])
        let bassMags   = computeMagnitudes(from: stemWaveforms[2])
        let otherMags  = computeMagnitudes(from: stemWaveforms[3])

        let vocalsRich = computeRichFeatures(
            index: 0, waveform: stemWaveforms[0], magnitudes: vocalsMags,
            attEnergy: (vocalsResult.bassAtt + vocalsResult.midAtt + vocalsResult.trebleAtt) / 3.0,
            dt: dt
        )
        let drumsRich = computeRichFeatures(
            index: 1, waveform: stemWaveforms[1], magnitudes: drumsMags,
            attEnergy: (drumsResult.bassAtt + drumsResult.midAtt + drumsResult.trebleAtt) / 3.0,
            dt: dt
        )
        let bassRich = computeRichFeatures(
            index: 2, waveform: stemWaveforms[2], magnitudes: bassMags,
            attEnergy: (bassResult.bassAtt + bassResult.midAtt + bassResult.trebleAtt) / 3.0,
            dt: dt
        )
        let otherRich = computeRichFeatures(
            index: 3, waveform: stemWaveforms[3], magnitudes: otherMags,
            attEnergy: (otherResult.bassAtt + otherResult.midAtt + otherResult.trebleAtt) / 3.0,
            dt: dt
        )

        // MV-3c: Vocal pitch via YIN.
        let (pitchHz, pitchConf) = pitchTracker.process(waveform: stemWaveforms[0])

        var features = StemFeatures(
            // Vocals: energy, presence (midHigh 1-4kHz), air (highMid 4-8kHz)
            vocalsEnergy: vocalsE,
            vocalsBand0: vocalsResult.midHigh,
            vocalsBand1: vocalsResult.highMid,
            vocalsBeat: 0,

            // Drums: energy, sub bass (kick), mid high (snare crack)
            drumsEnergy: drumsE,
            drumsBand0: drumsResult.subBass,
            drumsBand1: drumsResult.midHigh,
            drumsBeat: beatResult.beatBass,

            // Bass: energy, sub bass, low bass
            bassEnergy: bassE,
            bassBand0: bassResult.subBass,
            bassBand1: bassResult.lowBass,
            bassBeat: 0,

            // Other: energy, low mid, high mid
            otherEnergy: otherE,
            otherBand0: otherResult.lowMid,
            otherBand1: otherResult.highMid,
            otherBeat: 0
        )

        // MV-1 deviation fields.
        features.vocalsEnergyRel = vRel;  features.vocalsEnergyDev = max(0, vRel)
        features.drumsEnergyRel  = dRel;  features.drumsEnergyDev  = max(0, dRel)
        features.bassEnergyRel   = bRel;  features.bassEnergyDev   = max(0, bRel)
        features.otherEnergyRel  = oRel;  features.otherEnergyDev  = max(0, oRel)

        // MV-3a rich metadata fields.
        features.vocalsOnsetRate   = vocalsRich.onsetRate
        features.vocalsCentroid    = vocalsRich.centroid
        features.vocalsAttackRatio = vocalsRich.attackRatio
        features.vocalsEnergySlope = vocalsRich.energySlope

        features.drumsOnsetRate    = drumsRich.onsetRate
        features.drumsCentroid     = drumsRich.centroid
        features.drumsAttackRatio  = drumsRich.attackRatio
        features.drumsEnergySlope  = drumsRich.energySlope

        features.bassOnsetRate     = bassRich.onsetRate
        features.bassCentroid      = bassRich.centroid
        features.bassAttackRatio   = bassRich.attackRatio
        features.bassEnergySlope   = bassRich.energySlope

        features.otherOnsetRate    = otherRich.onsetRate
        features.otherCentroid     = otherRich.centroid
        features.otherAttackRatio  = otherRich.attackRatio
        features.otherEnergySlope  = otherRich.energySlope

        // MV-3c pitch fields.
        features.vocalsPitchHz          = pitchHz
        features.vocalsPitchConfidence  = pitchConf

        return features
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
    private func analyzeStem(
        _ waveform: [Float],
        processor: BandEnergyProcessor,
        fps: Float
    ) -> BandEnergyProcessor.Result {
        let mags = computeMagnitudes(from: waveform)
        return processor.process(magnitudes: mags, fps: fps)
    }

    // MARK: - MV-3a Rich Metadata

    /// Compute onset rate, spectral centroid, attack ratio, and energy slope for one stem.
    ///
    /// - Parameters:
    ///   - index: Stem index (0=vocals, 1=drums, 2=bass, 3=other) for richStates access.
    ///   - waveform: Raw PCM samples from the stem.
    ///   - magnitudes: Pre-computed FFT magnitude bins (512 floats).
    ///   - attEnergy: Attenuated total energy (average of bassAtt, midAtt, trebleAtt).
    ///   - dt: Frame delta time in seconds.
    private func computeRichFeatures(
        index: Int,
        waveform: [Float],
        magnitudes: [Float],
        attEnergy: Float,
        dt: Float
    ) -> (onsetRate: Float, centroid: Float, attackRatio: Float, energySlope: Float) {

        // ── Spectral centroid (0–1 normalized by Nyquist) ────────────────────
        var centroid: Float = 0
        if !magnitudes.isEmpty {
            let binResolution = sampleRate / Float(Self.fftSize)
            var weightedSum: Float = 0
            var totalMag: Float = 0
            for (i, mag) in magnitudes.enumerated() {
                let freq = Float(i) * binResolution
                weightedSum += freq * mag
                totalMag += mag
            }
            centroid = totalMag > 1e-10 ? (weightedSum / totalMag) / nyquist : 0
        }

        // ── RMS of the current waveform window ───────────────────────────────
        var currentRMS: Float = 0
        if !waveform.isEmpty {
            var sumSq: Float = 0
            vDSP_svesq(waveform, 1, &sumSq, vDSP_Length(waveform.count))
            currentRMS = sqrt(sumSq / Float(waveform.count))
        }

        // ── Attack ratio: fastRMS / slowRMS (clamped 0–3) ────────────────────
        // FPS-independent EMA decay: exp(-dt / τ)
        let fastDecay = exp(-dt / 0.050)   // τ = 50ms
        let slowDecay = exp(-dt / 0.500)   // τ = 500ms
        richStates[index].fastRMS = richStates[index].fastRMS * fastDecay
                                  + currentRMS * (1 - fastDecay)
        richStates[index].slowRMS = richStates[index].slowRMS * slowDecay
                                  + currentRMS * (1 - slowDecay)
        let attackRatio = min(3.0, richStates[index].fastRMS
                                  / max(richStates[index].slowRMS, 1e-8))

        // ── Energy slope (attenuated, FPS-independent derivative) ────────────
        let energySlope = dt > 0
            ? (attEnergy - richStates[index].prevAttEnergy) / dt
            : 0
        richStates[index].prevAttEnergy = attEnergy

        // ── Onset rate: leaky integrator over ~0.5s ───────────────────────────
        // Flux: half-wave rectified change in RMS.
        let flux = max(0, currentRMS - richStates[index].prevRMS)
        richStates[index].prevRMS = currentRMS
        // Adaptive threshold: EMA of recent flux × 1.5.
        richStates[index].fluxEMA = richStates[index].fluxEMA * 0.9 + flux * 0.1
        let fluxThreshold = richStates[index].fluxEMA * 1.5
        if flux > fluxThreshold && flux > 1e-6 {
            richStates[index].onsetAccum += 1.0
        }
        // Decay the accumulator with a 0.5s window time constant.
        let windowDecay = exp(-dt / 0.5)
        richStates[index].onsetAccum *= windowDecay
        // Rate = accumulated count / window length (0.5s).
        let onsetRate = richStates[index].onsetAccum * 2.0

        return (onsetRate: onsetRate, centroid: centroid,
                attackRatio: attackRatio, energySlope: energySlope)
    }

    /// Compute FFT magnitudes from a mono waveform.
    /// Uses the last `fftSize` samples. Returns 512 magnitude bins.
    private func computeMagnitudes(from waveform: [Float]) -> [Float] {
        let sampleCount = waveform.count
        guard sampleCount > 0 else {
            // Return zeros — analyzers handle gracefully.
            magnitudes.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                base.initialize(repeating: 0, count: Self.binCount)
            }
            return magnitudes
        }

        // Take the last fftSize samples (or zero-pad if shorter).
        let offset = max(0, sampleCount - Self.fftSize)
        let available = min(Self.fftSize, sampleCount)

        // Zero the windowed buffer, then copy available samples.
        windowedSamples.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.initialize(repeating: 0, count: Self.fftSize)
        }
        waveform.withUnsafeBufferPointer { src in
            windowedSamples.withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return }
                let copyStart = Self.fftSize - available
                dstBase.advanced(by: copyStart).update(
                    from: srcBase.advanced(by: offset),
                    count: available
                )
            }
        }

        // Apply Hann window.
        vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(Self.fftSize))

        // Convert to split complex, run FFT, compute magnitudes — all within
        // withUnsafeMutableBufferPointer to satisfy Swift 6 pointer safety.
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress, let imagBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)

                // Interleaved → split complex.
                windowedSamples.withUnsafeBufferPointer { input in
                    guard let inputBase = input.baseAddress else { return }
                    inputBase.withMemoryRebound(
                        to: DSPComplex.self, capacity: Self.binCount
                    ) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.binCount))
                    }
                }

                // Forward FFT.
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(kFFTDirection_Forward))

                // Squared magnitudes → magnitudes buffer.
                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    guard let magBase = magBuf.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magBase, 1, vDSP_Length(Self.binCount))
                }
            }
        }

        // Scale (divide by fftSize).
        var scale = Float(Self.fftSize)
        vDSP_vsdiv(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(Self.binCount))

        // Square root for magnitude (zvmags gives squared magnitude).
        var count = Int32(Self.binCount)
        vvsqrtf(&magnitudes, magnitudes, &count)

        return magnitudes
    }
}
