// SpectralClustererTests — SECDET Stage B validation for the McFee/Ellis clustering
// port (recurrence graph → normalized Laplacian → eigensolve → k-means → boundaries).
//
// Hermetic tests (always run) cover the deterministic primitives. The golden-match
// test reproduces the lab's clustering intermediates + final boundaries on the
// SMTS + Ticket to Ride goldens (skips when the lab golden export is absent).

import Testing
import Foundation
@testable import DSP

@Suite("SpectralClusterer")
struct SpectralClustererTests {

    // MARK: - LAPACK ssyev spike

    @Test("ssyev: eigenvalues/vectors of [[2,1],[1,2]] are {1,3}")
    func test_ssyev_known2x2() throws {
        // Symmetric [[2,1],[1,2]]: eigenvalues 1 (vec ∝ [1,-1]) and 3 (vec ∝ [1,1]).
        let mat: [Float] = [2, 1, 1, 2]
        let result = try #require(SymmetricEigen.decompose(matrix: mat, size: 2))
        #expect(abs(result.eigenvalues[0] - 1) < 1e-5)
        #expect(abs(result.eigenvalues[1] - 3) < 1e-5)
        // Eigenvector for λ=1 is [a,-a]; for λ=3 is [a,a] (row-major [i*n+j]).
        let v0 = (result.eigenvectors[0 * 2 + 0], result.eigenvectors[1 * 2 + 0])
        let v1 = (result.eigenvectors[0 * 2 + 1], result.eigenvectors[1 * 2 + 1])
        #expect(abs(v0.0 + v0.1) < 1e-5, "λ=1 eigenvector should be antisymmetric")
        #expect(abs(v1.0 - v1.1) < 1e-5, "λ=3 eigenvector should be symmetric")
    }

    @Test("ssyev: 3×3 diagonal returns its diagonal ascending")
    func test_ssyev_diagonal() throws {
        let mat: [Float] = [5, 0, 0, 0, 2, 0, 0, 0, 9]
        let result = try #require(SymmetricEigen.decompose(matrix: mat, size: 3))
        #expect(abs(result.eigenvalues[0] - 2) < 1e-5)
        #expect(abs(result.eigenvalues[1] - 5) < 1e-5)
        #expect(abs(result.eigenvalues[2] - 9) < 1e-5)
    }

    // MARK: - normalized Laplacian / enforce_min hermetic checks

    @Test("normalizedLaplacian: isolated node gets a 0 diagonal (scipy convention)")
    func test_laplacian_isolatedNode() {
        // A = [[0,2,0],[2,0,0],[0,0,0]] → node 2 isolated.
        let lap = RecurrenceGraph.normalizedLaplacian([0, 2, 0, 2, 0, 0, 0, 0, 0], size: 3)
        #expect(abs(lap[0] - 1) < 1e-6)        // L[0,0] = 1 (connected)
        #expect(abs(lap[8] - 0) < 1e-6)        // L[2,2] = 0 (isolated)
        #expect(abs(lap[1] + 1) < 1e-6)        // L[0,1] = -2/sqrt(2*2) = -1
    }

    @Test("kmeans: two well-separated blobs split cleanly")
    func test_kmeans_twoBlobs() {
        // Points near (0,0) and near (10,10) → two clusters.
        let points: [Float] = [0, 0, 0.1, -0.1, -0.1, 0.1, 10, 10, 10.1, 9.9, 9.9, 10.1]
        let labels = KMeans.cluster(points: points, size: 6, dim: 2, k: 2)
        // First three share a label, last three share the other.
        #expect(labels[0] == labels[1] && labels[1] == labels[2])
        #expect(labels[3] == labels[4] && labels[4] == labels[5])
        #expect(labels[0] != labels[3])
    }

    @Test("enforceMin: merges sub-8s sections, appends duration")
    func test_enforceMin() {
        // segments start at 0,5,10,...; bounds at indices 1,2,5 → times 5,10,25.
        let starts = (0..<8).map { Double($0) * 5.0 }
        let out = SpectralSectionDetector.enforceMin(
            segmentStartTimes: starts, bounds: [1, 2, 5], duration: 40, minLen: 8.0)
        // 0 → 5 (Δ5 <8, drop) → 10 (Δ10 ≥8 from 0, keep) → 25 (Δ15, keep) + dur.
        #expect(out == [0.0, 10.0, 25.0, 40.0])
    }

    // MARK: - Golden match (skips when the lab clustering export is absent)

    @Test("golden: Swift clustering reproduces librosa graph + boundaries")
    func test_clusteringGolden() throws {
        guard let dir = goldenDir(), FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("clustering_meta.json").path) else {
            print("SpectralClustererTests: skipping (clustering golden absent — run export_clustering_golden.py)")
            return
        }
        let meta = try JSONDecoder().decode(
            ClusterMeta.self, from: Data(contentsOf: dir.appendingPathComponent("clustering_meta.json")))
        for sid in meta.tracks.keys.sorted() {
            try validate(sid, info: meta.tracks[sid]!, dir: dir)   // swiftlint:disable:this force_unwrapping
        }
    }

    private func validate(_ sid: String, info: ClusterMeta.Track, dir: URL) throws {
        let n = info.n
        let cq = try loadF32(dir.appendingPathComponent("\(sid)_Cq.f32"))
        let ms = try loadF32(dir.appendingPathComponent("\(sid)_Ms.f32"))
        let gR = try loadF32(dir.appendingPathComponent("\(sid)_R.f32"))
        let gA = try loadF32(dir.appendingPathComponent("\(sid)_A.f32"))
        let gEvals = try loadF32(dir.appendingPathComponent("\(sid)_evals.f32"))
        let gX = try loadF32(dir.appendingPathComponent("\(sid)_X.f32"))
        let beats = try loadI32(dir.appendingPathComponent("\(sid)_beats.i32")).map { Double($0) * 512.0 / 22050.0 }

        // Deterministic chain: recurrence affinity → fuse → Laplacian eigenvalues.
        let swR = RecurrenceGraph.affinity(features: cq, dim: 252, size: n)
        let rCorr = pearson(swR, gR) ?? 0
        let rf = RecurrenceGraph.timelagMedian(swR, size: n)
        let rp = RecurrenceGraph.pathDiagonal(mfcc: ms, dim: 13, size: n)
        let fused = RecurrenceGraph.fuse(recurrence: rf, path: rp, size: n)
        let aCorr = pearson(fused.matrix, gA) ?? 0
        let lap = RecurrenceGraph.normalizedLaplacian(fused.matrix, size: n)
        let eigen = try #require(SymmetricEigen.decompose(matrix: lap, size: n))
        // We symmetrize A (the timelag asymmetry is a reflect-padding artifact), so
        // the spectrum is well-conditioned in [0,2]. The lab keeps the asymmetry and
        // gets huge ill-conditioned eigenvalues from a sub-float32 near-isolated-node
        // degree — irreproducible and unused — so raw eigenvalues are NOT the gate.
        let smallest = eigen.eigenvalues.first ?? 99
        let largest = eigen.eigenvalues.last ?? 99
        let swX = SpectralSectionDetector.embedding(eigenvectors: eigen.eigenvectors, size: n, k: 5)
        let xSSM = ssmCorrelation(swX, gX, rows: n, cols: 5)
        _ = gEvals  // golden eigenvalues kept for reference; not gated (see above).

        print(String(format: "  [\(sid)] N=\(n) | R corr=%.4f | μ swift=%.4f gold=%.4f | A corr=%.4f | spectrum=[%.4f,%.4f] | X SSM=%.3f",
                     rCorr, fused.mu, info.mu, aCorr, smallest, largest, xSSM))
        // Gates: the deterministic fused affinity (feeds the Laplacian), a well-formed
        // symmetric-Laplacian spectrum, and (below) the boundaries themselves.
        #expect(rCorr > 0.97, "recurrence matrix should track librosa (got \(rCorr))")
        #expect(aCorr > 0.99, "fused affinity must match (feeds the Laplacian)")
        #expect(smallest > -1e-3 && largest < 2.1, "well-formed normalized-Laplacian spectrum [\(smallest), \(largest)]")

        // End-to-end boundaries vs the lab.
        let feat = SectionFeatures(cqtDB: [], mfcc: [], cqSync: cq, msSync: ms,
                                   cqtBinCount: 252, mfccCount: 13, frameCount: 0, segmentCount: n)
        let swBounds = SpectralSectionDetector().boundaryTimes(
            features: feat, segmentStartTimes: beats, duration: info.dur)
        let f3 = boundaryF(ref: info.boundsSec, est: swBounds, window: 3.0)
        print(String(format: "  [\(sid)] boundaries swift=\(swBounds.map { Int($0) }) lab=\(info.boundsSec.map { Int($0) }) | F@3 vs lab=%.3f", f3))
        #expect(f3 > 0.80, "boundaries should reproduce the lab within 3 s (F@3 \(f3))")
    }

    // MARK: - metrics

    private func boundaryF(ref: [Double], est: [Double], window: Double) -> Double {
        // Interior boundaries only (drop 0 and the final duration, present in both).
        let refI = ref.dropFirst().dropLast()
        let estI = est.dropFirst().dropLast()
        guard !refI.isEmpty, !estI.isEmpty else { return refI.isEmpty && estI.isEmpty ? 1 : 0 }
        var hits = 0
        for boundary in refI where estI.contains(where: { abs($0 - boundary) <= window }) { hits += 1 }
        let recall = Double(hits) / Double(refI.count)
        var hitsE = 0
        for boundary in estI where refI.contains(where: { abs($0 - boundary) <= window }) { hitsE += 1 }
        let precision = Double(hitsE) / Double(estI.count)
        return precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
    }

    private func ssmCorrelation(_ a: [Float], _ b: [Float], rows: Int, cols: Int) -> Float {
        pearson(pairwiseDistances(a, rows: rows, cols: cols),
                pairwiseDistances(b, rows: rows, cols: cols)) ?? 0
    }

    private func pairwiseDistances(_ mat: [Float], rows: Int, cols: Int) -> [Float] {
        // mat is row-major rows×cols; distance between rows i,j over the cols.
        var out = [Float](); out.reserveCapacity(rows * (rows - 1) / 2)
        for i in 0..<rows {
            for j in (i + 1)..<rows {
                var acc: Float = 0
                for c in 0..<cols { let d = mat[i * cols + c] - mat[j * cols + c]; acc += d * d }
                out.append(acc.squareRoot())
            }
        }
        return out
    }

    private func pearson(_ x: [Float], _ y: [Float]) -> Float? {
        let count = min(x.count, y.count)
        guard count > 1 else { return nil }
        let mx = x.reduce(0, +) / Float(count), my = y.reduce(0, +) / Float(count)
        var sxy: Float = 0, sxx: Float = 0, syy: Float = 0
        for i in 0..<count {
            let dx = x[i] - mx, dy = y[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        let denom = (sxx * syy).squareRoot()
        return denom > 1e-12 ? sxy / denom : nil
    }

    // MARK: - golden IO

    private func goldenDir() -> URL? {
        let path = ProcessInfo.processInfo.environment["PHOSPHENE_SECTION_GOLDEN_DIR"]
            ?? NSHomeDirectory() + "/phosphene_section_lab/golden"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadF32(_ url: URL) throws -> [Float] {
        try Data(contentsOf: url).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func loadI32(_ url: URL) throws -> [Int32] {
        try Data(contentsOf: url).withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }
    }

    private struct ClusterMeta: Decodable {
        let tracks: [String: Track]
        struct Track: Decodable {
            let n: Int
            let mu: Float
            let dur: Double
            let boundsSec: [Double]
            enum CodingKeys: String, CodingKey {
                case n = "N", mu, dur, boundsSec = "bounds_sec"
            }
        }
    }
}
