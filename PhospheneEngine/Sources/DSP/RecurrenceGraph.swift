// RecurrenceGraph — McFee/Ellis affinity construction (SECDET Stage B).
//
// Ports the deterministic graph stages of tune_corpus.py's `mcfee_eig`, each
// replicating its librosa/scipy counterpart exactly (validated vs golden):
//   • affinity        = recurrence_matrix(Cq, width=3, mode=affinity, sym=True)
//   • timelagMedian   = timelag_filter(median_filter)(R, size=(1,7))
//   • pathDiagonal    = exp(-‖ΔMs‖²/median) on the sub/super-diagonal
//   • fuse            = μ-balanced  A = μ·Rf + (1-μ)·Rp
//   • normalizedLaplacian = csgraph.laplacian(A, normed=True)
//
// All matrices are dense row-major size×size (size = beat count ≈ 300–600, so dense is fine).

import Accelerate
import Foundation

// MARK: - RecurrenceGraph

enum RecurrenceGraph {

    static let width = 3

    // MARK: - Recurrence affinity

    /// `librosa.segment.recurrence_matrix(features, width=3, mode='affinity', sym=True)`.
    ///
    /// Mutual k-NN on sqeuclidean distances between the `size` feature columns
    /// (`features` is `dim × size`, row-major), excluding the `|i−j| < 3` band;
    /// `R[i,j] = exp(−d_ij / bandwidth)` for mutual neighbours, else 0, symmetric.
    /// `bandwidth` = median over rows of the k-th surviving neighbour distance
    /// (librosa's `med_k_scalar`). `k = 2·ceil(√(size−5))`.
    static func affinity(features: [Float], dim: Int, size: Int) -> [Float] {
        guard size >= 2 else { return [Float](repeating: 0, count: size * size) }
        let kVal = max(1, 2 * Int(ceil((Double(max(1, size - 2 * width + 1))).squareRoot())))
        let nNeighbors = min(size - 1, kVal + 2 * width)

        // Gram = Fᵀ·F (size×size) → sqeuclidean d_ij = ‖f_i‖² + ‖f_j‖² − 2·gram_ij.
        var gram = [Float](repeating: 0, count: size * size)
        let dimI = Int32(dim)
        let sizeI = Int32(size)
        features.withUnsafeBufferPointer { feat in
            // swiftlint:disable:next line_length
            cblas_sgemm(CblasRowMajor, CblasTrans, CblasNoTrans, sizeI, sizeI, dimI, 1, feat.baseAddress, sizeI, feat.baseAddress, sizeI, 0, &gram, sizeI)
        }
        let norms = (0..<size).map { gram[$0 * size + $0] }
        func dist(_ row: Int, _ col: Int) -> Float {
            max(0, norms[row] + norms[col] - 2 * gram[row * size + col])
        }

        // Asymmetric keep-mask: top-nNeighbors candidates → drop |i−j|<3 → keep k nearest.
        var keep = [Bool](repeating: false, count: size * size)
        var rowDist = [(dist: Float, col: Int)](repeating: (0, 0), count: size)
        for row in 0..<size {
            for col in 0..<size { rowDist[col] = (dist(row, col), col) }
            rowDist.sort { $0.dist < $1.dist }
            var kept = 0
            for rank in 0..<min(nNeighbors, size) where abs(row - rowDist[rank].col) >= width {
                keep[row * size + rowDist[rank].col] = true
                kept += 1
                if kept >= kVal { break }
            }
        }

        // Mutual NN + med_k_scalar bandwidth (k-th surviving distance, median over rows).
        var distToK: [Float] = []
        var mutual = [Bool](repeating: false, count: size * size)
        for row in 0..<size {
            var surviving: [Float] = []
            for col in 0..<size where keep[row * size + col] && keep[col * size + row] {
                mutual[row * size + col] = true
                surviving.append(dist(row, col))
            }
            if !surviving.isEmpty {
                surviving.sort()
                distToK.append(surviving[min(surviving.count, kVal) - 1])
            }
        }
        let bandwidth = median(distToK)
        let invBw = bandwidth > 0 ? 1.0 / bandwidth : 0

        var matrix = [Float](repeating: 0, count: size * size)
        for idx in 0..<(size * size) where mutual[idx] {
            matrix[idx] = expf(-dist(idx / size, idx % size) * invBw)
        }
        return matrix
    }

    // MARK: - Timelag median filter

    /// `timelag_filter(median_filter)(R, size=(1,7))`: a window-7 median along each
    /// diagonal of `R` (constant `i−j`). Boundary handling matches librosa's
    /// `pad=True` lag conversion + scipy reflect: the time index reflects into
    /// `[0,size)`, and lag indices that leave the matrix contribute 0.
    static func timelagMedian(_ matrix: [Float], size: Int, window: Int = 7) -> [Float] {
        let half = window / 2
        var out = [Float](repeating: 0, count: size * size)
        var buffer = [Float](repeating: 0, count: window)
        for row in 0..<size {
            for col in 0..<size {
                for offset in -half...half {
                    var time = col + offset
                    if time < 0 { time = -time - 1 }                 // reflect low
                    if time >= size { time = 2 * size - 1 - time }         // reflect high
                    let lagRow = (row - col) + time
                    buffer[offset + half] = (lagRow >= 0 && lagRow < size && time >= 0 && time < size)
                        ? matrix[lagRow * size + time] : 0
                }
                buffer.sort()
                out[row * size + col] = buffer[half]                    // odd window → middle
            }
        }
        return out
    }

    // MARK: - Path (sequence) diagonal

    /// `Rp = diag(ps,1) + diag(ps,-1)` where `ps[t] = exp(−‖ΔMs_t‖² / median)`.
    static func pathDiagonal(mfcc: [Float], dim: Int, size: Int) -> [Float] {
        var matrix = [Float](repeating: 0, count: size * size)
        guard size >= 2 else { return matrix }
        var pathDist = [Float](repeating: 0, count: size - 1)
        for time in 0..<(size - 1) {
            var sum: Float = 0
            for component in 0..<dim {
                let diff = mfcc[component * size + (time + 1)] - mfcc[component * size + time]
                sum += diff * diff
            }
            pathDist[time] = sum
        }
        let med = median(pathDist) + 1e-9
        for time in 0..<(size - 1) {
            let sim = expf(-pathDist[time] / med)
            matrix[time * size + (time + 1)] = sim
            matrix[(time + 1) * size + time] = sim
        }
        return matrix
    }

    // MARK: - μ-balanced fuse

    /// `mu = dp·(dp+dr) / Σ(dp+dr)²`; `A = μ·Rf + (1−μ)·Rp`.
    static func fuse(recurrence: [Float], path: [Float], size: Int) -> (matrix: [Float], mu: Float) {
        var degPath = [Float](repeating: 0, count: size)
        var degRec = [Float](repeating: 0, count: size)
        for row in 0..<size {
            var sumPath: Float = 0
            var sumRec: Float = 0
            for col in 0..<size { sumPath += path[row * size + col]; sumRec += recurrence[row * size + col] }
            degPath[row] = sumPath
            degRec[row] = sumRec
        }
        var num: Float = 0
        var den: Float = 0
        for row in 0..<size {
            let total = degPath[row] + degRec[row]
            num += degPath[row] * total
            den += total * total
        }
        let mu = num / (den + 1e-9)
        var matrix = [Float](repeating: 0, count: size * size)
        for idx in 0..<(size * size) { matrix[idx] = mu * recurrence[idx] + (1 - mu) * path[idx] }
        return (matrix, mu)
    }

    // MARK: - Normalized Laplacian

    /// `csgraph.laplacian(A, normed=True)` = `I − D^-½ A D^-½`. Isolated nodes
    /// (degree 0) get a 0 diagonal (scipy convention), not 1.
    ///
    /// The input is symmetrized first: the timelag filter leaves A marginally
    /// asymmetric near the time boundaries (≤0.05, a reflect-padding artifact, not
    /// signal). scipy/eigh keep the asymmetry and, at a near-isolated node, produce
    /// huge ill-conditioned eigenvalues whose value depends on a sub-float32 degree
    /// — irreproducible and unused. Averaging makes the Laplacian symmetric and the
    /// spectrum well-conditioned (eigenvalues in [0,2]) on every track; the
    /// boundaries reproduce the lab either way (validated).
    static func normalizedLaplacian(_ matrix: [Float], size: Int) -> [Float] {
        var sym = matrix
        for row in 0..<size {
            for col in (row + 1)..<size {
                let avg = 0.5 * (matrix[row * size + col] + matrix[col * size + row])
                sym[row * size + col] = avg
                sym[col * size + row] = avg
            }
        }
        var degree = [Float](repeating: 0, count: size)
        for row in 0..<size {
            var sum: Float = 0
            for col in 0..<size { sum += sym[row * size + col] }
            degree[row] = sum
        }
        let invSqrt = degree.map { $0 > 0 ? 1 / $0.squareRoot() : Float(0) }
        var laplacian = [Float](repeating: 0, count: size * size)
        for row in 0..<size {
            for col in 0..<size {
                let diag: Float = (row == col && degree[row] > 0) ? 1 : 0
                laplacian[row * size + col] = diag - sym[row * size + col] * invSqrt[row] * invSqrt[col]
            }
        }
        return laplacian
    }

    // MARK: - median (np.median semantics)

    /// Median matching `np.median` (even count averages the two middle values).
    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : 0.5 * (sorted[mid - 1] + sorted[mid])
    }
}
