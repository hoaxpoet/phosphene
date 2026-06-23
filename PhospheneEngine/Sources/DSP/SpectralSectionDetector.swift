// SpectralSectionDetector — McFee/Ellis Laplacian spectral clustering (SECDET Stage B).
//
// Turns beat-synced section features (SectionFeatures: cqSync 252×N, msSync 13×N)
// into section-boundary times, reproducing tune_corpus.py's `mc(S, "eCq", 5)`:
//   recurrence affinity → timelag median → MFCC path diagonal → μ-balanced fuse →
//   normalized Laplacian → ssyev bottom-k eigenvectors → median(9,1) + cumulative-
//   norm row-normalize → k-means(k=5) → label-change boundaries → enforce_min(8 s).
//
// The McFee algorithm choice (and the 252-CQT-over-chroma finding) is D-170. This is
// the offline/batch detector that replaces the novelty boundary source at Stage C.

import Accelerate
import Foundation

// MARK: - SpectralSectionDetector

struct SpectralSectionDetector {

    /// Number of section types (k). Fixed at 5 per the lab validation (D-170).
    static let k = 5

    /// Minimum section length in seconds (merge shorter sections).
    static let minSectionSeconds = 8.0

    /// Detect section-boundary times (seconds, ascending, including 0 and `duration`).
    ///
    /// - Parameters:
    ///   - features: Beat-synced features from `SectionFeatureExtractor`.
    ///   - segmentStartTimes: Start time (s) of each of the `segmentCount` beat
    ///     segments (segment i begins at sync-boundary i → `boundaryFrame_i·hop/sr`).
    ///   - duration: Track duration in seconds (final boundary).
    /// - Returns: Boundary times, or `[0, duration]` when there's too little data.
    func boundaryTimes(features: SectionFeatures, segmentStartTimes: [Double], duration: Double) -> [Double] {
        let size = features.segmentCount
        guard size >= 2 * RecurrenceGraph.width + 2, segmentStartTimes.count == size else {
            return [0, duration]
        }
        let labels = clusterLabels(features: features, size: size)
        var bounds: [Int] = []
        for i in 0..<(size - 1) where labels[i] != labels[i + 1] { bounds.append(i + 1) }
        return Self.enforceMin(
            segmentStartTimes: segmentStartTimes,
            bounds: bounds,
            duration: duration,
            minLen: Self.minSectionSeconds)
    }

    /// The label per beat segment (exposed for diagnostics/tests).
    func clusterLabels(features: SectionFeatures, size: Int) -> [Int] {
        let recurrence = RecurrenceGraph.affinity(features: features.cqSync, dim: features.cqtBinCount, size: size)
        let filtered = RecurrenceGraph.timelagMedian(recurrence, size: size)
        let path = RecurrenceGraph.pathDiagonal(mfcc: features.msSync, dim: features.mfccCount, size: size)
        let fused = RecurrenceGraph.fuse(recurrence: filtered, path: path, size: size)
        let laplacian = RecurrenceGraph.normalizedLaplacian(fused.matrix, size: size)
        guard let eigen = SymmetricEigen.decompose(matrix: laplacian, size: size) else {
            return [Int](repeating: 0, count: size)
        }
        let embedding = Self.embedding(eigenvectors: eigen.eigenvectors, size: size, k: Self.k)
        return KMeans.cluster(points: embedding, size: size, dim: Self.k, k: Self.k)
    }

    // MARK: - Spectral embedding

    /// `median_filter(ev, size=(9,1))` on the first `k` eigenvectors, then
    /// cumulative-norm row-normalization: `X[i] = evf[i,:k] / ‖evf[i,:k]‖₂`.
    /// `eigenvectors` is row-major `size×size` with `[i*size + j]` = component i of eigvec j.
    /// Returns row-major `size×k`.
    static func embedding(eigenvectors: [Float], size: Int, k: Int, window: Int = 9) -> [Float] {
        let half = window / 2
        var filtered = [Float](repeating: 0, count: size * k)
        var buffer = [Float](repeating: 0, count: window)
        for vec in 0..<k {
            for row in 0..<size {
                for offset in -half...half {
                    var time = row + offset
                    if time < 0 { time = -time - 1 }                 // scipy reflect
                    if time >= size { time = 2 * size - 1 - time }
                    buffer[offset + half] = eigenvectors[time * size + vec]
                }
                buffer.sort()
                filtered[row * k + vec] = buffer[half]
            }
        }
        var out = [Float](repeating: 0, count: size * k)
        for row in 0..<size {
            var sumSq: Float = 0
            for vec in 0..<k { let value = filtered[row * k + vec]; sumSq += value * value }
            let inv = 1 / (sumSq.squareRoot() + 1e-9)
            for vec in 0..<k { out[row * k + vec] = filtered[row * k + vec] * inv }
        }
        return out
    }

    // MARK: - enforce_min

    /// `enforce_min`: merge sections shorter than `minLen`, returning ascending
    /// unique boundary times with `duration` appended. `bounds` are segment
    /// indices where the label changes; `segmentStartTimes[i]` is segment i's start.
    static func enforceMin(segmentStartTimes: [Double], bounds: [Int],
                           duration: Double, minLen: Double) -> [Double] {
        let count = segmentStartTimes.count
        func timeAt(_ index: Int) -> Double { segmentStartTimes[min(index, count - 1)] }
        let sortedBounds = Array(Set(bounds + [0])).sorted()
        var kept = [0]
        var last = 0
        for index in sortedBounds where index != 0 {
            if timeAt(index) - timeAt(last) >= minLen { kept.append(index); last = index }
        }
        var times = Set(kept.map(timeAt))
        times.insert(duration)
        return times.sorted()
    }
}
