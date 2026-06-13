// StemSeparator+ModelIO — Model output-buffer read helper.
//
// Extracted from `StemSeparator.separate()` (the Step 6 output read) so that
// method stays within SwiftLint's `function_body_length` / `file_length`
// budgets after the CLEAN.1.1 BUG-031 ownership instrumentation was added.
// Pure data marshalling: copies each stem's L/R magnitude spectrogram out of
// the shared `StemModelEngine` output buffers into owned `[Float]` arrays.

import Foundation
import Metal

// MARK: - Model Output Read

extension StemSeparator {

    /// Copy the four stems' L/R magnitude spectrograms out of the model's
    /// shared output buffers into per-stem `[Float]` arrays.
    ///
    /// `static` and parameterized on `outputBuffers` so it does not capture the
    /// separator's private `stemModel`; the caller passes `stemModel.outputBuffers`.
    ///
    /// - Parameters:
    ///   - outputBuffers: Per-stem `(magL, magR)` UMA buffers from `StemModelEngine`.
    ///   - elemCount: Floats per channel (`nbFrames * nBins`).
    /// - Returns: `(magL, magR)` — each a `stemCount`-element array of magnitude arrays.
    static func readStemMagnitudes(
        outputBuffers: [(magL: MTLBuffer, magR: MTLBuffer)],
        elemCount: Int
    ) -> (magL: [[Float]], magR: [[Float]]) {
        var allStemMagL = [[Float]]()
        var allStemMagR = [[Float]]()
        allStemMagL.reserveCapacity(stemCount)
        allStemMagR.reserveCapacity(stemCount)

        for stem in 0..<stemCount {
            let outL = outputBuffers[stem].magL.contents().assumingMemoryBound(to: Float.self)
            let outR = outputBuffers[stem].magR.contents().assumingMemoryBound(to: Float.self)
            allStemMagL.append(Array(UnsafeBufferPointer(start: outL, count: elemCount)))
            allStemMagR.append(Array(UnsafeBufferPointer(start: outR, count: elemCount)))
        }

        return (allStemMagL, allStemMagR)
    }
}
