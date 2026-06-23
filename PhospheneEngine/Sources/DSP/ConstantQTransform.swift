// ConstantQTransform — 252-bin log-CQT in dB, matching librosa.cqt + amplitude_to_db.
//
// Spectral-kernel (Brown-Puckette) constant-Q: one sparse complex kernel per bin,
// precomputed at init; per frame, one real FFT of the (zero-padded, center=True)
// window followed by a sparse complex dot against each bin's kernel. Output is
// `amplitude_to_db(|CQT|, ref=max)` — the exact feature the validated McFee
// detector builds its recurrence graph on (SECDET, lab spec: tune_corpus.py).
//
// Per-bin absolute scaling is NOT matched to librosa's recursive method: norm=1
// kernels give a per-bin constant gain difference, which is a per-row constant
// dB offset after amplitude_to_db. That offset cancels in column-pair distances,
// so it does not perturb the downstream recurrence matrix / F-scores. Validation
// (SectionFeatureGoldenTests) uses per-row-demeaned metrics for this reason.

import Accelerate
import Foundation

// MARK: - ConstantQTransform

/// Offline 252-bin log-CQT (dB). Not thread-safe; one instance per analysis task.
final class ConstantQTransform {

    // MARK: - Spec (librosa.cqt defaults, fmin = C1)

    static let sampleRate = 22050.0
    static let hop = 512
    static let binsPerOctave = 36
    static let binCount = 252
    static let fmin = 32.70319566257483           // librosa.note_to_hz("C1")
    static let amin: Float = 1e-5                  // amplitude_to_db default
    static let topDB: Float = 80.0

    /// Q = filter_scale / (2^(1/B) − 1).
    static let qFactor = 1.0 / (pow(2.0, 1.0 / Double(binsPerOctave)) - 1.0)

    // MARK: - Precomputed kernel

    private let fftLen: Int
    private let pad: Int
    private let rfft: VDSPRealFFT

    /// Sparse spectral kernel, CSR-style across the 252 bins.
    private let rowStart: [Int]                    // binCount + 1
    private let colIndex: [Int32]                  // nonzero half-spectrum bins
    private let kernelReal: [Float]                // Re(conj(K)) / fftLen, pre-scaled
    private let kernelImag: [Float]                // Im(conj(K)) / fftLen, pre-scaled

    // MARK: - Init

    init() {
        let freqs = (0..<Self.binCount).map {
            Self.fmin * pow(2.0, Double($0) / Double(Self.binsPerOctave))
        }
        let lengths = freqs.map { Self.qFactor * Self.sampleRate / $0 }
        let maxLen = Int(ceil(lengths[0]))
        // Smallest power of two ≥ the longest filter (lowest bin).
        var len = 1
        while len < maxLen { len <<= 1 }
        self.fftLen = len
        self.pad = len / 2
        self.rfft = VDSPRealFFT(size: len)

        let kernel = Self.buildKernel(freqs: freqs, lengths: lengths, fftLen: len)
        self.rowStart = kernel.rowStart
        self.colIndex = kernel.colIndex
        self.kernelReal = kernel.kernelReal
        self.kernelImag = kernel.kernelImag
    }

    // MARK: - Kernel construction

    private struct Kernel {
        let rowStart: [Int]
        let colIndex: [Int32]
        let kernelReal: [Float]
        let kernelImag: [Float]
    }

    /// Build the sparse spectral kernel: per bin, a periodic-Hann-windowed complex
    /// exponential (L1-normalised, librosa norm=1), full-complex-FFT'd once, then
    /// reduced to the half-spectrum bins covering 99% of its L1 magnitude
    /// (librosa sparsity=0.01) with conj(K)/fftLen folded in for the per-frame dot.
    private static func buildKernel(freqs: [Double], lengths: [Double], fftLen len: Int) -> Kernel {
        var starts = [0]
        var cols: [Int32] = []
        var kre: [Float] = []
        var kim: [Float] = []
        let half = len / 2
        let kfft = ComplexFFT(size: len)
        var tReal = [Float](repeating: 0, count: len)
        var tImag = [Float](repeating: 0, count: len)
        var kReal = [Float](repeating: 0, count: len)
        var kImag = [Float](repeating: 0, count: len)
        var entries: [(bin: Int, mag: Float)] = []
        entries.reserveCapacity(half + 1)
        let invLen = 1.0 / Float(len)

        for binK in 0..<freqs.count {
            let lenK = max(1, Int(ceil(lengths[binK])))
            let offset = (len - lenK) / 2
            for idx in 0..<len { tReal[idx] = 0; tImag[idx] = 0 }
            // Periodic-Hann-windowed complex exponential, L1-normalised (norm=1).
            var winSum: Double = 0
            for idx in 0..<lenK {
                winSum += 0.5 * (1.0 - cos(2.0 * Double.pi * Double(idx) / Double(lenK)))
            }
            let invWin = winSum > 0 ? 1.0 / winSum : 1.0
            for idx in 0..<lenK {
                let win = 0.5 * (1.0 - cos(2.0 * Double.pi * Double(idx) / Double(lenK))) * invWin
                let phase = 2.0 * Double.pi * freqs[binK] * Double(idx) / sampleRate
                tReal[offset + idx] = Float(win * cos(phase))
                tImag[offset + idx] = Float(win * sin(phase))
            }
            kfft.forward(real: &tReal, imag: &tImag, outReal: &kReal, outImag: &kImag)

            // librosa sparsity=0.01: keep the smallest set of half-spectrum bins
            // covering 99% of this kernel's L1 magnitude. Drops the sidelobe tail
            // (the per-frame dot then touches only the main lobe — far fewer
            // scattered loads) and matches the basis librosa actually transforms.
            entries.removeAll(keepingCapacity: true)
            var total: Float = 0
            for bin in 0...half {
                let mag = (kReal[bin] * kReal[bin] + kImag[bin] * kImag[bin]).squareRoot()
                if mag > 0 { entries.append((bin, mag)); total += mag }
            }
            entries.sort { $0.mag > $1.mag }
            var cumulative: Float = 0
            let target = total * 0.99
            var kept: [Int] = []
            for ent in entries {
                kept.append(ent.bin); cumulative += ent.mag
                if cumulative >= target { break }
            }
            kept.sort()
            for bin in kept {
                cols.append(Int32(bin))
                // Store conj(K)/fftLen: CQT = (1/N) Σ F[ω]·conj(K[ω]).
                kre.append(kReal[bin] * invLen)
                kim.append(-kImag[bin] * invLen)
            }
            starts.append(cols.count)
        }
        return Kernel(rowStart: starts, colIndex: cols, kernelReal: kre, kernelImag: kim)
    }

    // MARK: - Transform

    /// Number of CQT frames for `nSamples` (librosa center=True: 1 + n/hop).
    static func frameCount(nSamples: Int) -> Int { 1 + nSamples / hop }

    /// Compute `amplitude_to_db(|CQT|, ref=max)` for mono 22050 Hz PCM.
    ///
    /// - Returns: bin-major row-major matrix, length `binCount * T`, indexed
    ///   `bin * T + frame` (matches librosa's `(252, T)` C-order layout).
    func dbMatrix(samples: [Float]) -> (data: [Float], frameCount: Int) {
        let nSamples = samples.count
        let frames = Self.frameCount(nSamples: nSamples)
        guard frames > 0 else { return ([], 0) }

        // Zero-pad fftLen/2 each side → window t = padded[t*hop ..< t*hop+fftLen]
        // is centred on original sample t*hop (center=True).
        var padded = [Float](repeating: 0, count: nSamples + 2 * pad)
        padded.withUnsafeMutableBufferPointer { dst in
            samples.withUnsafeBufferPointer { src in
                if let srcBase = src.baseAddress, let dstBase = dst.baseAddress {
                    (dstBase + pad).update(from: srcBase, count: nSamples)
                }
            }
        }

        // Magnitude accumulates bin-major so the dB pass can scan a contiguous row.
        var mag = [Float](repeating: 0, count: Self.binCount * frames)
        var outReal = [Float](repeating: 0, count: rfft.binCount)
        var outImag = [Float](repeating: 0, count: rfft.binCount)

        padded.withUnsafeBufferPointer { padBuf in
            let padBase = padBuf.baseAddress!    // swiftlint:disable:this force_unwrapping
            colIndex.withUnsafeBufferPointer { colBuf in
            kernelReal.withUnsafeBufferPointer { kreBuf in
            kernelImag.withUnsafeBufferPointer { kimBuf in
                // swiftlint:disable force_unwrapping
                let colBase = colBuf.baseAddress!
                let kreBase = kreBuf.baseAddress!
                let kimBase = kimBuf.baseAddress!
                // swiftlint:enable force_unwrapping
                for frameIdx in 0..<frames {
                    rfft.forward(frame: padBase + frameIdx * Self.hop, outReal: &outReal, outImag: &outImag)
                    outReal.withUnsafeBufferPointer { frBuf in
                    outImag.withUnsafeBufferPointer { fiBuf in
                        let frBase = frBuf.baseAddress!  // swiftlint:disable:this force_unwrapping
                        let fiBase = fiBuf.baseAddress!  // swiftlint:disable:this force_unwrapping
                        for binK in 0..<Self.binCount {
                            var accRe: Float = 0
                            var accIm: Float = 0
                            for idx in rowStart[binK]..<rowStart[binK + 1] {
                                let bin = Int(colBase[idx])
                                let freqRe = frBase[bin], freqIm = fiBase[bin]
                                let kerRe = kreBase[idx], kerIm = kimBase[idx]
                                // F·conj(K) (conj already folded into stored kernel).
                                accRe += freqRe * kerRe - freqIm * kerIm
                                accIm += freqRe * kerIm + freqIm * kerRe
                            }
                            mag[binK * frames + frameIdx] = (accRe * accRe + accIm * accIm).squareRoot()
                        }
                    }}
                }
            }}}
        }

        amplitudeToDBRefMax(&mag)
        return (mag, frames)
    }

    // MARK: - amplitude_to_db(ref=max)

    /// In-place `librosa.amplitude_to_db(S, ref=np.max)`: 20·log10(S/max(S)),
    /// floored at −top_db, with the amin / power-domain handling librosa uses.
    private func amplitudeToDBRefMax(_ spec: inout [Float]) {
        var peak: Float = 0
        vDSP_maxv(spec, 1, &peak, vDSP_Length(spec.count))
        let aminP = Self.amin * Self.amin                 // power-domain amin
        let refP = max(aminP, peak * peak)                // ref = max(S)^2
        let refDB = 10.0 * log10(refP)
        let floorDB = -Self.topDB                         // dBMax (≈0) − top_db
        for i in spec.indices {
            let pwr = max(aminP, spec[i] * spec[i])
            spec[i] = max(10.0 * log10(pwr) - refDB, floorDB)
        }
    }
}

// MARK: - ComplexFFT (init-time kernel transform)

/// Minimal complex-to-complex forward FFT (vDSP), used once per CQT bin at init.
private final class ComplexFFT {
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    let size: Int

    init(size: Int) {
        self.size = size
        self.log2n = vDSP_Length(log2(Double(size)))
        guard let created = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("ComplexFFT: vDSP_create_fftsetup failed for size=\(size)")
        }
        self.setup = created
    }
    deinit { vDSP_destroy_fftsetup(setup) }

    /// Standard forward DFT: out[ω] = Σ_n (real+i·imag)[n]·exp(−2πi ω n / N).
    func forward(real: inout [Float], imag: inout [Float],
                 outReal: inout [Float], outImag: inout [Float]) {
        real.withUnsafeMutableBufferPointer { realBuf in
            imag.withUnsafeMutableBufferPointer { imagBuf in
                // swiftlint:disable:next force_unwrapping
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }
        // vDSP forward complex FFT is unnormalised — copy straight out.
        let bytes = size * MemoryLayout<Float>.size
        outReal.withUnsafeMutableBufferPointer { dst in
            _ = real.withUnsafeBufferPointer { src in memcpy(dst.baseAddress, src.baseAddress, bytes) }
        }
        outImag.withUnsafeMutableBufferPointer { dst in
            _ = imag.withUnsafeBufferPointer { src in memcpy(dst.baseAddress, src.baseAddress, bytes) }
        }
    }
}
