// KMeans — hand-rolled Lloyd's k-means with k-means++ seeding (SECDET Stage B).
//
// Stands in for sklearn.cluster.KMeans(n_init=10, random_state=0) in the McFee
// pipeline. Deterministic (fixed-seed LCG), n_init restarts, lowest-inertia wins.
// The spectral embedding's clustering is invariant to orthogonal transforms of the
// coordinates, so matching sklearn's exact seeding is unnecessary — restarts +
// best-inertia reliably recover the same partition.

import Foundation

// MARK: - KMeans

enum KMeans {

    /// Cluster `size` points of dimension `dim` (row-major `points[i*dim + c]`) into
    /// `k` groups. Returns a label in `0..<k` per point.
    static func cluster(points: [Float], size: Int, dim: Int, k: Int,
                        nInit: Int = 10, maxIter: Int = 300, seed: UInt64 = 0) -> [Int] {
        guard size > 0, k > 0 else { return [Int](repeating: 0, count: size) }
        if size <= k { return Array(0..<size) }

        var best: [Int] = []
        var bestInertia = Float.greatestFiniteMagnitude
        var rng = LCG(state: seed &+ 0x9E3779B97F4A7C15)

        for _ in 0..<nInit {
            var centers = plusPlusInit(points: points, size: size, dim: dim, k: k, rng: &rng)
            var labels = [Int](repeating: 0, count: size)
            for _ in 0..<maxIter {
                let changed = assign(points: points, size: size, dim: dim, centers: centers, labels: &labels)
                centers = recompute(points: points, size: size, dim: dim, labels: labels, fallback: centers)
                if !changed { break }
            }
            let inertia = totalInertia(points: points, size: size, dim: dim, centers: centers, labels: labels)
            if inertia < bestInertia { bestInertia = inertia; best = labels }
        }
        return best
    }

    // MARK: - k-means++ seeding

    private static func plusPlusInit(points: [Float], size: Int, dim: Int, k: Int,
                                     rng: inout LCG) -> [Float] {
        var centers = [Float](repeating: 0, count: k * dim)
        let first = Int(rng.uniform() * Double(size)) % size
        copyPoint(points, first, dim, into: &centers, at: 0)

        var closest = (0..<size).map { sqDist(points, $0, centers, 0, dim) }
        for centerIdx in 1..<k {
            let total = closest.reduce(0, +)
            var target = Float(rng.uniform()) * total
            var chosen = size - 1
            for pointIdx in 0..<size {
                target -= closest[pointIdx]
                if target <= 0 { chosen = pointIdx; break }
            }
            copyPoint(points, chosen, dim, into: &centers, at: centerIdx)
            for pointIdx in 0..<size {
                let dist = sqDist(points, pointIdx, centers, centerIdx, dim)
                if dist < closest[pointIdx] { closest[pointIdx] = dist }
            }
        }
        return centers
    }

    // MARK: - Lloyd steps

    private static func assign(points: [Float], size: Int, dim: Int, centers: [Float], labels: inout [Int]) -> Bool {
        var changed = false
        let centerCount = centers.count / dim
        for pointIdx in 0..<size {
            var bestLabel = 0
            var bestDist = Float.greatestFiniteMagnitude
            for centerIdx in 0..<centerCount {
                let dist = sqDist(points, pointIdx, centers, centerIdx, dim)
                if dist < bestDist { bestDist = dist; bestLabel = centerIdx }
            }
            if labels[pointIdx] != bestLabel { labels[pointIdx] = bestLabel; changed = true }
        }
        return changed
    }

    private static func recompute(points: [Float], size: Int, dim: Int, labels: [Int], fallback: [Float]) -> [Float] {
        let k = fallback.count / dim
        var centers = [Float](repeating: 0, count: k * dim)
        var counts = [Int](repeating: 0, count: k)
        for pointIdx in 0..<size {
            let label = labels[pointIdx]
            counts[label] += 1
            for component in 0..<dim { centers[label * dim + component] += points[pointIdx * dim + component] }
        }
        for centerIdx in 0..<k {
            let base = centerIdx * dim
            if counts[centerIdx] == 0 {
                // Empty cluster: keep the previous center (avoids NaN drift).
                for component in 0..<dim { centers[base + component] = fallback[base + component] }
            } else {
                let inv = 1 / Float(counts[centerIdx])
                for component in 0..<dim { centers[base + component] *= inv }
            }
        }
        return centers
    }

    private static func totalInertia(points: [Float], size: Int, dim: Int,
                                     centers: [Float], labels: [Int]) -> Float {
        var sum: Float = 0
        for pointIdx in 0..<size { sum += sqDist(points, pointIdx, centers, labels[pointIdx], dim) }
        return sum
    }

    // MARK: - helpers

    private static func sqDist(_ apoints: [Float], _ aIdx: Int,
                               _ bpoints: [Float], _ bIdx: Int, _ dim: Int) -> Float {
        var sum: Float = 0
        let aBase = aIdx * dim, bBase = bIdx * dim
        for component in 0..<dim {
            let diff = apoints[aBase + component] - bpoints[bBase + component]
            sum += diff * diff
        }
        return sum
    }

    private static func copyPoint(_ points: [Float], _ idx: Int, _ dim: Int,
                                  into centers: inout [Float], at centerIdx: Int) {
        for component in 0..<dim { centers[centerIdx * dim + component] = points[idx * dim + component] }
    }
}

// MARK: - LCG

/// Deterministic 64-bit linear congruential generator (reproducible clustering).
private struct LCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func uniform() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}
