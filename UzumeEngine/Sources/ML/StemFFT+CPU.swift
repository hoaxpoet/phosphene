// StemFFT+CPU — CPU vDSP fallback path for the stem STFT engine.
//
// This is the original Accelerate-based STFT/iSTFT that lived inside
// `StemSeparator` before Increment 3.1a promoted the work to MPSGraph.
// It stays alive for two reasons:
//
// 1. Cross-validation: the GPU path is tested against this reference with
//    ``StemFFTEngine/forceCPUFallback`` = `true`.
// 2. Fallback: any input whose frame count differs from the fixed graph
//    size (`StemFFTEngine.modelFrameCount`) routes here transparently,
//    avoiding graph recompilation for test clips.
//
// A follow-up increment may retire this path once Increment 3.1b has
// demonstrated the GPU path working under live-stream load.

import Accelerate
import Foundation

extension StemFFTEngine {

    // MARK: - CPU Forward STFT

    internal func cpuForward(mono: [Float]) -> (magnitude: [Float], phase: [Float]) {
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
        var windowedFrame = [Float](repeating: 0, count: Self.nFFT)
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        for frame in 0..<nbFrames {
            let offset = frame * Self.hopLength
            for i in 0..<Self.nFFT {
                windowedFrame[i] = padded[offset + i] * window[i]
            }

            windowedFrame.withUnsafeBufferPointer { srcPtr in
                realPart.withUnsafeMutableBufferPointer { realBuf in
                    imagPart.withUnsafeMutableBufferPointer { imagBuf in
                        guard let realBase = realBuf.baseAddress,
                              let imagBase = imagBuf.baseAddress,
                              let srcBase = srcPtr.baseAddress else { return }
                        var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                        srcBase.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                        }
                        vDSP_fft_zrip(
                            fftSetup, &splitComplex, 1, Self.log2n, FFTDirection(FFT_FORWARD)
                        )
                    }
                }
            }

            let binOffset = frame * Self.nBins
            let scale = 1.0 / Float(Self.nFFT)

            // DC bin packed into realPart[0].
            magnitude[binOffset] = abs(realPart[0]) * scale
            phase[binOffset] = realPart[0] >= 0 ? 0 : .pi

            for bin in 1..<halfN {
                let re = realPart[bin]
                let im = imagPart[bin]
                magnitude[binOffset + bin] = sqrtf(re * re + im * im) * scale
                phase[binOffset + bin] = atan2f(im, re)
            }

            // Nyquist bin packed into imagPart[0].
            magnitude[binOffset + halfN] = abs(imagPart[0]) * scale
            phase[binOffset + halfN] = imagPart[0] >= 0 ? 0 : .pi
        }

        return (magnitude, phase)
    }

    // MARK: - CPU Inverse STFT

    internal func cpuInverse(
        magnitude: [Float], phase: [Float], nbFrames: Int, originalLength: Int?
    ) -> [Float] {
        let outputLength = (nbFrames - 1) * Self.hopLength + Self.nFFT
        var output = [Float](repeating: 0, count: outputLength)
        var windowSum = [Float](repeating: 0, count: outputLength)

        let halfN = Self.nFFT / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var timeFrame = [Float](repeating: 0, count: Self.nFFT)

        for frame in 0..<nbFrames {
            let binOffset = frame * Self.nBins

            // DC — packed in realPart[0] with the scale pre-multiply.
            realPart[0] = magnitude[binOffset] * cosf(phase[binOffset]) * Float(Self.nFFT)
            // Nyquist — packed in imagPart[0].
            imagPart[0] = magnitude[binOffset + halfN] * cosf(phase[binOffset + halfN]) * Float(Self.nFFT)

            for bin in 1..<halfN {
                let mag = magnitude[binOffset + bin] * Float(Self.nFFT)
                let ph = phase[binOffset + bin]
                realPart[bin] = mag * cosf(ph)
                imagPart[bin] = mag * sinf(ph)
            }

            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    guard let realBase = realBuf.baseAddress,
                          let imagBase = imagBuf.baseAddress else { return }
                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    vDSP_fft_zrip(
                        fftSetup, &splitComplex, 1, Self.log2n, FFTDirection(FFT_INVERSE)
                    )
                    timeFrame.withUnsafeMutableBufferPointer { dstBuf in
                        guard let dstBase = dstBuf.baseAddress else { return }
                        dstBase.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                            vDSP_ztoc(&splitComplex, 1, complexPtr, 2, vDSP_Length(halfN))
                        }
                    }
                }
            }

            // vDSP's inverse FFT contributes an additional factor of 2 that we
            // normalize out alongside the 1/nFFT scale.
            var scale = 1.0 / Float(2 * Self.nFFT)
            vDSP_vsmul(timeFrame, 1, &scale, &timeFrame, 1, vDSP_Length(Self.nFFT))

            let outOffset = frame * Self.hopLength
            for i in 0..<Self.nFFT {
                output[outOffset + i] += timeFrame[i] * window[i]
                windowSum[outOffset + i] += window[i] * window[i]
            }
        }

        for i in 0..<outputLength where windowSum[i] > 1e-8 {
            output[i] /= windowSum[i]
        }

        if let origLen = originalLength {
            let pad = Self.nFFT / 2
            let start = min(pad, output.count)
            let end = min(start + origLen, output.count)
            return Array(output[start..<end])
        }
        return output
    }
}
