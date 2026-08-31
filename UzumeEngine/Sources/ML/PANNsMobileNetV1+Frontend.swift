// PANNsMobileNetV1+Frontend — PANNs log-mel front-end (Swift / vDSP).
//
// Exact reproduction of the torchlibrosa Spectrogram + LogmelFilterBank used by
// PANNs, achieved by matmul against the checkpoint's own matrices rather than
// reimplementing librosa: the STFT is a framed matmul against the Hann-windowed
// DFT basis (conv_real / conv_imag), the mel projection a matmul against melW.
// Validated to < 2e-6 max abs vs the PyTorch reference log-mel (IFC.2).
//
// Pipeline: reflect-pad (n_fft/2, center=True) → frame (win 1024, hop 320) →
// real/imag = frames · basisᵀ → power = real² + imag² → mel = power · melW →
// 10·log10(clamp(mel, 1e-10)). amin=1e-10, ref=1.0, top_db=none.

import Accelerate
import Foundation

// MARK: - PANNsFrontend

/// Computes the PANNs log-mel spectrogram. Holds the transposed STFT basis so
/// the per-call hot path is three vDSP matmuls + a vectorized log.
struct PANNsFrontend {

    private let convRealT: [Float]   // [nFFT, nBins] = conv_realᵀ
    private let convImagT: [Float]   // [nFFT, nBins]
    private let melW: [Float]        // [nBins, 64]
    private let nBins: Int
    private let nFFT = PANNsMobileNetV1.nFFT
    private let hop = PANNsMobileNetV1.hop
    private let melBins = PANNsMobileNetV1.melBins

    init(matrices: PANNsFrontendMatrices) {
        self.nBins = matrices.nBins
        self.melW = matrices.melW
        self.convRealT = Self.transpose(matrices.convReal, rows: matrices.nBins, cols: nFFT)
        self.convImagT = Self.transpose(matrices.convImag, rows: matrices.nBins, cols: nFFT)
    }

    /// Transpose a row-major [rows × cols] matrix to [cols × rows].
    private static func transpose(_ matrix: [Float], rows: Int, cols: Int) -> [Float] {
        var out = [Float](repeating: 0, count: rows * cols)
        vDSP_mtrans(matrix, 1, &out, 1, vDSP_Length(cols), vDSP_Length(rows))
        return out
    }

    /// Log-mel for `waveform`, shaped to exactly `frames` rows (row-major
    /// [frames * 64]). Frames beyond the natural count are padded with the
    /// silence floor (10·log10(1e-10) = -100); excess frames are truncated.
    func logMel(waveform: [Float], frames: Int) -> [Float] {
        let pad = nFFT / 2
        let padded = reflectPad(waveform, pad: pad)
        let nfr = padded.count >= nFFT ? 1 + (padded.count - nFFT) / hop : 0

        // Frame matrix [nfr × nFFT], row-major.
        var framesMat = [Float](repeating: 0, count: nfr * nFFT)
        padded.withUnsafeBufferPointer { src in
            framesMat.withUnsafeMutableBufferPointer { dst in
                guard let srcBase = src.baseAddress, let dstBase = dst.baseAddress else { return }
                for frame in 0..<nfr {
                    memcpy(dstBase + frame * nFFT, srcBase + frame * hop, nFFT * MemoryLayout<Float>.size)
                }
            }
        }

        // real / imag = frames · basisᵀ  → [nfr × nBins]
        var real = [Float](repeating: 0, count: nfr * nBins)
        var imag = [Float](repeating: 0, count: nfr * nBins)
        vDSP_mmul(framesMat, 1, convRealT, 1, &real, 1, vDSP_Length(nfr), vDSP_Length(nBins), vDSP_Length(nFFT))
        vDSP_mmul(framesMat, 1, convImagT, 1, &imag, 1, vDSP_Length(nfr), vDSP_Length(nBins), vDSP_Length(nFFT))

        // power = real² + imag²
        var power = [Float](repeating: 0, count: nfr * nBins)
        vDSP_vsq(real, 1, &power, 1, vDSP_Length(nfr * nBins))
        var imagSq = [Float](repeating: 0, count: nfr * nBins)
        vDSP_vsq(imag, 1, &imagSq, 1, vDSP_Length(nfr * nBins))
        vDSP_vadd(power, 1, imagSq, 1, &power, 1, vDSP_Length(nfr * nBins))

        // mel = power · melW  → [nfr × 64]
        var mel = [Float](repeating: 0, count: nfr * melBins)
        vDSP_mmul(power, 1, melW, 1, &mel, 1, vDSP_Length(nfr), vDSP_Length(melBins), vDSP_Length(nBins))

        // logmel = 10 · log10(clamp(mel, 1e-10))
        var amin: Float = 1e-10
        vDSP_vthr(mel, 1, &amin, &mel, 1, vDSP_Length(nfr * melBins))
        var count = Int32(nfr * melBins)
        var logmel = [Float](repeating: 0, count: nfr * melBins)
        vvlog10f(&logmel, mel, &count)
        var ten: Float = 10
        vDSP_vsmul(logmel, 1, &ten, &logmel, 1, vDSP_Length(nfr * melBins))

        return fit(logmel, naturalFrames: nfr, to: frames)
    }

    /// numpy `np.pad(x, pad, mode="reflect")` (reflect_type="even"): mirror about
    /// the edge sample without repeating it. Requires count > pad.
    private func reflectPad(_ x: [Float], pad: Int) -> [Float] {
        let count = x.count
        var out = [Float](repeating: 0, count: count + 2 * pad)
        for i in 0..<pad { out[i] = x[pad - i] }                       // left:  x[pad]…x[1]
        for i in 0..<count { out[pad + i] = x[i] }                     // middle
        for j in 0..<pad { out[pad + count + j] = x[count - 2 - j] }   // right: x[n-2]…x[n-1-pad]
        return out
    }

    /// Pad/truncate the frame axis of a [naturalFrames × 64] log-mel to `frames`.
    private func fit(_ logmel: [Float], naturalFrames: Int, to frames: Int) -> [Float] {
        if naturalFrames == frames { return logmel }
        var out = [Float](repeating: 10 * log10f(1e-10), count: frames * melBins)
        let copyCount = min(naturalFrames, frames) * melBins
        out.replaceSubrange(0..<copyCount, with: logmel[0..<copyCount])
        return out
    }
}
