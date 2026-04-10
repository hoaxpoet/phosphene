// StemSeparator+Pack — CoreML spectrogram packing/unpacking and iSTFT reconstruction.

import CoreML

// MARK: - Spectrogram Packing / Unpacking

extension StemSeparator {

    /// Pack left/right magnitude spectrograms into CoreML input format.
    ///
    /// Uses MLShapedArray for stride-safe access to the backing buffer.
    ///
    /// - Parameters:
    ///   - magL: Left channel magnitude (nBins * nbFrames), stored as [frame][bin].
    ///   - magR: Right channel magnitude (nBins * nbFrames), stored as [frame][bin].
    ///   - nbFrames: Number of STFT frames.
    /// - Returns: MLMultiArray of shape [1, 2, 2049, nbFrames].
    func packSpectrogramForModel(
        magL: [Float], magR: [Float], nbFrames: Int
    ) throws -> MLMultiArray {
        let shape = [1, 2, Self.nBins, nbFrames]
        var shaped = MLShapedArray<Float>(repeating: 0, shape: shape)

        // Write via withUnsafeMutableShapedBufferPointer — handles padded strides correctly.
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

    /// Extract 4-stem × 2-channel magnitude spectrograms from the CoreML output.
    private func extractStemSpectrograms(
        output: MLMultiArray,
        nbFrames: Int
    ) -> (left: [[Float]], right: [[Float]]) {
        let binsPerFrame = Self.nBins

        let shaped = MLShapedArray<Float>(converting: output)

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

                for bin in 0..<binsPerFrame {
                    let freqOff = bin * strides[2]
                    for frame in 0..<nbFrames {
                        let localIdx = frame * binsPerFrame + bin
                        let timeOff = frame * strides[3]
                        allStemMagL[stem][localIdx] = ptr[leftBase + freqOff + timeOff]
                        allStemMagR[stem][localIdx] = ptr[rightBase + freqOff + timeOff]
                    }
                }
            }
        }

        return (allStemMagL, allStemMagR)
    }

    /// iSTFT each stem's L/R channels with original phase, average to mono.
    private func reconstructStemWaveforms(
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

            // Average to mono.
            let monoCount = min(waveL.count, waveR.count)
            var mono = [Float](repeating: 0, count: monoCount)
            for idx in 0..<monoCount {
                mono[idx] = (waveL[idx] + waveR[idx]) * 0.5
            }

            stemWaveforms.append(mono)
        }

        return stemWaveforms
    }
}
