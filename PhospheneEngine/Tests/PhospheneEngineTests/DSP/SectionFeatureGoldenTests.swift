// SectionFeatureGoldenTests — SECDET Stage A validation for the Swift port of the
// lab's beat-synced 252-CQT + 13-MFCC features.
//
// Two layers:
//  • Hermetic (always run): a tone lands on its CQT bin; MFCC is finite/non-trivial;
//    beat-sync aggregation reproduces librosa.util.sync exactly on a tiny matrix.
//  • Golden match (skips when the lab is absent): compares the Swift features to
//    librosa goldens exported by ~/phosphene_section_lab/export_golden.py.
//
// The headline CQT gate is the SSM correlation on the beat-synced matrix: the
// recurrence graph the detector builds depends only on pairwise column distances,
// which are invariant to the per-bin constant-gain differences between the kernel
// CQT and librosa's recursive CQT. That correlation predicts F-score transfer; raw
// per-element dB agreement does not (and is not expected to be exact).
//
// Golden dir: $PHOSPHENE_SECTION_GOLDEN_DIR, else ~/phosphene_section_lab/golden.

import Testing
import Foundation
@testable import DSP

@Suite("SectionFeatureGolden")
struct SectionFeatureGoldenTests {

    // MARK: - Hermetic: CQT bin localisation

    @Test("CQT: a C4 tone peaks on its own bin (108)")
    func test_cqt_tonePeaksOnBin() {
        // f_k = fmin·2^(k/36); bin 108 = 32.703·2^3 = 261.6 Hz (C4).
        let sr = Float(ConstantQTransform.sampleRate)
        let freq: Float = 261.6255653
        let samples = (0..<(sr.intValue * 4)).map { sin(2 * .pi * freq * Float($0) / sr) }
        let (db, frames) = ConstantQTransform().dbMatrix(samples: samples)
        #expect(frames > 0)

        // Steady-state frame: the loudest bin should be 108 ± a couple of bins,
        // and a far bin (≈2 octaves down) should be far quieter.
        let t = frames / 2
        var best = 0
        var bestVal = -Float.greatestFiniteMagnitude
        for k in 0..<ConstantQTransform.binCount where db[k * frames + t] > bestVal {
            bestVal = db[k * frames + t]; best = k
        }
        #expect(abs(best - 108) <= 2, "tone peaked at bin \(best), expected ≈108")
        #expect(bestVal - db[36 * frames + t] > 20, "C4 bin should dominate a 2-octave-down bin")
    }

    // MARK: - Hermetic: MFCC sanity

    @Test("MFCC: tone yields finite, non-trivial coefficients")
    func test_mfcc_finiteNonTrivial() {
        let sr = Float(MFCCProcessor.sampleRate)
        let samples = (0..<(sr.intValue * 2)).map { sin(2 * .pi * 440 * Float($0) / sr) }
        let (mfcc, frames) = MFCCProcessor().matrix(samples: samples)
        #expect(frames > 0)
        #expect(mfcc.allSatisfy { $0.isFinite })
        // Interior frame should carry spectral shape: not all coeffs ≈ 0.
        let t = frames / 2
        let energy = (1..<MFCCProcessor.nMFCC).reduce(Float(0)) { $0 + abs(mfcc[$1 * frames + t]) }
        #expect(energy > 1.0, "MFCC coeffs 1..12 unexpectedly flat (energy=\(energy))")
    }

    // MARK: - Hermetic: beat-sync parity with librosa.util.sync

    @Test("beat-sync: median/mean match librosa.util.sync on a known matrix")
    func test_beatSync_matchesLibrosa() {
        // Probe (verified against librosa): data row = 0..19, beats = [3,7,12,16].
        let row: [Float] = (0..<20).map { Float($0) }
        let bounds = SectionFeatureExtractor.syncBoundaries(beatFrames: [3, 7, 12, 16], frameCount: 20)
        #expect(bounds == [0, 3, 7, 12, 16, 20])
        let med = SectionFeatureExtractor.aggregate(row, rows: 1, cols: 20, bounds: bounds, median: true)
        // librosa medians: [1.0, 4.5, 9.0, 13.5, 17.5]
        #expect(approxEqual(med, [1.0, 4.5, 9.0, 13.5, 17.5], tol: 1e-5))
        let mean = SectionFeatureExtractor.aggregate(row, rows: 1, cols: 20, bounds: bounds, median: false)
        // segment means: [1, 4.5, 9, 13.5, 17.5] (means of consecutive ranges)
        #expect(approxEqual(mean, [1.0, 4.5, 9.0, 13.5, 17.5], tol: 1e-5))
    }

    @Test("beat-sync: beats with frame 0 (librosa beat_track) keep N == distinct beats")
    func test_beatSync_zeroBeatBoundaries() {
        let bounds = SectionFeatureExtractor.syncBoundaries(beatFrames: [0, 5, 11], frameCount: 30)
        #expect(bounds == [0, 5, 11, 30])          // N segments = 3 = distinct beats
    }

    // MARK: - Hermetic: Slaney mel basis is well-formed

    @Test("mel basis: shape, non-negative, each filter has support")
    func test_melBasis_wellFormed() {
        let basis = MFCCProcessor.buildSlaneyMelBasis()
        #expect(basis.count == MFCCProcessor.nMels * MFCCProcessor.nBins)
        #expect(basis.allSatisfy { $0 >= 0 })
        for m in 0..<MFCCProcessor.nMels {
            let rowSum = (0..<MFCCProcessor.nBins).reduce(Float(0)) { $0 + basis[m * MFCCProcessor.nBins + $1] }
            #expect(rowSum > 0, "mel filter \(m) has no support")
        }
    }

    // MARK: - Golden match (skips when the lab golden export is absent)

    @Test("golden: Swift features reproduce librosa (mel exact, MFCC + CQT structure)")
    func test_goldenMatch() throws {
        guard let dir = goldenDir() else {
            print("SectionFeatureGoldenTests: skipping golden match (golden dir absent — run export_golden.py)")
            return
        }
        print("SectionFeatureGoldenTests: golden dir = \(dir.path)")

        // 1. Mel basis — should be near-exact (same formula as librosa.filters.mel).
        let goldenMel = try loadF32(dir.appendingPathComponent("mel_basis.f32"))
        let swiftMel = MFCCProcessor.buildSlaneyMelBasis()
        #expect(swiftMel.count == goldenMel.count, "mel basis size \(swiftMel.count) vs \(goldenMel.count)")
        let melMaxAbs = zip(swiftMel, goldenMel).map { abs($0 - $1) }.max() ?? 0
        print(String(format: "  mel_basis  maxAbsΔ = %.3e", melMaxAbs))
        #expect(melMaxAbs < 1e-5, "Slaney mel basis must match librosa exactly")

        let meta = try loadMeta(dir.appendingPathComponent("meta.json"))
        for sid in meta.tracks.keys.sorted() {
            try validateTrack(sid, dir: dir, meta: meta)
        }
    }

    private func validateTrack(_ sid: String, dir: URL, meta: GoldenMeta) throws {
        guard let info = meta.tracks[sid] else { return }
        let y = try loadF32(dir.appendingPathComponent("\(sid)_y.f32"))
        let beats = try loadI32(dir.appendingPathComponent("\(sid)_beats.i32")).map(Int.init)
        let gCqt = try loadF32(dir.appendingPathComponent("\(sid)_cqt.f32"))   // (252, T)
        let gMfcc = try loadF32(dir.appendingPathComponent("\(sid)_mfcc.f32")) // (13, T)
        let gCq = try loadF32(dir.appendingPathComponent("\(sid)_Cq.f32"))     // (252, N)
        let gMs = try loadF32(dir.appendingPathComponent("\(sid)_Ms.f32"))     // (13, N)

        let feat = SectionFeatureExtractor().extract(samples22k: y, beatFrames: beats)
        let tCQT = info.cqtShape[1], nSeg = info.cqShape[1]
        print("  [\(sid)] T golden=\(tCQT) swift=\(feat.frameCount) | N golden=\(nSeg) swift=\(feat.segmentCount)")
        #expect(feat.frameCount == tCQT, "CQT frame count")
        #expect(feat.segmentCount == nSeg, "beat-sync segment count")

        // MFCC: deterministic pipeline → expect strong per-coefficient correlation.
        let mfccCorr = meanRowCorrelation(feat.mfcc, gMfcc, rows: 13, cols: min(feat.frameCount, tCQT))
        print(String(format: "  [\(sid)] MFCC   mean per-coeff corr = %.4f", mfccCorr))
        #expect(mfccCorr > 0.99, "MFCC should track librosa closely (got \(mfccCorr))")

        // CQT frame-level: per-column correlation across the 252 bins (report).
        let cqtColCorr = meanColCorrelation(feat.cqtDB, gCqt, rows: 252, cols: min(feat.frameCount, tCQT))
        print(String(format: "  [\(sid)] CQT    mean per-frame corr = %.4f", cqtColCorr))

        // HEADLINE: SSM correlation on beat-synced Cq — invariant to per-bin gain,
        // predicts recurrence/F-score transfer.
        let cqSSM = ssmCorrelation(feat.cqSync, gCq, rows: 252, cols: nSeg)
        let msSSM = ssmCorrelation(feat.msSync, gMs, rows: 13, cols: nSeg)
        print(String(format: "  [\(sid)] Cq SSM corr = %.4f | Ms SSM corr = %.4f", cqSSM, msSSM))
        #expect(cqSSM > 0.99, "beat-synced CQT recurrence structure must match librosa (got \(cqSSM))")
        #expect(msSSM > 0.99, "beat-synced MFCC recurrence structure must match librosa (got \(msSSM))")
    }

    // MARK: - Metrics

    /// Mean Pearson correlation across rows (e.g. per MFCC coefficient over time).
    private func meanRowCorrelation(_ a: [Float], _ b: [Float], rows: Int, cols: Int) -> Float {
        var sum: Float = 0, count = 0
        for r in 0..<rows {
            let ar = Array(a[(r * cols)..<(r * cols + cols)])
            let br = Array(b[(r * cols)..<(r * cols + cols)])
            if let c = pearson(ar, br) { sum += c; count += 1 }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    /// Mean Pearson correlation across columns (each column = one frame's bins).
    private func meanColCorrelation(_ a: [Float], _ b: [Float], rows: Int, cols: Int) -> Float {
        var sum: Float = 0, count = 0
        var ca = [Float](repeating: 0, count: rows)
        var cb = [Float](repeating: 0, count: rows)
        for t in 0..<cols {
            for r in 0..<rows { ca[r] = a[r * cols + t]; cb[r] = b[r * cols + t] }
            if let c = pearson(ca, cb) { sum += c; count += 1 }
        }
        return count > 0 ? sum / Float(count) : 0
    }

    /// Correlation between the two pairwise-column-distance self-similarity matrices.
    /// Invariant to per-row constant offsets (they cancel in column differences).
    private func ssmCorrelation(_ a: [Float], _ b: [Float], rows: Int, cols: Int) -> Float {
        let da = pairwiseDistances(a, rows: rows, cols: cols)
        let db = pairwiseDistances(b, rows: rows, cols: cols)
        return pearson(da, db) ?? 0
    }

    private func pairwiseDistances(_ mat: [Float], rows: Int, cols: Int) -> [Float] {
        var out = [Float](); out.reserveCapacity(cols * (cols - 1) / 2)
        for i in 0..<cols {
            for j in (i + 1)..<cols {
                var acc: Float = 0
                for r in 0..<rows {
                    let d = mat[r * cols + i] - mat[r * cols + j]
                    acc += d * d
                }
                out.append(acc.squareRoot())
            }
        }
        return out
    }

    private func pearson(_ x: [Float], _ y: [Float]) -> Float? {
        let n = min(x.count, y.count)
        guard n > 1 else { return nil }
        let mx = x.reduce(0, +) / Float(n)
        let my = y.reduce(0, +) / Float(n)
        var sxy: Float = 0, sxx: Float = 0, syy: Float = 0
        for i in 0..<n {
            let dx = x[i] - mx, dy = y[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        let denom = (sxx * syy).squareRoot()
        return denom > 1e-12 ? sxy / denom : nil
    }

    private func approxEqual(_ a: [Float], _ b: [Float], tol: Float) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tol }
    }

    // MARK: - Golden IO

    private func goldenDir() -> URL? {
        let path = ProcessInfo.processInfo.environment["PHOSPHENE_SECTION_GOLDEN_DIR"]
            ?? NSHomeDirectory() + "/phosphene_section_lab/golden"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("meta.json").path) ? url : nil
    }

    private func loadF32(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private func loadI32(_ url: URL) throws -> [Int32] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }
    }

    private func loadMeta(_ url: URL) throws -> GoldenMeta {
        try JSONDecoder().decode(GoldenMeta.self, from: Data(contentsOf: url))
    }

    private struct GoldenMeta: Decodable {
        let tracks: [String: TrackInfo]
        struct TrackInfo: Decodable {
            let cqtShape: [Int]
            let mfccShape: [Int]
            let cqShape: [Int]
            let msShape: [Int]
            enum CodingKeys: String, CodingKey {
                case cqtShape = "cqt_shape", mfccShape = "mfcc_shape"
                case cqShape = "Cq_shape", msShape = "Ms_shape"
            }
        }
    }
}

// MARK: - Float helper

private extension Float {
    var intValue: Int { Int(self) }
}
