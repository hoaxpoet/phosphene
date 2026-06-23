// VDSPRealFFT — minimal reusable forward real FFT (vDSP), standard-DFT scaled.
//
// Shared by the offline section-feature kernels (ConstantQTransform @ 65536,
// MFCCProcessor @ 2048). Takes an already-windowed real frame and produces the
// standard complex half-spectrum (length n/2+1), undoing vDSP_fft_zrip's 2×
// convention and its DC/Nyquist packing so callers get textbook X[k].

import Accelerate
import Foundation

// MARK: - VDSPRealFFT

/// Forward real FFT for a fixed power-of-two size. Not thread-safe; create one
/// per offline analysis task and call `forward` serially.
final class VDSPRealFFT {

    /// FFT size (power of two).
    let size: Int

    /// Half-spectrum length (`size/2 + 1`).
    let binCount: Int

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var realScratch: [Float]
    private var imagScratch: [Float]

    // MARK: - Init

    /// - Parameter size: FFT size; must be a power of two.
    init(size: Int) {
        precondition(size > 0 && (size & (size - 1)) == 0, "VDSPRealFFT size must be a power of two")
        self.size = size
        self.binCount = size / 2 + 1
        self.log2n = vDSP_Length(log2(Double(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("VDSPRealFFT: vDSP_create_fftsetup failed for size=\(size)")
        }
        self.setup = setup
        self.realScratch = [Float](repeating: 0, count: size / 2)
        self.imagScratch = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    // MARK: - Transform

    /// Forward FFT of an already-windowed real frame.
    ///
    /// - Parameters:
    ///   - frame: Real samples, exactly `size` values (windowing pre-applied).
    ///   - outReal: Receives Re(X[k]) for k in 0...size/2 (length `binCount`).
    ///   - outImag: Receives Im(X[k]) for k in 0...size/2 (length `binCount`).
    ///
    /// Output is the standard DFT (vDSP's 2× removed; DC and Nyquist placed at
    /// indices 0 and size/2 with zero imaginary part).
    func forward(frame: UnsafePointer<Float>, outReal: inout [Float], outImag: inout [Float]) {
        let half = size / 2
        realScratch.withUnsafeMutableBufferPointer { realBuf in
            imagScratch.withUnsafeMutableBufferPointer { imagBuf in
                // swiftlint:disable force_unwrapping
                let realBase = realBuf.baseAddress!
                let imagBase = imagBuf.baseAddress!
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { complexPtr in
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                outReal.withUnsafeMutableBufferPointer { outRealBuf in
                    outImag.withUnsafeMutableBufferPointer { outImagBuf in
                        let outRealBase = outRealBuf.baseAddress!
                        let outImagBase = outImagBuf.baseAddress!
                        // vDSP packs 2×DC in realp[0], 2×Nyquist in imagp[0];
                        // 2×X[k] in realp[k]/imagp[k] for k=1..half-1.
                        outRealBase[0] = realBase[0] * 0.5
                        outImagBase[0] = 0
                        outRealBase[half] = imagBase[0] * 0.5
                        outImagBase[half] = 0
                        var scale: Float = 0.5
                        vDSP_vsmul(realBase + 1, 1, &scale, outRealBase + 1, 1, vDSP_Length(half - 1))
                        vDSP_vsmul(imagBase + 1, 1, &scale, outImagBase + 1, 1, vDSP_Length(half - 1))
                    }
                }
                // swiftlint:enable force_unwrapping
            }
        }
    }
}
