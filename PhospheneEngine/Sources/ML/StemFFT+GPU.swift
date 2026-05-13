// StemFFT+GPU — MPSGraph-backed forward and inverse STFT.
//
// Split out of `StemFFT.swift` to keep each file under the 400-line
// SwiftLint warning. The public API and engine lifecycle live in the
// main file; this extension owns the GPU fast-path for the fixed
// 10-second / 431-frame window that `StemSeparator` uses.

import Accelerate
import Foundation
import Metal
import MetalPerformanceShadersGraph

extension StemFFTEngine {

    // MARK: - GPU Forward

    internal func gpuForward(mono: [Float]) -> (magnitude: [Float], phase: [Float]) {
        // The GPU graph is built for exactly `modelFrameCount` frames.
        // Inputs that produce a different frame count (e.g. tiny test clips)
        // fall back to the CPU path rather than re-compiling the graph.
        let pad = Self.nFFT / 2
        let paddedCount = mono.count + 2 * pad
        let nbFrames = (paddedCount - Self.nFFT) / Self.hopLength + 1
        if nbFrames != Self.modelFrameCount {
            return cpuForward(mono: mono)
        }

        packForwardInput(mono: mono)
        runForwardGraph()

        // Read magnitudes/phases back from UMA buffers and convert to the
        // vDSP-equivalent convention (see `computeMagnitudePhase`).
        let totalBins = Self.modelFrameCount * Self.nBins
        var magnitude = [Float](repeating: 0, count: totalBins)
        var phase = [Float](repeating: 0, count: totalBins)
        let realPtr = forwardRealBuffer.contents().bindMemory(to: Float.self, capacity: totalBins)
        let imagPtr = forwardImagBuffer.contents().bindMemory(to: Float.self, capacity: totalBins)

        computeMagnitudePhase(
            real: realPtr,
            imag: imagPtr,
            nbFrames: Self.modelFrameCount,
            magnitude: &magnitude,
            phase: &phase
        )

        return (magnitude, phase)
    }

    /// Center-pad, window, and write `mono` into the forward UMA input buffer.
    private func packForwardInput(mono: [Float]) {
        let pad = Self.nFFT / 2
        let inPtr = forwardInputBuffer.contents().bindMemory(
            to: Float.self, capacity: Self.modelFrameCount * Self.nFFT
        )
        var padded = [Float](repeating: 0, count: mono.count + 2 * pad)
        mono.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            padded.withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress else { return }
                (dstBase + pad).update(from: base, count: mono.count)
            }
        }
        window.withUnsafeBufferPointer { winPtr in
            guard let winBase = winPtr.baseAddress else { return }
            padded.withUnsafeBufferPointer { padPtr in
                guard let padBase = padPtr.baseAddress else { return }
                for frame in 0..<Self.modelFrameCount {
                    let src = padBase + frame * Self.hopLength
                    let dst = inPtr + frame * Self.nFFT
                    vDSP_vmul(src, 1, winBase, 1, dst, 1, vDSP_Length(Self.nFFT))
                }
            }
        }
    }

    /// Execute the forward MPSGraph, writing into `forwardRealBuffer` and
    /// `forwardImagBuffer`.
    private func runForwardGraph() {
        let inputShape: [NSNumber] = [
            NSNumber(value: Self.modelFrameCount),
            NSNumber(value: Self.nFFT)
        ]
        let binsShape: [NSNumber] = [
            NSNumber(value: Self.modelFrameCount),
            NSNumber(value: Self.nBins)
        ]

        let inputData = MPSGraphTensorData(forwardInputBuffer, shape: inputShape, dataType: .float32)
        let realOutData = MPSGraphTensorData(forwardRealBuffer, shape: binsShape, dataType: .float32)
        let imagOutData = MPSGraphTensorData(forwardImagBuffer, shape: binsShape, dataType: .float32)

        // `MPSGraph.run(with:feeds:targetOperations:resultsDictionary:)` blocks
        // until the command buffer completes and writes directly into the
        // result `MPSGraphTensorData` buffers (zero-copy UMA).
        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [forwardInputTensor: inputData]
        let targets: [MPSGraphTensor: MPSGraphTensorData] = [
            forwardRealOutput: realOutData,
            forwardImagOutput: imagOutData
        ]
        forwardGraph.run(
            with: commandQueue,
            feeds: feeds,
            targetOperations: nil,
            resultsDictionary: targets
        )
    }

    /// Convert MPSGraph's standard-DFT real/imag output into magnitude +
    /// phase values that match the CPU vDSP reference exactly.
    ///
    /// vDSP's `fft_zrip` returns twice the standard DFT across all bins
    /// (including DC and Nyquist), so we multiply MPSGraph's output by 2
    /// before dividing by `nFFT`. This convention is internal to the
    /// engine — downstream callers (StemSeparator, the MPSGraph model) are
    /// insensitive to the absolute amplitude because the STFT/iSTFT pair
    /// round-trips with matching conventions on both ends.
    ///
    /// The heavy lifting is done via vDSP (`vDSP_zvabs` for
    /// `sqrt(re^2 + im^2)`) and vForce (`vvatan2f` for phase), processing
    /// the full `nbFrames × nBins` grid in a single call each.
    private func computeMagnitudePhase(
        real: UnsafePointer<Float>,
        imag: UnsafePointer<Float>,
        nbFrames: Int,
        magnitude: inout [Float],
        phase: inout [Float]
    ) {
        let totalBins = nbFrames * Self.nBins
        let scale: Float = 2.0 / Float(Self.nFFT)

        magnitude.withUnsafeMutableBufferPointer { magBuf in
            phase.withUnsafeMutableBufferPointer { phaseBuf in
                guard let magBase = magBuf.baseAddress,
                      let phaseBase = phaseBuf.baseAddress else { return }

                // Magnitude = sqrt(re^2 + im^2), fused for the whole batch.
                var splitMutable = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: real),
                    imagp: UnsafeMutablePointer(mutating: imag)
                )
                vDSP_zvabs(&splitMutable, 1, magBase, 1, vDSP_Length(totalBins))

                // Apply the 2/nFFT scaling in place.
                var scaleVar = scale
                vDSP_vsmul(magBase, 1, &scaleVar, magBase, 1, vDSP_Length(totalBins))

                // Phase = atan2(im, re) over the whole batch.
                var count = Int32(totalBins)
                vvatan2f(phaseBase, imag, real, &count)
            }
        }
    }

    // MARK: - GPU Inverse

    internal func gpuInverse(
        magnitude: [Float], phase: [Float], nbFrames: Int, originalLength: Int?
    ) -> [Float] {
        // Only the fixed-size path runs on the GPU. Unusual sizes use CPU.
        if nbFrames != Self.modelFrameCount {
            return cpuInverse(
                magnitude: magnitude, phase: phase, nbFrames: nbFrames, originalLength: originalLength
            )
        }

        packInverseInputs(magnitude: magnitude, phase: phase)
        runInverseGraph()
        let output = overlapAddAndNormalize()

        // Strip center padding if an original length was supplied.
        if let origLen = originalLength {
            let pad = Self.nFFT / 2
            let start = min(pad, output.count)
            let end = min(start + origLen, output.count)
            return Array(output[start..<end])
        }
        return output
    }

    /// Pack magnitude/phase into the real/imag input buffers of the
    /// inverse graph.
    ///
    /// Scaling: the forward path scales magnitudes by `2/nFFT` (to match
    /// vDSP's doubled convention). To recover a standard-DFT spectrum we
    /// must multiply by `nFFT/2` — then `HermiteanToRealFFT` with
    /// `scalingMode = .size` applies its own `1/nFFT` factor, and the
    /// net round-trip gain is unity.
    private func packInverseInputs(magnitude: [Float], phase: [Float]) {
        let totalBins = Self.modelFrameCount * Self.nBins
        let realPtr = inverseRealBuffer.contents().bindMemory(to: Float.self, capacity: totalBins)
        let imagPtr = inverseImagBuffer.contents().bindMemory(to: Float.self, capacity: totalBins)

        // sin/cos of the entire phase grid in one pass.
        var count = Int32(totalBins)
        phase.withUnsafeBufferPointer { phasePtr in
            guard let phaseBase = phasePtr.baseAddress else { return }
            vvsincosf(imagPtr, realPtr, phaseBase, &count)
        }

        // Multiply by magnitude * (nFFT / 2) across the whole grid.
        var amp: Float = Float(Self.nFFT) / 2
        magnitude.withUnsafeBufferPointer { magPtr in
            guard let magBase = magPtr.baseAddress else { return }
            vDSP_vmul(magBase, 1, realPtr, 1, realPtr, 1, vDSP_Length(totalBins))
            vDSP_vsmul(realPtr, 1, &amp, realPtr, 1, vDSP_Length(totalBins))
            vDSP_vmul(magBase, 1, imagPtr, 1, imagPtr, 1, vDSP_Length(totalBins))
            vDSP_vsmul(imagPtr, 1, &amp, imagPtr, 1, vDSP_Length(totalBins))
        }

        // Force the imaginary component of the DC and Nyquist bins to zero
        // for each frame — those bins represent real-valued components of a
        // Hermitean spectrum; any non-zero imag leaked in via numerical
        // noise would just get thrown away by HermiteanToRealFFT, but clean
        // inputs match the CPU path byte-for-byte.
        let halfN = Self.nFFT / 2
        for frame in 0..<Self.modelFrameCount {
            let binOffset = frame * Self.nBins
            imagPtr[binOffset] = 0
            imagPtr[binOffset + halfN] = 0
        }
    }

    /// Run the inverse MPSGraph with the pre-populated real/imag buffers
    /// and write the time-domain result into `inverseOutputBuffer`.
    private func runInverseGraph() {
        let binsShape: [NSNumber] = [
            NSNumber(value: Self.modelFrameCount),
            NSNumber(value: Self.nBins)
        ]
        let outShape: [NSNumber] = [
            NSNumber(value: Self.modelFrameCount),
            NSNumber(value: Self.nFFT)
        ]
        let realInData = MPSGraphTensorData(
            inverseRealBuffer, shape: binsShape, dataType: .float32
        )
        let imagInData = MPSGraphTensorData(
            inverseImagBuffer, shape: binsShape, dataType: .float32
        )
        let outData = MPSGraphTensorData(
            inverseOutputBuffer, shape: outShape, dataType: .float32
        )

        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            inverseRealInput: realInData,
            inverseImagInput: imagInData
        ]
        let targets: [MPSGraphTensor: MPSGraphTensorData] = [inverseRealOutput: outData]
        inverseGraph.run(
            with: commandQueue,
            feeds: feeds,
            targetOperations: nil,
            resultsDictionary: targets
        )
    }

    /// CPU-side overlap-add of the inverse graph output.
    ///
    /// Each frame is multiplied by the Hann window (via `vDSP_vmul`) then
    /// added into the output buffer with `vDSP_vadd`. The normalization
    /// by the precomputed window-square sum uses `vDSP_vdiv`.
    private func overlapAddAndNormalize() -> [Float] {
        let outLength = (Self.modelFrameCount - 1) * Self.hopLength + Self.nFFT
        var output = [Float](repeating: 0, count: outLength)
        let outPtr = inverseOutputBuffer.contents().bindMemory(
            to: Float.self, capacity: Self.modelFrameCount * Self.nFFT
        )
        var scratch = [Float](repeating: 0, count: Self.nFFT)

        output.withUnsafeMutableBufferPointer { outBuf in
            guard let outBase = outBuf.baseAddress else { return }
            window.withUnsafeBufferPointer { winPtr in
                guard let winBase = winPtr.baseAddress else { return }
                scratch.withUnsafeMutableBufferPointer { scratchBuf in
                    guard let scratchBase = scratchBuf.baseAddress else { return }
                    for frame in 0..<Self.modelFrameCount {
                        let framePtr = outPtr + frame * Self.nFFT
                        vDSP_vmul(
                            framePtr, 1, winBase, 1, scratchBase, 1, vDSP_Length(Self.nFFT)
                        )
                        let dst = outBase + frame * Self.hopLength
                        vDSP_vadd(
                            dst, 1, scratchBase, 1, dst, 1, vDSP_Length(Self.nFFT)
                        )
                    }
                }
            }

            // Normalize by the precomputed window-square sum. Indices where
            // wsum is near zero contribute negligible output and we rely on
            // the upstream zero-padding of the signal to keep them benign.
            windowSquareSum.withUnsafeBufferPointer { wsumPtr in
                guard let wsumBase = wsumPtr.baseAddress else { return }
                vDSP_vdiv(wsumBase, 1, outBase, 1, outBase, 1, vDSP_Length(outLength))
            }
        }

        return output
    }
}
