// SectionFeatureExtractor — beat-synced 252-CQT + 13-MFCC at 22050 Hz (SECDET Stage A).
//
// Produces the exact feature matrices the validated McFee/Ellis section detector
// consumes (lab spec: precompute.py / tune_corpus.py): frame-level log-CQT (dB) and
// MFCC, then beat-synchronised — median over CQT, mean over MFCC — using librosa's
// util.sync segmentation (boundaries = unique([0] + beats); the final segment runs
// to the end). Stages B/C build the recurrence graph + clustering on `cqSync`.
//
// Input is already-decoded mono 22050 Hz PCM. The full-track decode/resample to
// 22050 (production wiring) and beat-time→frame conversion belong to Stage C; here
// the caller supplies beat frame indices on the hop=512 grid (so Stage A validation
// is isolated from the beat tracker — see SectionFeatureGoldenTests).

import Accelerate
import Foundation

// MARK: - SectionFeatures

/// Beat-synced section features for one track. Matrices are bin-major row-major
/// (`row * cols + col`), matching the lab's `(rows, T/N)` C-order layout.
struct SectionFeatures {
    /// Frame-level log-CQT in dB, `cqtBinCount × frameCount`.
    let cqtDB: [Float]
    /// Frame-level MFCC, `mfccCount × frameCount`.
    let mfcc: [Float]
    /// Beat-synced CQT (median), `cqtBinCount × segmentCount`.
    let cqSync: [Float]
    /// Beat-synced MFCC (mean), `mfccCount × segmentCount`.
    let msSync: [Float]

    let cqtBinCount: Int
    let mfccCount: Int
    let frameCount: Int
    let segmentCount: Int
}

// MARK: - SectionFeatureExtractor

/// Computes beat-synced CQT + MFCC for offline section analysis.
struct SectionFeatureExtractor {

    private let cqt = ConstantQTransform()
    private let mfccProc = MFCCProcessor()

    /// Extract beat-synced features.
    ///
    /// - Parameters:
    ///   - samples22k: Mono Float32 PCM at 22050 Hz (full track).
    ///   - beatFrames: Beat positions as frame indices on the hop=512 grid.
    func extract(samples22k: [Float], beatFrames: [Int]) -> SectionFeatures {
        let (cqtDB, tCQT) = cqt.dbMatrix(samples: samples22k)
        let (mfcc, tMFCC) = mfccProc.matrix(samples: samples22k)
        let frames = min(tCQT, tMFCC)

        let bounds = Self.syncBoundaries(beatFrames: beatFrames, frameCount: frames)
        let cqSync = Self.aggregate(
            cqtDB, rows: ConstantQTransform.binCount, cols: tCQT, bounds: bounds, median: true)
        let msSync = Self.aggregate(
            mfcc, rows: MFCCProcessor.nMFCC, cols: tMFCC, bounds: bounds, median: false)

        return SectionFeatures(
            cqtDB: cqtDB,
            mfcc: mfcc,
            cqSync: cqSync,
            msSync: msSync,
            cqtBinCount: ConstantQTransform.binCount,
            mfccCount: MFCCProcessor.nMFCC,
            frameCount: frames,
            segmentCount: max(0, bounds.count - 1)
        )
    }

    // MARK: - Beat-sync (librosa.util.sync)

    /// Segment boundaries matching `librosa.util.sync(..., idx=beats)`:
    /// `sorted(unique({0} ∪ beats))` clamped to `[0, frameCount]`, with
    /// `frameCount` appended so the final segment extends to the end. The number
    /// of segments equals the count of distinct beat-derived boundaries.
    static func syncBoundaries(beatFrames: [Int], frameCount: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        var set = Set<Int>([0])
        for beat in beatFrames where beat >= 0 && beat < frameCount { set.insert(beat) }
        var bounds = set.sorted()
        bounds.append(frameCount)          // final segment runs to T
        return bounds
    }

    /// Aggregate feature columns within each segment. `median=true` → per-row
    /// median (np.median, even-count averages the two middle values);
    /// `median=false` → per-row mean. Output is bin-major (`rows × segments`).
    static func aggregate(_ data: [Float], rows: Int, cols: Int,
                          bounds: [Int], median: Bool) -> [Float] {
        let segs = max(0, bounds.count - 1)
        guard segs > 0 else { return [] }
        var out = [Float](repeating: 0, count: rows * segs)
        var scratch = [Float]()
        for seg in 0..<segs {
            let lo = min(bounds[seg], cols)
            let hi = min(bounds[seg + 1], cols)
            let cnt = max(0, hi - lo)
            for row in 0..<rows {
                let rowBase = row * cols
                if cnt == 0 {
                    out[row * segs + seg] = 0
                } else if median {
                    scratch.removeAll(keepingCapacity: true)
                    scratch.append(contentsOf: data[(rowBase + lo)..<(rowBase + hi)])
                    scratch.sort()
                    out[row * segs + seg] = cnt % 2 == 1
                        ? scratch[cnt / 2]
                        : 0.5 * (scratch[cnt / 2 - 1] + scratch[cnt / 2])
                } else {
                    var mean: Float = 0
                    data.withUnsafeBufferPointer { ptr in
                        // swiftlint:disable:next force_unwrapping
                        vDSP_meanv(ptr.baseAddress! + rowBase + lo, 1, &mean, vDSP_Length(cnt))
                    }
                    out[row * segs + seg] = mean
                }
            }
        }
        return out
    }
}
