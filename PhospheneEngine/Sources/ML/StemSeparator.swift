// StemSeparator — MPSGraph-powered audio stem separation using Open-Unmix HQ.
// Accepts interleaved PCM audio, performs STFT via the GPU-accelerated
// `StemFFTEngine`, runs MPSGraph mask estimation via `StemModelEngine`, applies
// masks and iSTFT to produce four separated stem waveforms (vocals, drums,
// bass, other) in UMA buffers.
//
// STFT/iSTFT is handled outside the neural network because CoreML has no
// complex number support. The model operates on magnitude spectrograms only;
// phase is preserved from the original STFT and reapplied during iSTFT
// reconstruction. As of Increment 3.1a the transforms run on the GPU via
// MPSGraph (see `StemFFT.swift`); the legacy Accelerate/vDSP path is
// preserved inside `StemFFTEngine` behind `forceCPUFallback` for
// cross-validation testing.
//
// As of Increment 3.9 the neural network prediction uses `StemModelEngine`
// (MPSGraph, Float32 on GPU) instead of CoreML on the ANE. This eliminates
// the ANE Float16→Float32 conversion bottleneck (~420ms) and the
// MLMultiArray pack/unpack overhead.
//
// All heavy allocations happen at init time. Per-call allocations are limited
// to [Float] arrays for STFT intermediates.

import Foundation
import Metal
import Accelerate
import Shared
import Audio
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "StemSeparator")

// MARK: - StemSeparator

/// Separates mixed audio into four stems using MPSGraph on the GPU.
///
/// Pipeline per call:
/// 1. Resample to 44100 Hz if needed (model's native rate)
/// 2. Deinterleave stereo → two mono channels
/// 3. STFT each channel → magnitude + phase spectrograms
/// 4. MPSGraph prediction: magnitude → 4 filtered magnitude spectrograms
/// 5. iSTFT: filtered magnitude × original phase → 4 stem waveforms
/// 6. Write each stem into its own UMABuffer<Float>
public final class StemSeparator: StemSeparating, @unchecked Sendable {

    // MARK: - Constants

    /// STFT parameters matching the Open-Unmix HQ model.
    public static let nFFT = 4096
    public static let hopLength = 1024
    public static let nBins = nFFT / 2 + 1  // 2049
    public static let modelSampleRate: Float = 44100

    /// Number of output stems.
    public static let stemCount = 4

    /// Fixed number of STFT frames the model expects.
    /// Computed as: (modelSampleRate * durationSeconds) / hopLength + 1
    /// where durationSeconds = 10 (the conversion default).
    public static let modelFrameCount = 431

    /// Number of mono samples needed to produce exactly modelFrameCount STFT frames.
    /// With center=True padding: numSamples = (modelFrameCount - 1) * hopLength.
    public static let requiredMonoSamples = (modelFrameCount - 1) * hopLength  // 440320

    // MARK: - Model

    /// MPSGraph-based Open-Unmix HQ inference engine (Increment 3.8+3.9).
    private let stemModel: StemModelEngine

    // MARK: - Output

    /// Ordered stem labels.
    public let stemLabels: [String] = ["vocals", "drums", "bass", "other"]

    /// Four UMA output buffers, one per stem. Each holds mono waveform samples.
    public let stemBuffers: [UMABuffer<Float>]

    /// Default output buffer capacity (enough for ~10s at 44100 Hz).
    private static let defaultBufferCapacity = 441_000

    // MARK: - STFT Engine

    /// GPU-accelerated STFT/iSTFT engine (Increment 3.1a). Replaces the
    /// original CPU-based Accelerate path. The engine keeps a CPU vDSP
    /// fallback behind `forceCPUFallback` for cross-validation testing.
    private let fftEngine: StemFFTEngine

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a stem separator backed by the Open-Unmix HQ MPSGraph model.
    ///
    /// - Parameter device: Metal device for UMA buffer allocation and GPU inference.
    /// - Throws: `StemSeparationError` if model or engine initialization fails.
    public init(device: MTLDevice) throws {
        // Load MPSGraph stem model (weights from .bin files, ~136 MB).
        do {
            self.stemModel = try StemModelEngine(device: device)
        } catch {
            throw StemSeparationError.modelLoadFailed(error.localizedDescription)
        }

        // Allocate output buffers.
        var buffers = [UMABuffer<Float>]()
        for _ in 0..<Self.stemCount {
            buffers.append(try UMABuffer<Float>(device: device, capacity: Self.defaultBufferCapacity))
        }
        self.stemBuffers = buffers

        // GPU-accelerated STFT/iSTFT engine (MPSGraph + vDSP fallback).
        do {
            self.fftEngine = try StemFFTEngine(device: device)
        } catch {
            throw StemSeparationError.modelLoadFailed("Failed to initialize StemFFTEngine: \(error)")
        }

        logger.info("StemSeparator loaded: MPSGraph engine, \(Self.nFFT)-pt STFT, \(Self.nBins) bins")
    }

    // MARK: - Separation

    /// Separate audio into four stems.
    ///
    /// Input audio is padded or truncated to the model's fixed window size
    /// (~10s at 44100 Hz). Shorter inputs are zero-padded; longer inputs
    /// use the first `requiredMonoSamples` per channel.
    ///
    /// - Parameters:
    ///   - audio: Interleaved float32 PCM samples.
    ///   - channelCount: 1 (mono) or 2 (stereo).
    ///   - sampleRate: Input sample rate in Hz.
    /// - Returns: Separation result with per-stem metadata.
    public func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let monoFrames = audio.count / max(channelCount, 1)
        guard monoFrames >= Self.hopLength else {
            throw StemSeparationError.insufficientSamples(audio.count)
        }

        // Step 1: Resample to model rate if needed.
        let resampled: [Float]
        if abs(sampleRate - Self.modelSampleRate) > 1.0 {
            resampled = resample(audio, from: sampleRate, to: Self.modelSampleRate, channelCount: channelCount)
        } else {
            resampled = audio
        }

        // Step 2: Deinterleave to mono channels.
        let (leftRaw, rightRaw) = deinterleave(resampled, channelCount: channelCount)

        // Step 3: Pad or truncate to exactly requiredMonoSamples.
        let left = padOrTruncate(leftRaw, to: Self.requiredMonoSamples)
        let right = padOrTruncate(rightRaw, to: Self.requiredMonoSamples)

        // Step 4: STFT both channels (center-padded to produce modelFrameCount frames).
        let (magL, phaseL) = stft(mono: left)
        let (magR, phaseR) = stft(mono: right)

        let nbFrames = magL.count / Self.nBins

        // Step 5: Write magnitudes into StemModelEngine input buffers and predict.
        let elemCount = nbFrames * Self.nBins
        let byteCount = elemCount * MemoryLayout<Float>.size

        magL.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            memcpy(stemModel.inputMagLBuffer.contents(), srcBase, byteCount)
        }
        magR.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            memcpy(stemModel.inputMagRBuffer.contents(), srcBase, byteCount)
        }

        do {
            try stemModel.predict()
        } catch {
            throw StemSeparationError.predictionFailed(error.localizedDescription)
        }

        // Step 6: Read output magnitudes and reconstruct stem waveforms via iSTFT.
        let outputFrames = nbFrames
        var allStemMagL = [[Float]]()
        var allStemMagR = [[Float]]()
        allStemMagL.reserveCapacity(Self.stemCount)
        allStemMagR.reserveCapacity(Self.stemCount)

        for stem in 0..<Self.stemCount {
            let bufL = stemModel.outputBuffers[stem].magL
            let bufR = stemModel.outputBuffers[stem].magR
            let outL = bufL.contents().assumingMemoryBound(to: Float.self)
            let outR = bufR.contents().assumingMemoryBound(to: Float.self)

            allStemMagL.append(Array(UnsafeBufferPointer(start: outL, count: elemCount)))
            allStemMagR.append(Array(UnsafeBufferPointer(start: outR, count: elemCount)))
        }

        let stemWaveforms = reconstructStemWaveforms(
            allStemMagL: allStemMagL,
            allStemMagR: allStemMagR,
            phaseL: phaseL,
            phaseR: phaseR,
            nbFrames: outputFrames
        )

        // Step 7: Write to UMA output buffers.
        let monoSampleCount = stemWaveforms[0].count
        writeToBuffers(stemWaveforms, sampleCount: monoSampleCount)

        let result = buildResult(sampleCount: monoSampleCount)
        logger.debug("Separated \(audio.count) samples → \(monoSampleCount) samples/stem (\(nbFrames) STFT frames)")
        return result
    }

    /// Write stem waveforms into the pre-allocated UMA output buffers.
    private func writeToBuffers(_ waveforms: [[Float]], sampleCount: Int) {
        lock.lock()
        for i in 0..<Self.stemCount {
            let writeCount = min(sampleCount, stemBuffers[i].capacity)
            if writeCount == waveforms[i].count {
                stemBuffers[i].write(waveforms[i])
            } else {
                stemBuffers[i].write(Array(waveforms[i].prefix(writeCount)))
            }
        }
        lock.unlock()
    }

    /// Build a StemSeparationResult from the given sample count.
    private func buildResult(sampleCount: Int) -> StemSeparationResult {
        let frame = AudioFrame(
            sampleRate: Self.modelSampleRate,
            sampleCount: UInt32(sampleCount),
            channelCount: 1
        )
        let stemData = StemData(vocals: frame, drums: frame, bass: frame, other: frame)
        return StemSeparationResult(stemData: stemData, sampleCount: sampleCount)
    }

    // MARK: - STFT

    /// Compute Short-Time Fourier Transform on mono audio with center padding.
    ///
    /// Matches PyTorch's `torch.stft(center=True)`: input is zero-padded by
    /// nFFT/2 on each side, giving `nb_frames = num_samples // hop_length + 1`.
    ///
    /// Delegates to ``StemFFTEngine``, which routes to the GPU MPSGraph path
    /// when the frame count matches `modelFrameCount` and falls back to the
    /// preserved vDSP CPU path otherwise.
    ///
    /// - Parameter mono: Mono float32 samples.
    /// - Returns: Tuple of (magnitude, phase) arrays, each of length nBins * nbFrames.
    func stft(mono: [Float]) -> (magnitude: [Float], phase: [Float]) {
        return fftEngine.forward(mono: mono)
    }

    // MARK: - iSTFT

    /// Inverse STFT: reconstruct time-domain signal from magnitude and phase.
    ///
    /// Uses overlap-add with the same Hann window for synthesis.
    /// When `originalLength` is provided, strips center padding to return
    /// a waveform matching the original (pre-padded) length.
    ///
    /// Delegates to ``StemFFTEngine``.
    ///
    /// - Parameters:
    ///   - magnitude: Magnitude spectrogram (nBins * nbFrames).
    ///   - phase: Phase spectrogram (nBins * nbFrames).
    ///   - nbFrames: Number of STFT frames.
    ///   - originalLength: If provided, trim center padding to this length.
    /// - Returns: Reconstructed mono waveform.
    func istft(
        magnitude: [Float],
        phase: [Float],
        nbFrames: Int,
        originalLength: Int? = nil
    ) -> [Float] {
        return fftEngine.inverse(
            magnitude: magnitude,
            phase: phase,
            nbFrames: nbFrames,
            originalLength: originalLength
        )
    }

    // MARK: - Resampling

    /// Resample audio from one sample rate to another via linear interpolation.
    ///
    /// - Parameters:
    ///   - audio: Input samples (interleaved if multi-channel).
    ///   - fromRate: Source sample rate.
    ///   - toRate: Target sample rate.
    ///   - channelCount: Number of interleaved channels.
    /// - Returns: Resampled audio.
    private func resample(
        _ audio: [Float], from fromRate: Float, to toRate: Float, channelCount: Int
    ) -> [Float] {
        let ratio = toRate / fromRate
        let inputFrames = audio.count / channelCount
        let outputFrames = Int(Float(inputFrames) * ratio)
        let outputCount = outputFrames * channelCount

        var output = [Float](repeating: 0, count: outputCount)

        // Linear interpolation resampling per channel.
        for ch in 0..<channelCount {
            for outFrame in 0..<outputFrames {
                let srcPosition = Float(outFrame) / ratio
                let srcIdx = Int(srcPosition)
                let frac = srcPosition - Float(srcIdx)

                let idx0 = min(srcIdx, inputFrames - 1) * channelCount + ch
                let idx1 = min(srcIdx + 1, inputFrames - 1) * channelCount + ch
                let outIdx = outFrame * channelCount + ch

                output[outIdx] = audio[idx0] * (1.0 - frac) + audio[idx1] * frac
            }
        }

        return output
    }

    // MARK: - Padding

    /// Pad with zeros or truncate an array to exactly `targetCount` elements.
    private func padOrTruncate(_ input: [Float], to targetCount: Int) -> [Float] {
        if input.count == targetCount {
            return input
        } else if input.count > targetCount {
            return Array(input.prefix(targetCount))
        } else {
            var result = input
            result.append(contentsOf: [Float](repeating: 0, count: targetCount - input.count))
            return result
        }
    }

    // MARK: - Deinterleave

    /// Split interleaved stereo into two mono arrays.
    ///
    /// Uses `vDSP_ctoz` to deinterleave LRLRLR → separate L and R arrays
    /// in a single vectorized call.
    /// For mono input, returns the same array as both channels.
    private func deinterleave(_ audio: [Float], channelCount: Int) -> (left: [Float], right: [Float]) {
        guard channelCount >= 2 else {
            return (audio, audio)
        }

        let frameCount = audio.count / channelCount
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)

        // vDSP_ctoz interprets interleaved pairs as DSPSplitComplex (real=L, imag=R).
        audio.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            srcBase.withMemoryRebound(to: DSPComplex.self, capacity: frameCount) { complex in
                left.withUnsafeMutableBufferPointer { leftBuf in
                    right.withUnsafeMutableBufferPointer { rightBuf in
                        guard let lPtr = leftBuf.baseAddress,
                              let rPtr = rightBuf.baseAddress else { return }
                        var split = DSPSplitComplex(realp: lPtr, imagp: rPtr)
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(frameCount))
                    }
                }
            }
        }

        return (left, right)
    }
}
