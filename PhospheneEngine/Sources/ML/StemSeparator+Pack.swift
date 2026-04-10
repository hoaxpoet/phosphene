// StemSeparator+Pack — CoreML spectrogram packing/unpacking and iSTFT reconstruction.
//
// Optimized in Increment 3.1a-followup:
// - Pack: raw MLMultiArray.dataPointer + vDSP_mtrans (bypasses MLShapedArray alloc)
// - Unpack: MLShapedArray(converting:) for Float16→Float32, then vDSP_mtrans
//   for [bin][frame] → [frame][bin] transpose (replaces scalar nested loops)
// - Mono averaging: vDSP_vadd + vDSP_vsmul
// - UMABuffer.write: memcpy via Float-specialized overload

import Accelerate
import CoreML

// MARK: - Spectrogram Packing

extension StemSeparator {

    /// Pack left/right magnitude spectrograms into CoreML input format.
    ///
    /// Creates an MLMultiArray of shape [1, 2, 2049, nbFrames] and fills it
    /// via `vDSP_mtrans` to transpose each channel from [frame][bin] to
    /// [bin][frame] layout. Writes directly to the MLMultiArray's backing
    /// buffer when strides are dense (verified at runtime).
    ///
    /// - Parameters:
    ///   - magL: Left channel magnitude (nBins * nbFrames), stored as [frame][bin].
    ///   - magR: Right channel magnitude (nBins * nbFrames), stored as [frame][bin].
    ///   - nbFrames: Number of STFT frames.
    /// - Returns: MLMultiArray of shape [1, 2, 2049, nbFrames].
    func packSpectrogramForModel(
        magL: [Float], magR: [Float], nbFrames: Int
    ) throws -> MLMultiArray {
        let shape: [NSNumber] = [1, 2, NSNumber(value: Self.nBins), NSNumber(value: nbFrames)]
        let array = try MLMultiArray(shape: shape, dataType: .float32)

        let perChannel = Self.nBins * nbFrames
        let strides = array.strides.map { $0.intValue }

        if isDensePackLayout(strides: strides, nbFrames: nbFrames, perChannel: perChannel) {
            packDense(magL: magL, magR: magR, nbFrames: nbFrames, into: array, perChannel: perChannel)
        } else {
            packStrided(magL: magL, magR: magR, nbFrames: nbFrames, into: array)
        }

        return array
    }
}

// MARK: - Pack Helpers

private extension StemSeparator {

    func isDensePackLayout(strides: [Int], nbFrames: Int, perChannel: Int) -> Bool {
        strides[3] == 1 && strides[2] == nbFrames
            && strides[1] == perChannel && strides[0] == 2 * perChannel
    }

    func packDense(
        magL: [Float], magR: [Float], nbFrames: Int,
        into array: MLMultiArray, perChannel: Int
    ) {
        let dst = array.dataPointer.assumingMemoryBound(to: Float.self)
        let nBins = vDSP_Length(Self.nBins)
        let nFrames = vDSP_Length(nbFrames)

        magL.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            vDSP_mtrans(srcBase, 1, dst, 1, nBins, nFrames)
        }
        magR.withUnsafeBufferPointer { src in
            guard let srcBase = src.baseAddress else { return }
            vDSP_mtrans(srcBase, 1, dst.advanced(by: perChannel), 1, nBins, nFrames)
        }
    }

    func packStrided(
        magL: [Float], magR: [Float], nbFrames: Int, into array: MLMultiArray
    ) {
        var shaped = MLShapedArray<Float>(converting: array)
        shaped.withUnsafeMutableShapedBufferPointer { ptr, _, strides in
            for bin in 0..<Self.nBins {
                for frame in 0..<nbFrames {
                    let srcIdx = frame * Self.nBins + bin
                    let leftIdx = bin * strides[2] + frame * strides[3]
                    let rightIdx = strides[1] + bin * strides[2] + frame * strides[3]
                    ptr[leftIdx] = magL[srcIdx]
                    ptr[rightIdx] = magR[srcIdx]
                }
            }
        }
    }
}

// MARK: - Spectrogram Unpacking + iSTFT

extension StemSeparator {

    /// Unpack CoreML output and apply iSTFT to reconstruct stem waveforms.
    func unpackAndISTFT(
        output: MLMultiArray,
        phaseL: [Float],
        phaseR: [Float],
        nbFrames: Int
    ) throws -> [[Float]] {
        let (allStemMagL, allStemMagR) = extractStemSpectrograms(
            output: output,
            nbFrames: nbFrames
        )
        return reconstructStemWaveforms(
            allStemMagL: allStemMagL,
            allStemMagR: allStemMagR,
            phaseL: phaseL,
            phaseR: phaseR,
            nbFrames: nbFrames
        )
    }
}

// MARK: - Extract

private extension StemSeparator {

    /// Extract 4-stem × 2-channel magnitude spectrograms from the CoreML output.
    ///
    /// The ANE typically outputs Float16. `MLShapedArray<Float>(converting:)`
    /// handles the type conversion. When the converted buffer has dense
    /// strides, we transpose each stem/channel block from [bin][frame] to
    /// [frame][bin] via a single `vDSP_mtrans` call per block.
    func extractStemSpectrograms(
        output: MLMultiArray,
        nbFrames: Int
    ) -> (left: [[Float]], right: [[Float]]) {
        let perChannel = Self.nBins * nbFrames

        var allStemMagL = [[Float]](
            repeating: [Float](repeating: 0, count: perChannel),
            count: Self.stemCount
        )
        var allStemMagR = [[Float]](
            repeating: [Float](repeating: 0, count: perChannel),
            count: Self.stemCount
        )

        let shaped = MLShapedArray<Float>(converting: output)

        shaped.withUnsafeShapedBufferPointer { ptr, _, strides in
            if strides[3] == 1 && strides[2] == nbFrames {
                extractDense(
                    ptr: ptr,
                    strides: strides,
                    nbFrames: nbFrames,
                    magL: &allStemMagL,
                    magR: &allStemMagR
                )
            } else {
                extractStrided(
                    ptr: ptr,
                    strides: strides,
                    nbFrames: nbFrames,
                    magL: &allStemMagL,
                    magR: &allStemMagR
                )
            }
        }

        return (allStemMagL, allStemMagR)
    }

    /// Dense fast path: direct vDSP_mtrans from the converted buffer.
    func extractDense(
        ptr: UnsafeBufferPointer<Float>,
        strides: [Int],
        nbFrames: Int,
        magL: inout [[Float]],
        magR: inout [[Float]]
    ) {
        guard let base = ptr.baseAddress else { return }
        let nFrames = vDSP_Length(nbFrames)
        let nBins = vDSP_Length(Self.nBins)

        for stem in 0..<Self.stemCount {
            let stemBase = stem * strides[0]

            magL[stem].withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress else { return }
                vDSP_mtrans(base.advanced(by: stemBase), 1, dstBase, 1, nFrames, nBins)
            }

            magR[stem].withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress else { return }
                let src = base.advanced(by: stemBase + strides[1])
                vDSP_mtrans(src, 1, dstBase, 1, nFrames, nBins)
            }
        }
    }

    /// Strided fallback: scalar element-by-element reads.
    func extractStrided(
        ptr: UnsafeBufferPointer<Float>,
        strides: [Int],
        nbFrames: Int,
        magL: inout [[Float]],
        magR: inout [[Float]]
    ) {
        let binsPerFrame = Self.nBins
        for stem in 0..<Self.stemCount {
            let stemBase = stem * strides[0]
            let leftBase = stemBase
            let rightBase = stemBase + strides[1]

            for bin in 0..<binsPerFrame {
                let freqOff = bin * strides[2]
                for frame in 0..<nbFrames {
                    let localIdx = frame * binsPerFrame + bin
                    let timeOff = frame * strides[3]
                    magL[stem][localIdx] = ptr[leftBase + freqOff + timeOff]
                    magR[stem][localIdx] = ptr[rightBase + freqOff + timeOff]
                }
            }
        }
    }
}

// MARK: - Reconstruct

private extension StemSeparator {

    /// iSTFT each stem's L/R channels with original phase, average to mono.
    ///
    /// Uses `vDSP_vadd` and `vDSP_vsmul` for the L+R mono averaging.
    func reconstructStemWaveforms(
        allStemMagL: [[Float]],
        allStemMagR: [[Float]],
        phaseL: [Float],
        phaseR: [Float],
        nbFrames: Int
    ) -> [[Float]] {
        var stemWaveforms = [[Float]]()
        stemWaveforms.reserveCapacity(Self.stemCount)

        for stem in 0..<Self.stemCount {
            let waveL = istft(
                magnitude: allStemMagL[stem],
                phase: phaseL,
                nbFrames: nbFrames,
                originalLength: Self.requiredMonoSamples
            )
            let waveR = istft(
                magnitude: allStemMagR[stem],
                phase: phaseR,
                nbFrames: nbFrames,
                originalLength: Self.requiredMonoSamples
            )

            stemWaveforms.append(averageToMono(left: waveL, right: waveR))
        }

        return stemWaveforms
    }

    /// Average stereo to mono via vDSP.
    func averageToMono(left: [Float], right: [Float]) -> [Float] {
        let count = min(left.count, right.count)
        var mono = [Float](repeating: 0, count: count)
        let vLen = vDSP_Length(count)

        left.withUnsafeBufferPointer { leftBuf in
            right.withUnsafeBufferPointer { rightBuf in
                mono.withUnsafeMutableBufferPointer { dst in
                    guard let lp = leftBuf.baseAddress,
                          let rp = rightBuf.baseAddress,
                          let dp = dst.baseAddress else { return }
                    vDSP_vadd(lp, 1, rp, 1, dp, 1, vLen)
                    var half: Float = 0.5
                    vDSP_vsmul(dp, 1, &half, dp, 1, vLen)
                }
            }
        }

        return mono
    }
}
