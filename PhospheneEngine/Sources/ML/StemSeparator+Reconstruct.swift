// StemSeparator+Reconstruct — iSTFT reconstruction and mono averaging.
//
// After MPSGraph prediction produces 4 stem × 2 channel magnitude
// spectrograms, this extension applies iSTFT with the original phase
// and averages stereo to mono.
//
// Optimized with vDSP:
// - Mono averaging: vDSP_vadd + vDSP_vsmul

import Accelerate

// MARK: - Reconstruct

extension StemSeparator {

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
                    guard let lPtr = leftBuf.baseAddress,
                          let rPtr = rightBuf.baseAddress,
                          let dPtr = dst.baseAddress else { return }
                    vDSP_vadd(lPtr, 1, rPtr, 1, dPtr, 1, vLen)
                    var half: Float = 0.5
                    vDSP_vsmul(dPtr, 1, &half, dPtr, 1, vLen)
                }
            }
        }

        return mono
    }
}
