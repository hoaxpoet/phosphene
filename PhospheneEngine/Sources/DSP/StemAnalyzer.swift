// StemAnalyzer — Per-stem energy and beat analysis for the live stem pipeline.
// Holds 4× BandEnergyProcessor (one per stem) + 1× BeatDetector on drums.
// Takes mono waveform samples from stem separation, runs a lightweight FFT
// to get magnitudes, then feeds them to existing DSP primitives.

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

    // MARK: - DSP Primitives

    /// Per-stem energy processors: [vocals, drums, bass, other].
    private let energyProcessors: [BandEnergyProcessor]

    /// Beat detector on the drums stem only.
    private let drumsBeatDetector: BeatDetector

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
        // 4 independent energy processors — one per stem.
        self.energyProcessors = (0..<4).map { _ in
            BandEnergyProcessor(binCount: Self.binCount, sampleRate: sampleRate, fftSize: Self.fftSize)
        }
        self.drumsBeatDetector = BeatDetector(
            binCount: Self.binCount, sampleRate: sampleRate, fftSize: Self.fftSize
        )

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

        logger.info("StemAnalyzer initialized (4 energy + 1 beat detector)")
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

        let dt = fps > 0 ? 1.0 / fps : 0.016

        // Analyze each stem.
        let vocalsEnergy = analyzeStem(stemWaveforms[0], processor: energyProcessors[0], fps: fps)
        let drumsEnergy = analyzeStem(stemWaveforms[1], processor: energyProcessors[1], fps: fps)
        let bassEnergy = analyzeStem(stemWaveforms[2], processor: energyProcessors[2], fps: fps)
        let otherEnergy = analyzeStem(stemWaveforms[3], processor: energyProcessors[3], fps: fps)

        // Beat detection on drums stem only.
        let drumsMags = computeMagnitudes(from: stemWaveforms[1])
        let beatResult = drumsBeatDetector.process(magnitudes: drumsMags, fps: fps, deltaTime: dt)

        return StemFeatures(
            // Vocals: energy, presence (midHigh 1-4kHz), air (highMid 4-8kHz)
            vocalsEnergy: vocalsEnergy.bass + vocalsEnergy.mid + vocalsEnergy.treble,
            vocalsBand0: vocalsEnergy.midHigh,
            vocalsBand1: vocalsEnergy.highMid,
            vocalsBeat: 0,

            // Drums: energy, sub bass (kick), mid high (snare crack)
            drumsEnergy: drumsEnergy.bass + drumsEnergy.mid + drumsEnergy.treble,
            drumsBand0: drumsEnergy.subBass,
            drumsBand1: drumsEnergy.midHigh,
            drumsBeat: beatResult.beatBass,

            // Bass: energy, sub bass, low bass
            bassEnergy: bassEnergy.bass + bassEnergy.mid + bassEnergy.treble,
            bassBand0: bassEnergy.subBass,
            bassBand1: bassEnergy.lowBass,
            bassBeat: 0,

            // Other: energy, low mid, high mid
            otherEnergy: otherEnergy.bass + otherEnergy.mid + otherEnergy.treble,
            otherBand0: otherEnergy.lowMid,
            otherBand1: otherEnergy.highMid,
            otherBeat: 0
        )
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        for processor in energyProcessors {
            processor.reset()
        }
        drumsBeatDetector.reset()
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

    /// Compute FFT magnitudes from a mono waveform.
    /// Uses the last `fftSize` samples. Returns 512 magnitude bins.
    private func computeMagnitudes(from waveform: [Float]) -> [Float] {
        let sampleCount = waveform.count
        guard sampleCount > 0 else {
            // Return zeros — analyzers handle gracefully.
            magnitudes.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.initialize(repeating: 0, count: Self.binCount)
            }
            return magnitudes
        }

        // Take the last fftSize samples (or zero-pad if shorter).
        let offset = max(0, sampleCount - Self.fftSize)
        let available = min(Self.fftSize, sampleCount)

        // Zero the windowed buffer, then copy available samples.
        windowedSamples.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.initialize(repeating: 0, count: Self.fftSize)
        }
        waveform.withUnsafeBufferPointer { src in
            windowedSamples.withUnsafeMutableBufferPointer { dst in
                let copyStart = Self.fftSize - available
                dst.baseAddress!.advanced(by: copyStart).update(
                    from: src.baseAddress!.advanced(by: offset),
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
                var split = DSPSplitComplex(realp: realBuf.baseAddress!,
                                            imagp: imagBuf.baseAddress!)

                // Interleaved → split complex.
                windowedSamples.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self, capacity: Self.binCount
                    ) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.binCount))
                    }
                }

                // Forward FFT.
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n,
                              FFTDirection(kFFTDirection_Forward))

                // Squared magnitudes → magnitudes buffer.
                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    vDSP_zvmags(&split, 1, magBuf.baseAddress!, 1,
                                vDSP_Length(Self.binCount))
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
