// StemSeparator — CoreML-powered audio stem separation using Open-Unmix HQ.
// Accepts interleaved PCM audio, performs STFT via Accelerate, runs CoreML
// mask estimation on the ANE, applies masks and iSTFT to produce four
// separated stem waveforms (vocals, drums, bass, other) in UMA buffers.
//
// STFT/iSTFT is handled in Swift because CoreML has no complex number support.
// The model operates on magnitude spectrograms only; phase is preserved from
// the original STFT and reapplied during iSTFT reconstruction.
//
// All heavy allocations happen at init time. Per-call allocations are limited
// to MLShapedArray creation (CoreML requirement).
//
// MLShapedArray is used instead of raw MLMultiArray pointer access because
// ANE output buffers have padded strides with unmapped memory in the padding
// regions. MLShapedArray.withUnsafeShapedBufferPointer handles these strides
// correctly. A future optimization (GPU STFT/iSTFT via Metal compute shaders)
// would eliminate the CPU-side extraction entirely.

import Foundation
import Metal
import CoreML
import Accelerate
import Shared
import Audio
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "StemSeparator")

// MARK: - StemSeparator

/// Separates mixed audio into four stems using CoreML and the Neural Engine.
///
/// Pipeline per call:
/// 1. Resample to 44100 Hz if needed (model's native rate)
/// 2. Deinterleave stereo → two mono channels
/// 3. STFT each channel → magnitude + phase spectrograms
/// 4. CoreML prediction: magnitude → 4 filtered magnitude spectrograms
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

    /// The loaded CoreML model.
    private let model: MLModel

    /// The compute unit configuration used to load the model.
    public let computeUnits: MLComputeUnits

    // MARK: - Output

    /// Ordered stem labels.
    public let stemLabels: [String] = ["vocals", "drums", "bass", "other"]

    /// Four UMA output buffers, one per stem. Each holds mono waveform samples.
    public let stemBuffers: [UMABuffer<Float>]

    /// Default output buffer capacity (enough for ~10s at 44100 Hz).
    private static let defaultBufferCapacity = 441_000

    // MARK: - Pre-allocated STFT Buffers

    /// Hann window for STFT.
    private let window: [Float]

    /// vDSP FFT setup for nFFT-point transforms.
    private let fftSetup: FFTSetup

    /// Log2 of nFFT for vDSP.
    private static let log2n = vDSP_Length(log2(Double(nFFT)))

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create a stem separator backed by the Open-Unmix HQ CoreML model.
    ///
    /// - Parameter device: Metal device for UMA buffer allocation.
    /// - Throws: `StemSeparationError` if model loading fails.
    public init(device: MTLDevice) throws {
        // Load model from bundle.
        guard let modelURL = Bundle.module.url(
            forResource: "StemSeparator",
            withExtension: "mlpackage",
            subdirectory: "Models"
        ) else {
            throw StemSeparationError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        self.computeUnits = config.computeUnits

        do {
            self.model = try MLModel(contentsOf: MLModel.compileModel(at: modelURL), configuration: config)
        } catch {
            throw StemSeparationError.modelLoadFailed(error.localizedDescription)
        }

        // Allocate output buffers.
        var buffers = [UMABuffer<Float>]()
        for _ in 0..<Self.stemCount {
            buffers.append(try UMABuffer<Float>(device: device, capacity: Self.defaultBufferCapacity))
        }
        self.stemBuffers = buffers

        // Create Hann window.
        var win = [Float](repeating: 0, count: Self.nFFT)
        vDSP_hann_window(&win, vDSP_Length(Self.nFFT), Int32(vDSP_HANN_NORM))
        self.window = win

        // Create FFT setup.
        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else {
            throw StemSeparationError.modelLoadFailed("Failed to create vDSP FFT setup")
        }
        self.fftSetup = setup

        logger.info("StemSeparator loaded: \(Self.nFFT)-point STFT, \(Self.nBins) bins, ANE inference")
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
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

        // Step 4: Pack into MLMultiArray [1, 2, 2049, nb_frames] and predict.
        let inputArray = try packSpectrogramForModel(magL: magL, magR: magR, nbFrames: nbFrames)

        let inputFeatures = try MLDictionaryFeatureProvider(
            dictionary: ["spectrogram": MLFeatureValue(multiArray: inputArray)]
        )

        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: inputFeatures)
        } catch {
            throw StemSeparationError.predictionFailed(error.localizedDescription)
        }

        // Step 5: Unpack output [4, 2, 2049, nb_frames] → 4 pairs of magnitude spectrograms.
        guard let outputArray = prediction.featureValue(for: "stems")?.multiArrayValue else {
            throw StemSeparationError.predictionFailed("Missing output feature")
        }

        guard outputArray.shape.count == 4 else {
            throw StemSeparationError.predictionFailed(
                "Unexpected output shape: \(outputArray.shape)")
        }

        // Step 6: iSTFT each stem and write to UMA buffers.
        let stemWaveforms = try unpackAndISTFT(
            output: outputArray,
            phaseL: phaseL,
            phaseR: phaseR,
            nbFrames: outputArray.shape[3].intValue
        )

        let monoSampleCount = stemWaveforms[0].count
        lock.lock()
        for i in 0..<Self.stemCount {
            let writeCount = min(monoSampleCount, stemBuffers[i].capacity)
            stemBuffers[i].write(Array(stemWaveforms[i].prefix(writeCount)))
        }
        lock.unlock()

        // Build StemData metadata.
        let stemData = StemData(
            vocals: AudioFrame(sampleRate: Self.modelSampleRate,
                               sampleCount: UInt32(monoSampleCount), channelCount: 1),
            drums: AudioFrame(sampleRate: Self.modelSampleRate,
                              sampleCount: UInt32(monoSampleCount), channelCount: 1),
            bass: AudioFrame(sampleRate: Self.modelSampleRate,
                             sampleCount: UInt32(monoSampleCount), channelCount: 1),
            other: AudioFrame(sampleRate: Self.modelSampleRate,
                              sampleCount: UInt32(monoSampleCount), channelCount: 1)
        )

        logger.debug("Separated \(audio.count) samples → \(monoSampleCount) samples/stem (\(nbFrames) STFT frames)")

        return StemSeparationResult(stemData: stemData, sampleCount: monoSampleCount)
    }

    // MARK: - STFT

    /// Compute Short-Time Fourier Transform on mono audio with center padding.
    ///
    /// Matches PyTorch's `torch.stft(center=True)`: input is zero-padded by
    /// nFFT/2 on each side, giving `nb_frames = num_samples // hop_length + 1`.
    ///
    /// - Parameter mono: Mono float32 samples.
    /// - Returns: Tuple of (magnitude, phase) arrays, each of length nBins * nbFrames.
    private func stft(mono: [Float]) -> (magnitude: [Float], phase: [Float]) {
        // Center padding: pad by nFFT/2 on each side.
        let pad = Self.nFFT / 2
        var padded = [Float](repeating: 0, count: mono.count + 2 * pad)
        for i in 0..<mono.count {
            padded[pad + i] = mono[i]
        }

        let sampleCount = padded.count
        let nbFrames = (sampleCount - Self.nFFT) / Self.hopLength + 1
        let totalBins = Self.nBins * nbFrames

        var magnitude = [Float](repeating: 0, count: totalBins)
        var phase = [Float](repeating: 0, count: totalBins)

        let halfN = Self.nFFT / 2

        // Pre-allocate per-frame working buffers.
        var windowedFrame = [Float](repeating: 0, count: Self.nFFT)
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        for frame in 0..<nbFrames {
            let offset = frame * Self.hopLength

            // Extract and window the frame.
            for i in 0..<Self.nFFT {
                windowedFrame[i] = padded[offset + i] * window[i]
            }

            // Forward FFT.
            windowedFrame.withUnsafeBufferPointer { srcPtr in
                realPart.withUnsafeMutableBufferPointer { realPtr in
                    imagPart.withUnsafeMutableBufferPointer { imagPtr in
                        // swiftlint:disable force_unwrapping
                        var splitComplex = DSPSplitComplex(
                            realp: realPtr.baseAddress!,
                            imagp: imagPtr.baseAddress!
                        )
                        srcPtr.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self, capacity: halfN
                        ) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                        }
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                        // swiftlint:enable force_unwrapping
                    }
                }
            }

            // Extract magnitude and phase for nBins frequencies.
            // Bin 0 (DC) and bin halfN (Nyquist) are packed in realPart[0] and imagPart[0].
            let binOffset = frame * Self.nBins

            // DC component (bin 0).
            magnitude[binOffset] = abs(realPart[0]) / Float(Self.nFFT)
            phase[binOffset] = realPart[0] >= 0 ? 0 : .pi

            // Regular bins 1..<halfN.
            for bin in 1..<halfN {
                let re = realPart[bin]
                let im = imagPart[bin]
                magnitude[binOffset + bin] = sqrtf(re * re + im * im) / Float(Self.nFFT)
                phase[binOffset + bin] = atan2f(im, re)
            }

            // Nyquist (bin halfN = nBins - 1).
            magnitude[binOffset + halfN] = abs(imagPart[0]) / Float(Self.nFFT)
            phase[binOffset + halfN] = imagPart[0] >= 0 ? 0 : .pi
        }

        return (magnitude, phase)
    }

    // MARK: - iSTFT

    /// Inverse STFT: reconstruct time-domain signal from magnitude and phase.
    ///
    /// Uses overlap-add with the same Hann window for synthesis.
    /// When `originalLength` is provided, strips center padding to return
    /// a waveform matching the original (pre-padded) length.
    ///
    /// - Parameters:
    ///   - magnitude: Magnitude spectrogram (nBins * nbFrames).
    ///   - phase: Phase spectrogram (nBins * nbFrames).
    ///   - nbFrames: Number of STFT frames.
    ///   - originalLength: If provided, trim center padding to this length.
    /// - Returns: Reconstructed mono waveform.
    private func istft(magnitude: [Float], phase: [Float], nbFrames: Int,
                       originalLength: Int? = nil) -> [Float] {
        let outputLength = (nbFrames - 1) * Self.hopLength + Self.nFFT
        var output = [Float](repeating: 0, count: outputLength)
        var windowSum = [Float](repeating: 0, count: outputLength)

        let halfN = Self.nFFT / 2

        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var timeFrame = [Float](repeating: 0, count: Self.nFFT)

        for frame in 0..<nbFrames {
            let binOffset = frame * Self.nBins

            // Reconstruct split complex from magnitude and phase.
            // DC (bin 0): pack into realPart[0].
            realPart[0] = magnitude[binOffset] * cosf(phase[binOffset]) * Float(Self.nFFT)

            // Nyquist (bin halfN): pack into imagPart[0].
            imagPart[0] = magnitude[binOffset + halfN] * cosf(phase[binOffset + halfN]) * Float(Self.nFFT)

            // Regular bins.
            for bin in 1..<halfN {
                let mag = magnitude[binOffset + bin] * Float(Self.nFFT)
                let ph = phase[binOffset + bin]
                realPart[bin] = mag * cosf(ph)
                imagPart[bin] = mag * sinf(ph)
            }

            // Inverse FFT.
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    // swiftlint:disable force_unwrapping
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, Self.log2n, FFTDirection(FFT_INVERSE))

                    // Convert back to interleaved.
                    timeFrame.withUnsafeMutableBufferPointer { dstPtr in
                        dstPtr.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self, capacity: halfN
                        ) { complexPtr in
                            vDSP_ztoc(&splitComplex, 1, complexPtr, 2, vDSP_Length(halfN))
                        }
                    }
                    // swiftlint:enable force_unwrapping
                }
            }

            // Scale by 1/(2*nFFT) — vDSP's inverse FFT includes a factor of 2.
            var scale = 1.0 / Float(2 * Self.nFFT)
            vDSP_vsmul(timeFrame, 1, &scale, &timeFrame, 1, vDSP_Length(Self.nFFT))

            // Overlap-add with window.
            let outOffset = frame * Self.hopLength
            for i in 0..<Self.nFFT {
                output[outOffset + i] += timeFrame[i] * window[i]
                windowSum[outOffset + i] += window[i] * window[i]
            }
        }

        // Normalize by window sum to compensate for overlap.
        for i in 0..<outputLength {
            if windowSum[i] > 1e-8 {
                output[i] /= windowSum[i]
            }
        }

        // Strip center padding if originalLength is specified.
        if let origLen = originalLength {
            let pad = Self.nFFT / 2
            let start = min(pad, output.count)
            let end = min(start + origLen, output.count)
            return Array(output[start..<end])
        }

        return output
    }

    // MARK: - Spectrogram Packing / Unpacking

    /// Pack left/right magnitude spectrograms into CoreML input format.
    ///
    /// Uses MLShapedArray for stride-safe access to the backing buffer.
    ///
    /// - Parameters:
    ///   - magL: Left channel magnitude (nBins * nbFrames), stored as [frame][bin].
    ///   - magR: Right channel magnitude (nBins * nbFrames), stored as [frame][bin].
    ///   - nbFrames: Number of STFT frames.
    /// - Returns: MLMultiArray of shape [1, 2, 2049, nbFrames].
    private func packSpectrogramForModel(
        magL: [Float], magR: [Float], nbFrames: Int
    ) throws -> MLMultiArray {
        let shape = [1, 2, Self.nBins, nbFrames]
        var shaped = MLShapedArray<Float>(repeating: 0, shape: shape)

        // Write via withUnsafeMutableShapedBufferPointer — handles padded strides correctly.
        shaped.withUnsafeMutableShapedBufferPointer { ptr, _, strides in
            for f in 0..<Self.nBins {
                for t in 0..<nbFrames {
                    let srcIdx = t * Self.nBins + f
                    ptr[0 * strides[0] + 0 * strides[1] + f * strides[2] + t * strides[3]] = magL[srcIdx]
                    ptr[0 * strides[0] + 1 * strides[1] + f * strides[2] + t * strides[3]] = magR[srcIdx]
                }
            }
        }

        return MLMultiArray(shaped)
    }

    /// Unpack CoreML output and apply iSTFT to reconstruct stem waveforms.
    ///
    /// Uses MLShapedArray for stride-safe access to the ANE output buffer,
    /// which has padded strides with unmapped memory in the padding regions.
    ///
    /// - Parameters:
    ///   - output: MLMultiArray of shape [4, 2, 2049, nbFrames].
    ///   - phaseL: Left channel phase spectrogram.
    ///   - phaseR: Right channel phase spectrogram.
    ///   - nbFrames: Number of STFT frames.
    /// - Returns: Array of 4 mono waveforms (L+R averaged).
    private func unpackAndISTFT(
        output: MLMultiArray,
        phaseL: [Float],
        phaseR: [Float],
        nbFrames: Int
    ) throws -> [[Float]] {
        let binsPerFrame = Self.nBins

        // Wrap the MLMultiArray in MLShapedArray for stride-safe buffer access.
        let shaped = MLShapedArray<Float>(converting: output)

        // Extract all stem spectrograms using withUnsafeShapedBufferPointer,
        // which correctly maps logical indices through padded strides.
        var allStemMagL = [[Float]](
            repeating: [Float](repeating: 0, count: binsPerFrame * nbFrames),
            count: Self.stemCount
        )
        var allStemMagR = [[Float]](
            repeating: [Float](repeating: 0, count: binsPerFrame * nbFrames),
            count: Self.stemCount
        )

        shaped.withUnsafeShapedBufferPointer { ptr, _, strides in
            for stem in 0..<Self.stemCount {
                let stemBase = stem * strides[0]
                let leftBase = stemBase
                let rightBase = stemBase + strides[1]

                for f in 0..<binsPerFrame {
                    let freqOff = f * strides[2]
                    for t in 0..<nbFrames {
                        let localIdx = t * binsPerFrame + f
                        let timeOff = t * strides[3]
                        allStemMagL[stem][localIdx] = ptr[leftBase + freqOff + timeOff]
                        allStemMagR[stem][localIdx] = ptr[rightBase + freqOff + timeOff]
                    }
                }
            }
        }

        var stemWaveforms = [[Float]]()
        stemWaveforms.reserveCapacity(Self.stemCount)

        for stem in 0..<Self.stemCount {
            // iSTFT each channel with original phase, then strip center padding.
            let waveL = istft(magnitude: allStemMagL[stem], phase: phaseL, nbFrames: nbFrames,
                              originalLength: Self.requiredMonoSamples)
            let waveR = istft(magnitude: allStemMagR[stem], phase: phaseR, nbFrames: nbFrames,
                              originalLength: Self.requiredMonoSamples)

            // Average to mono.
            let monoCount = min(waveL.count, waveR.count)
            var mono = [Float](repeating: 0, count: monoCount)
            for i in 0..<monoCount {
                mono[i] = (waveL[i] + waveR[i]) * 0.5
            }

            stemWaveforms.append(mono)
        }

        return stemWaveforms
    }

    // MARK: - Resampling

    /// Resample audio from one sample rate to another using vDSP.
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
    /// For mono input, returns the same array as both channels.
    private func deinterleave(_ audio: [Float], channelCount: Int) -> (left: [Float], right: [Float]) {
        guard channelCount >= 2 else {
            return (audio, audio)
        }

        let frameCount = audio.count / channelCount
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)

        for i in 0..<frameCount {
            left[i] = audio[i * channelCount]
            right[i] = audio[i * channelCount + 1]
        }

        return (left, right)
    }
}
