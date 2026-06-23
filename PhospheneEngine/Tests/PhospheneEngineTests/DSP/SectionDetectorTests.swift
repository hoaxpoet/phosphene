// SectionDetectorTests — SECDET.3b wire-in validation for the public `SectionDetector`
// façade (22050 resample → beat-sync → McFee/Ellis clustering → strip framing boundaries).
//
// Two layers:
//  • Hermetic (always run): resampleMono halves the rate and preserves a tone's energy.
//  • Golden (skips when the lab is absent): the façade reproduces the lab McFee boundaries
//    on a real full track *from raw 22050 PCM + beat frames* — the first end-to-end check
//    of the whole Swift chain (CQT → MFCC → clustering) on real audio, not each half alone.
//
// Golden dir: $PHOSPHENE_SECTION_GOLDEN_DIR, else ~/phosphene_section_lab/golden.

import Testing
import Foundation
@testable import DSP

@Suite("SectionDetector")
struct SectionDetectorTests {

    // MARK: - Hermetic: resample

    @Test("resampleMono 44100→22050 halves length and preserves a tone's energy")
    func test_resampleMono_halvesAndPreserves() {
        let srcSR = 44100.0, dstSR = 22050.0
        let freq: Float = 440
        let src = (0..<Int(srcSR)).map { sin(2 * .pi * freq * Float($0) / Float(srcSR)) }   // 1 s
        let out = SectionDetector.resampleMono(src, from: srcSR, to: dstSR)
        #expect(abs(out.count - src.count / 2) <= 64, "got \(out.count), expected ≈ \(src.count / 2)")
        func rms(_ x: [Float]) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(1, x.count))).squareRoot() }
        let r0 = rms(src), r1 = rms(out)
        #expect(r0 > 0 && abs(r1 - r0) / r0 < 0.1, "RMS \(r1) vs \(r0)")
    }

    // MARK: - Hermetic: full-track beat extension (SECDET.5)

    @Test("fullTrackBeats extends a 30s-capped grid to the full track at the median period")
    func test_fullTrackBeats_extends() {
        // 30 s of beats at 0.5 s (120 bpm); the track is 100 s (Beat This! would cap at 30 s).
        let beats = stride(from: 0.0, through: 29.5, by: 0.5).map { $0 }
        let out = SectionDetector.fullTrackBeats(beats, duration: 100.0)
        #expect(out.count > beats.count, "grid should extend past 30 s")
        #expect(Array(out.prefix(beats.count)) == beats, "original beats preserved as the prefix")
        #expect(out.last! < 100.0 && out.last! >= 100.0 - 0.6, "extends to within a beat of duration")
        let lastGap = out[out.count - 1] - out[out.count - 2]
        #expect(abs(lastGap - 0.5) < 1e-6, "extension uses the median inter-beat period")
    }

    @Test("fullTrackBeats leaves an already-full grid unchanged")
    func test_fullTrackBeats_noExtensionWhenCovered() {
        let beats = stride(from: 0.0, through: 99.5, by: 0.5).map { $0 }   // already spans ~100 s
        let out = SectionDetector.fullTrackBeats(beats, duration: 100.0)
        #expect(out == beats, "no extension when the grid already covers the track")
    }

    // MARK: - Golden: façade reproduces the lab boundaries end-to-end

    @Test("golden: façade reproduces lab McFee boundaries from raw PCM + beats")
    func test_facadeReproducesLabBoundaries() throws {
        guard let dir = goldenDir() else {
            print("SectionDetectorTests: skipping golden (lab dir absent — run export_clustering_golden.py)")
            return
        }
        let sid = "tickettoride"   // shorter of the two goldens (193 s)
        let y = try loadF32(dir.appendingPathComponent("\(sid)_y.f32"))
        let beatFrames = try loadI32(dir.appendingPathComponent("\(sid)_beats.i32")).map(Int.init)
        let labAll = try loadF32(dir.appendingPathComponent("\(sid)_bounds.f32")).map(Double.init)

        // The façade takes beat TIMES (s); the golden stores hop-512 frame indices.
        let sr = ConstantQTransform.sampleRate, hop = Double(ConstantQTransform.hop)
        let beatTimes = beatFrames.map { Double($0) * hop / sr }
        let duration = Double(y.count) / sr

        let got = SectionDetector().boundaryTimes(
            samples: y, sampleRate: sr, beatTimes: beatTimes, duration: duration)

        // Lab truth is [0, t1, …, duration]; the façade returns interior starts only.
        let labInterior = Array(labAll.dropFirst().dropLast())
        let fScore = boundaryF(got, labInterior, tol: 3.0)
        print("  [\(sid)] façade boundaries = \(got.map { Int($0) })")
        print("  [\(sid)] lab interior      = \(labInterior.map { Int($0) }) | F@3 = \(fScore)")

        #expect(!got.isEmpty, "façade produced no boundaries on a real track")
        #expect(fScore >= 0.9, "façade boundaries should reproduce the lab (F@3 \(fScore))")
        // Spans the track → would clear the planner's 40 %-coverage gate.
        #expect((got.last ?? 0) >= duration * 0.4, "boundaries don't span ≥40 % of the track")
    }

    // MARK: - Metrics

    /// mir_eval-style boundary F-measure: an estimate hits a reference within `tol` s
    /// (greedy one-to-one). F = 2PR/(P+R).
    private func boundaryF(_ est: [Double], _ ref: [Double], tol: Double) -> Double {
        guard !est.isEmpty, !ref.isEmpty else { return est.isEmpty && ref.isEmpty ? 1 : 0 }
        var used = [Bool](repeating: false, count: ref.count)
        var hits = 0
        for e in est {
            for (j, r) in ref.enumerated() where !used[j] && abs(e - r) <= tol {
                used[j] = true; hits += 1; break
            }
        }
        let precision = Double(hits) / Double(est.count)
        let recall = Double(hits) / Double(ref.count)
        return precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
    }

    // MARK: - Golden IO

    private func goldenDir() -> URL? {
        let path = ProcessInfo.processInfo.environment["PHOSPHENE_SECTION_GOLDEN_DIR"]
            ?? NSHomeDirectory() + "/phosphene_section_lab/golden"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("tickettoride_y.f32").path)
            ? url : nil
    }

    private func loadF32(_ url: URL) throws -> [Float] {
        try Data(contentsOf: url).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    private func loadI32(_ url: URL) throws -> [Int32] {
        try Data(contentsOf: url).withUnsafeBytes { Array($0.bindMemory(to: Int32.self)) }
    }
}
