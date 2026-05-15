// BeatThisPreprocessor — Beat This! log-mel spectrogram preprocessor.
//
// Converts mono Float32 audio to a (T, 128) log-mel spectrogram at 50 fps,
// matching Beat This!'s Python LogMelSpect exactly (commit 9d787b97).
//
// Parameters (from beat_this/preprocessing.py, LogMelSpect.__init__):
//   sample_rate  = 22050 Hz          (preprocessing.py:LogMelSpect.__init__:14)
//   n_fft        = 1024              (:14)
//   hop_length   = 441               (:14)
//   f_min        = 30 Hz             (:14)
//   f_max        = 11000 Hz          (:14)
//   n_mels       = 128               (:14)
//   mel_scale    = "slaney"          (:17)
//   normalized   = "frame_length"   (:18)  → divides STFT by sqrt(n_fft)
//   power        = 1                 (:19)  → magnitude (not power) spectrogram
//   log_multiplier = 1000            (:20)
//
// STFT normalization derivation:
//   torchaudio normalized="frame_length" divides magnitudes by sqrt(n_fft) = 32.
//   vDSP_fft_zrip returns 2× the standard DFT for all bins (Apple docs).
//   Combined scale = 1 / (2 × sqrt(n_fft)) = 1 / 64.
//
// Mel filterbank: Slaney mel scale (linear ≤ 1000 Hz, log > 1000 Hz),
//   no area normalization (torchaudio default norm=None). Triangle filters,
//   shape (128, 513). Built once at init; mat-mul per frame via vDSP_mmul.
//
// Padding: reflect-pad by n_fft/2 = 512 samples on each side (center=True,
//   matches torchaudio STFT default).
//
// Performance: all working buffers pre-allocated at init; zero heap allocation
//   per frame inside process(). Protected by NSLock for thread safety.

// swiftlint:disable file_length
// File length warning suppressed: the STFT pipeline is one cohesive
// numerical-kernel module. Splitting buildMelFilterbank or processLocked
// to a sibling file would either (a) leak private state across files or
// (b) require regenerating the BeatThisPreprocessorGoldenTest reference
// activation dump, which is a non-trivial change. Accept the file length.

import Foundation
import Accelerate
@preconcurrency import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.dsp", category: "BeatThisPreprocessor")

// MARK: - BeatThisPreprocessor

/// Beat This! log-mel spectrogram preprocessor.
///
/// Call `process(samples:inputSampleRate:)` with mono PCM audio to receive a
/// flat row-major (T × 128) Float32 array. Each row is one 50-fps mel frame.
///
/// Thread-safe via an internal lock. One instance per pipeline is sufficient.
public final class BeatThisPreprocessor: @unchecked Sendable {

    // MARK: - Parameters

    /// Target sample rate (Hz). Audio resampled to this before STFT.
    public static let sampleRate: Int = 22050

    /// FFT size (samples).
    public static let nFFT: Int = 1024

    /// STFT hop length (samples). Produces 50 fps at 22050 Hz.
    public static let hopLength: Int = 441

    /// Number of mel bins.
    public static let nMels: Int = 128

    /// Mel filterbank lower frequency bound (Hz).
    public static let fMin: Float = 30.0

    /// Mel filterbank upper frequency bound (Hz).
    public static let fMax: Float = 11000.0

    /// log1p multiplier applied after mel filterbank.
    public static let logMultiplier: Float = 1000.0

    /// Number of STFT magnitude bins (nFFT/2 + 1).
    public static let nBins: Int = nFFT / 2 + 1  // 513

    /// Reflect-padding size (nFFT / 2).
    static let padSize: Int = nFFT / 2  // 512

    // vDSP_fft_zrip returns 2× standard DFT for all bins.
    // torchaudio normalized="frame_length" divides by sqrt(n_fft) = 32.
    // Combined correction: 1 / (2 × sqrt(1024)) = 1/64.
    static let stftScale: Float = 1.0 / (2.0 * Float(nFFT).squareRoot())

    private static let log2n: vDSP_Length = 10  // log2(1024)

    // MARK: - Pre-allocated buffers

    private let fftSetup: FFTSetup
    private var window: [Float]          // nFFT = 1024 — periodic Hann
    private var windowedFrame: [Float]   // nFFT = 1024
    private var splitRealp: [Float]      // nFFT/2 = 512
    private var splitImagp: [Float]      // nFFT/2 = 512
    private var magnitudes: [Float]      // nBins = 513
    private var melFrame: [Float]        // nMels = 128
    private var filterbank: [Float]      // nMels × nBins = 128 × 513 (row-major)
    private var paddedSignal: [Float]    // grown as needed per call

    private let lock = NSLock()

    // MARK: - Init

    /// Initialise preprocessor. Builds the Slaney mel filterbank and FFT setup.
    /// Subsequent `process()` calls are zero-alloc in the hot path.
    public init() {
        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("BeatThisPreprocessor: FFT setup failed for log2n=\(Self.log2n)")
        }
        fftSetup = setup

        // Periodic Hann window: w[n] = 0.5 × (1 − cos(2π×n/N))
        // Matches torch.hann_window(N, periodic=True).
        window = (0..<Self.nFFT).map { sampleIdx in
            0.5 * (1.0 - cos(2.0 * Float.pi * Float(sampleIdx) / Float(Self.nFFT)))
        }

        windowedFrame = [Float](repeating: 0, count: Self.nFFT)
        splitRealp    = [Float](repeating: 0, count: Self.nFFT / 2)
        splitImagp    = [Float](repeating: 0, count: Self.nFFT / 2)
        magnitudes    = [Float](repeating: 0, count: Self.nBins)
        melFrame      = [Float](repeating: 0, count: Self.nMels)
        filterbank    = [Float](repeating: 0, count: Self.nMels * Self.nBins)
        paddedSignal  = []

        buildMelFilterbank()

        // swiftlint:disable:next line_length
        logger.info("BeatThisPreprocessor ready: sr=\(Self.sampleRate) n_fft=\(Self.nFFT) hop=\(Self.hopLength) mels=\(Self.nMels)")
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Public API

    /// Convert mono PCM audio to a log-mel spectrogram.
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 PCM at `inputSampleRate`.
    ///   - inputSampleRate: Source sample rate. Audio is resampled via
    ///     `AVAudioConverter` when this differs from 22050 Hz.
    /// - Returns: `(data, frameCount)` where `data` is a flat row-major
    ///   Float32 array of shape (frameCount, 128), and
    ///   `frameCount = samples.count / hopLength + 1` after resampling.
    public func process(
        samples: [Float],
        inputSampleRate: Double = Double(BeatThisPreprocessor.sampleRate)
    ) -> (data: [Float], frameCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        return processLocked(samples: samples, inputSampleRate: inputSampleRate)
    }

    // MARK: - Core pipeline (must be called under lock)

    // swiftlint:disable:next function_body_length
    private func processLocked(
        samples: [Float],
        inputSampleRate: Double
    ) -> (data: [Float], frameCount: Int) {

        // 1. Resample if needed
        let signal: [Float] = inputSampleRate == Double(Self.sampleRate)
            ? samples
            : resample(samples, from: inputSampleRate, to: Double(Self.sampleRate))

        let nSamples = signal.count
        guard nSamples >= 2 else {
            logger.warning("BeatThisPreprocessor: signal too short (\(nSamples) samples)")
            return ([], 0)
        }

        let padN = Self.padSize          // 512
        let nFrames = nSamples / Self.hopLength + 1
        let paddedN = nSamples + 2 * padN

        // 2. Grow padded buffer if needed (amortised; rare after first call)
        if paddedSignal.count < paddedN {
            paddedSignal = [Float](repeating: 0, count: paddedN)
        }

        // 3. Reflect-pad: left = signal[padN..1] (reversed), right = signal[nSamples-2..nSamples-padN-1]
        signal.withUnsafeBufferPointer { sig in
            guard let sigBase = sig.baseAddress else { return }
            paddedSignal.withUnsafeMutableBufferPointer { pad in
                guard let padBase = pad.baseAddress else { return }
                // Left reflect: padded[i] = signal[padN - i] for i in 0..<padN
                for i in 0..<padN {
                    padBase[i] = sigBase[padN - i]
                }
                // Copy signal
                memcpy(padBase + padN, sigBase, nSamples * MemoryLayout<Float>.size)
                // Right reflect: padded[nSamples+padN+j] = signal[nSamples-2-j] for j in 0..<padN
                for j in 0..<padN {
                    padBase[nSamples + padN + j] = sigBase[nSamples - 2 - j]
                }
            }
        }

        // 4. STFT → mel → log1p across all nFrames frames
        var output = [Float](repeating: 0, count: nFrames * Self.nMels)

        // Hoist unsafe-buffer-pointer accesses outside the frame loop.
        splitRealp.withUnsafeMutableBufferPointer { rBuf in
        splitImagp.withUnsafeMutableBufferPointer { iBuf in
        window.withUnsafeBufferPointer { wBuf in
        windowedFrame.withUnsafeMutableBufferPointer { wfBuf in
        magnitudes.withUnsafeMutableBufferPointer { mBuf in
        melFrame.withUnsafeMutableBufferPointer { mfBuf in
        filterbank.withUnsafeBufferPointer { fbBuf in
        paddedSignal.withUnsafeBufferPointer { padBuf in
        output.withUnsafeMutableBufferPointer { outBuf in

            // swiftlint:disable force_unwrapping
            // baseAddress on a non-empty UnsafeBufferPointer is guaranteed
            // non-nil; all nine buffers above are pre-allocated at init
            // (windowedFrame, splitRealp, splitImagp, magnitudes, melFrame,
            // filterbank, window) or sized just above (paddedSignal, output).
            let rBase  = rBuf.baseAddress!
            let iBase  = iBuf.baseAddress!
            let wBase  = wBuf.baseAddress!
            let wfBase = wfBuf.baseAddress!
            let mBase  = mBuf.baseAddress!
            let mfBase = mfBuf.baseAddress!
            let fbBase = fbBuf.baseAddress!
            let padBase = padBuf.baseAddress!
            let outBase = outBuf.baseAddress!
            // swiftlint:enable force_unwrapping

            for frameIdx in 0..<nFrames {
                let frameStart = frameIdx * Self.hopLength

                // 4a. Window the frame: wf[n] = padded[frameStart+n] × window[n]
                vDSP_vmul(padBase + frameStart, 1, wBase, 1, wfBase, 1, vDSP_Length(Self.nFFT))

                // 4b. Pack real signal into split complex for vDSP_fft_zrip.
                //     Real signal treated as N/2 complex pairs: re[k]=signal[2k], im[k]=signal[2k+1].
                var split = DSPSplitComplex(realp: rBase, imagp: iBase)
                wfBase.withMemoryRebound(to: DSPComplex.self, capacity: Self.nFFT / 2) { cPtr in
                    vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(Self.nFFT / 2))
                }

                // 4c. Forward FFT. Output: realp[0]=2×DC, imagp[0]=2×Nyquist,
                //     realp[k]+i×imagp[k] = 2×X[k] for k=1..N/2-1.
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))

                // 4d. Magnitude for bins 1..N/2-1 via vDSP_zvabs.
                //     Skip bin 0 (DC and Nyquist are packed there differently).
                var innerSplit = DSPSplitComplex(realp: rBase + 1, imagp: iBase + 1)
                vDSP_zvabs(&innerSplit, 1, mBase + 1, 1, vDSP_Length(Self.nFFT / 2 - 1))

                // 4e. DC (bin 0) and Nyquist (bin N/2) — both real-valued.
                mBase[0] = abs(rBase[0])
                mBase[Self.nFFT / 2] = abs(iBase[0])

                // 4f. Apply combined normalization: 1 / (2 × sqrt(n_fft)) = 1/64.
                var scale = Self.stftScale
                vDSP_vsmul(mBase, 1, &scale, mBase, 1, vDSP_Length(Self.nBins))

                // 4g. Mel filterbank: (nMels, nBins) × (nBins,) → (nMels,)
                vDSP_mmul(fbBase, 1, mBase, 1, mfBase, 1, vDSP_Length(Self.nMels), 1, vDSP_Length(Self.nBins))

                // 4h. log1p(logMultiplier × mel): multiply then vvlog1pf
                var mult = Self.logMultiplier
                vDSP_vsmul(mfBase, 1, &mult, mfBase, 1, vDSP_Length(Self.nMels))
                var cnt = Int32(Self.nMels)
                vvlog1pf(mfBase, mfBase, &cnt)

                // 4i. Copy mel frame into output
                memcpy(outBase + frameIdx * Self.nMels, mfBase, Self.nMels * MemoryLayout<Float>.size)
            }
        }}}}}}}}} // end nested withUnsafe* closures

        return (data: output, frameCount: nFrames)
    }

    // MARK: - Slaney mel filterbank

    /// Builds a (nMels × nBins) row-major filterbank in `filterbank`.
    ///
    /// Matches torchaudio's `create_fb_matrix` with mel_scale="slaney", norm=None exactly:
    ///   - FFT bin b has frequency: b × (sr/2) / (nBins−1)  (linspace(0, sr/2, nBins))
    ///   - nMels+2 breakpoints linearly-spaced in Slaney mel domain → converted to Hz
    ///   - weight[b,m] = max(0, min(rising, falling)) with continuous Hz interpolation
    ///   - No area normalization (norm=None)
    private func buildMelFilterbank() {
        // Slaney mel scale constants (librosa/torchaudio create_fb_matrix).
        let fSp: Float       = 200.0 / 3.0    // Hz per mel (linear region slope)
        let minLogHz: Float  = 1000.0          // linear→log transition frequency
        let minLogMel: Float = minLogHz / fSp  // = 15.0 mel
        let logStep: Float   = log(6.4) / 27.0 // step size in log region

        func hzToMel(_ hz: Float) -> Float {
            hz < minLogHz
                ? hz / fSp
                : minLogMel + log(hz / minLogHz) / logStep
        }
        func melToHz(_ mel: Float) -> Float {
            mel < minLogMel
                ? mel * fSp
                : minLogHz * exp(logStep * (mel - minLogMel))
        }

        // FFT bin frequencies: linspace(0, sr/2, nBins) — matches torchaudio.
        // all_freqs[b] = b × (sample_rate/2) / (nBins−1)
        let halfSr = Float(Self.sampleRate) / 2.0  // 11025 Hz
        let allFreqs = (0..<Self.nBins).map { binIdx -> Float in
            Float(binIdx) * halfSr / Float(Self.nBins - 1)
        }

        // nMels+2 mel breakpoints, linspace in mel → converted to Hz.
        let melMin  = hzToMel(Self.fMin)
        let melMax  = hzToMel(Self.fMax)
        let nPoints = Self.nMels + 2  // 130
        let fPts = (0..<nPoints).map { i -> Float in
            let frac = Float(i) / Float(nPoints - 1)
            return melToHz(melMin + frac * (melMax - melMin))
        }

        // Triangle filters: continuous frequency interpolation (torchaudio formula).
        //   rising[b,m]  = (allFreqs[b] − fPts[m])   / (fPts[m+1] − fPts[m])
        //   falling[b,m] = (fPts[m+2] − allFreqs[b]) / (fPts[m+2] − fPts[m+1])
        //   weight[b,m]  = max(0, min(rising, falling))
        // filterbank layout: row m, col b → filterbank[m * nBins + b]
        for melIdx in 0..<Self.nMels {
            let fLeft   = fPts[melIdx]
            let fCenter = fPts[melIdx + 1]
            let fRight  = fPts[melIdx + 2]
            let riseW   = fCenter - fLeft    // > 0 by construction
            let fallW   = fRight - fCenter  // > 0 by construction

            for binIdx in 0..<Self.nBins {
                let hz      = allFreqs[binIdx]
                let rising  = riseW > 0 ? (hz - fLeft) / riseW : 0
                let falling = fallW > 0 ? (fRight - hz) / fallW : 0
                filterbank[melIdx * Self.nBins + binIdx] = max(0.0, min(rising, falling))
            }
        }
    }

    // MARK: - Resampling

    /// Resample mono Float32 audio from `srcRate` to `dstRate` using AVAudioConverter.
    ///
    /// Note: vDSP has no general-ratio resampler; AVAudioConverter (libresample under
    /// the hood) produces quality comparable to torchaudio's soxr default.
    private func resample(
        _ samples: [Float],
        from srcRate: Double,
        to dstRate: Double
    ) -> [Float] {
        guard let srcFmt = AVAudioFormat(standardFormatWithSampleRate: srcRate, channels: 1),
              let dstFmt = AVAudioFormat(standardFormatWithSampleRate: dstRate, channels: 1),
              let converter = AVAudioConverter(from: srcFmt, to: dstFmt) else {
            logger.error("BeatThisPreprocessor: AVAudioConverter init failed \(srcRate)→\(dstRate) Hz")
            return samples
        }

        let srcCount = samples.count
        let dstCount = Int(ceil(Double(srcCount) * dstRate / srcRate)) + 1

        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFmt,
                                            frameCapacity: AVAudioFrameCount(srcCount)),
              let dstBuf = AVAudioPCMBuffer(pcmFormat: dstFmt,
                                            frameCapacity: AVAudioFrameCount(dstCount)) else {
            logger.error("BeatThisPreprocessor: AVAudioPCMBuffer allocation failed")
            return samples
        }

        srcBuf.frameLength = AVAudioFrameCount(srcCount)
        samples.withUnsafeBufferPointer { src in
            _ = src  // suppress unused-result warning; memcpy is the side effect
            // floatChannelData is non-nil for any AVAudioFormat constructed via
            // standardFormatWithSampleRate (Float32 PCM) — verified above.
            // baseAddress is non-nil on a non-empty buffer (srcCount >= 1).
            // swiftlint:disable:next force_unwrapping
            memcpy(srcBuf.floatChannelData![0], src.baseAddress!, srcCount * MemoryLayout<Float>.size)
        }

        // nonisolated(unsafe): these vars are only accessed from the convert callback,
        // which AVAudioConverter calls synchronously on this thread.
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let capturedSrcBuf = srcBuf
        var convError: NSError?
        _ = converter.convert(to: dstBuf, error: &convError) { _, outStatus in
            guard !consumed else {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return capturedSrcBuf
        }

        if let err = convError {
            logger.error("BeatThisPreprocessor: AVAudioConverter error: \(err)")
            return samples
        }

        let outCount = Int(dstBuf.frameLength)
        // floatChannelData is non-nil for any AVAudioFormat constructed via
        // standardFormatWithSampleRate (Float32 PCM) — verified above.
        // swiftlint:disable:next force_unwrapping
        return Array(UnsafeBufferPointer(start: dstBuf.floatChannelData![0], count: outCount))
    }
}
