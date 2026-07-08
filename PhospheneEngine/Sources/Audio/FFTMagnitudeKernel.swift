// FFTMagnitudeKernel — the single source of truth for the window→magnitude formula.
//
// BUG-066 / MOOD-FLUX.3: the live (FFTProcessor) and offline (SessionPreparer.analyzeMIR)
// paths each had their own copy of "Hann-window → forward FFT → |FFT| × 2/fftSize", and
// they silently drifted (offline ran 16× hot for months, saturating the mood classifier's
// flux input). This kernel is that formula — plus the vDSP FFT-setup lifecycle and the
// per-call scratch — factored out once so the two paths, plus the CorpusCensusRunner
// mirror, physically cannot diverge again. Change the magnitude formula here or nowhere;
// the divergence-guard test (FFTRegressionTests) fails if a second copy reappears.

import Accelerate
import Foundation

// MARK: - FFTMagnitudeKernel

/// Owns the Hann window, split-complex scratch, and vDSP `FFTSetup` for one 1024-pt
/// magnitude path. Allocation-free per call and CPU-only (no `MTLDevice`): the live
/// real-time path stays zero-alloc per frame (BUG-036) and the offline path stays
/// device-free. Not `Sendable` — each consumer owns its own instance on one thread.
public final class FFTMagnitudeKernel {

    public let fftSize: Int
    public let binCount: Int

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let hann: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]

    /// Time-domain input scratch. The caller writes the frame's `fftSize` raw samples
    /// here (zero-padding as needed) before each `computeMagnitudes()` call; it is
    /// overwritten in place with the windowed samples.
    public var windowed: [Float]

    /// Output: `binCount` magnitude bins (`|FFT| × 2/fftSize`) after `computeMagnitudes()`.
    public private(set) var magnitudes: [Float]

    /// - Parameter fftSize: FFT length (power of two); produces `fftSize / 2` bins.
    public init(fftSize: Int) throws {
        self.fftSize = fftSize
        self.binCount = fftSize / 2
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw FFTError.setupFailed
        }
        self.fftSetup = setup

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.hann = window
        self.realPart = [Float](repeating: 0, count: binCount)
        self.imagPart = [Float](repeating: 0, count: binCount)
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.magnitudes = [Float](repeating: 0, count: binCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Apply the Hann window to `windowed` (in place), run the forward real FFT, and
    /// write `|FFT| × 2/fftSize` into `magnitudes`. Allocation-free — all buffers persist.
    public func computeMagnitudes() {
        // Hann window (in place).
        vDSP_vmul(windowed, 1, hann, 1, &windowed, 1, vDSP_Length(fftSize))

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let rBase = realBuf.baseAddress, let iBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: rBase, imagp: iBase)

                windowed.withUnsafeBufferPointer { input in
                    guard let inp = input.baseAddress else { return }
                    inp.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(binCount))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    guard let mBase = magBuf.baseAddress else { return }
                    // |FFT| (zvabs), NOT power (zvmags). See BUG-066.
                    vDSP_zvabs(&split, 1, mBase, 1, vDSP_Length(binCount))
                }
            }
        }

        // Normalize by FFT size: |FFT| × 2/fftSize.
        var scale = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(binCount))
    }
}
