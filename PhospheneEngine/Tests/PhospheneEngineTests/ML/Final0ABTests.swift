// Final0ABTests — MDL.1: does the larger Beat This! checkpoint give better evidence?
//
// The plan's expected leverage is suites 2 and 4, and DBN.2 ended with the finding
// that the remaining gap is **evidence quality, not model bias**: with an unbiased
// decoder, odd meters are still won by hairline margins because the downbeat stream
// is near-degenerate (DBN.1 measured a confident downbeat on 69–90 % of beats).
// final0 is the only lever that addresses the evidence itself rather than how it is
// read, so this A/B is the direct test of that finding.
//
// D-E asks whether the deltas justify **weight size + prep latency**, so this measures
// inference wall-time as well as accuracy — which is why the A/B runs through the real
// MPSGraph path rather than the PyTorch reference.
//
// final0 weights are NOT vendored: 81 MB does not enter the bundle before D-E decides.
// Convert them first, then point this at the output:
//
//   ~/phosphene-ml-env/bin/python Scripts/convert_beatthis_weights.py \
//     --checkpoint ~/.cache/torch/hub/checkpoints/beat_this-final0.ckpt \
//     --variant final0 --out /tmp/beat_this_final0
//
//   PHOSPHENE_MDL1_AB=1 PHOSPHENE_FINAL0_DIR=/tmp/beat_this_final0 \
//   swift test --package-path PhospheneEngine --filter Final0AB
//
// DIAGNOSTIC ONLY — env-gated, asserts nothing. The printed table is the artifact.

import Testing
import Foundation
import Metal
@testable import DSP
@testable import ML

@Suite("Final0AB")
struct Final0ABTests {

    private struct Row {
        let track: String
        let truthMeter: Int?
        let variant: String
        let bpm: Double
        let meter: Int
        let beatCount: Int
        let downbeatCount: Int
        /// The DBN.1 degeneracy metric — the fraction of beats also marked as downbeats.
        let downbeatBeatRatio: Double
        let inferenceMs: Double
    }

    @Test("MDL.1: small0 vs final0 on the ground-truthed catalogue")
    func test_final0AB() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_MDL1_AB"] == "1" else {
            print("[MDL.1] skipped — set PHOSPHENE_MDL1_AB=1 to run")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else { Issue.record("no Metal"); return }
        guard let finalDirPath = ProcessInfo.processInfo.environment["PHOSPHENE_FINAL0_DIR"] else {
            Issue.record("PHOSPHENE_FINAL0_DIR unset — convert final0 weights first (see header)")
            return
        }
        let finalDir = URL(fileURLWithPath: finalDirPath)
        guard FileManager.default.fileExists(atPath: finalDir.appendingPathComponent("manifest.json").path)
        else {
            Issue.record("no manifest.json in \(finalDirPath) — run the converter first")
            return
        }
        let fixturesDir = ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("phosphene_beatbench_fixtures")

        // Ground-truth meters as recorded in the GT.3 baseline; nil = no stable meter.
        let catalogue: [(String, Int?)] = [
            ("billie_jean", 4), ("money", 7), ("solsbury_hill", 7), ("take_five", 5),
            ("bohemian_rhapsody", 4), ("bleed", 4),
            ("pyramid_song", nil), ("yyz", nil), ("clair_de_lune", nil)
        ]

        let small = try BeatThisModel(device: device, variant: .small0, weightsDirectory: nil)
        let large = try BeatThisModel(device: device, variant: .final0, weightsDirectory: finalDir)
        print("""

        ================= MDL.1 — small0 vs final0 =================
        final0 loaded from \(finalDirPath) (not vendored; D-E decides).
        ratio = downbeat peaks / beat peaks — DBN.1's degeneracy metric. Lower is
        better on odd meters: it means the model marks fewer beats as candidate
        bar lines, which is the evidence problem DBN.2 could not read its way out of.
        \(String(repeating: "-", count: 92))
        track                variant  bpm     meter  beats  dbeats  ratio   infer ms
        """)

        var rows: [Row] = []
        for (name, truth) in catalogue {
            guard let url = Self.locate(name, in: fixturesDir) else {
                print("  \(name): fixture missing"); continue
            }
            let samples = try Self.decodeMono22050(url: url)
            let (spect, frames) = BeatThisPreprocessor().process(samples: samples, inputSampleRate: 22050.0)

            for (label, model) in [("small0", small), ("final0", large)] {
                let start = DispatchTime.now().uptimeNanoseconds
                let (beatProbs, downbeatProbs) = try model.predict(spectrogram: spect, frameCount: frames)
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000.0
                let grid = BeatGridResolver.resolve(
                    beatProbs: beatProbs, downbeatProbs: downbeatProbs, frameRate: 50.0
                )
                let beatPeaks = Self.peakCount(beatProbs)
                let dbPeaks = Self.peakCount(downbeatProbs)
                let row = Row(
                    track: name, truthMeter: truth, variant: label, bpm: grid.bpm,
                    meter: grid.beatsPerBar, beatCount: beatPeaks, downbeatCount: dbPeaks,
                    downbeatBeatRatio: beatPeaks > 0 ? Double(dbPeaks) / Double(beatPeaks) : 0,
                    inferenceMs: ms
                )
                rows.append(row)
                let truthStr = truth.map(String.init) ?? "—"
                let mark = truth.map { row.meter == $0 ? "✓" : "✗" } ?? " "
                print(String(format: "  %-20@ %-7@ %7.2f  %2d/%-2@%@  %5d  %5d  %5.2f  %8.1f",
                             name as NSString, label as NSString, row.bpm,
                             row.meter, truthStr as NSString, mark as NSString,
                             row.beatCount, row.downbeatCount, row.downbeatBeatRatio, row.inferenceMs))
            }
        }

        print("\n  \(String(repeating: "-", count: 90))")
        for label in ["small0", "final0"] {
            let sub = rows.filter { $0.variant == label }
            let truthed = sub.filter { $0.truthMeter != nil }
            let correct = truthed.filter { $0.meter == $0.truthMeter }.count
            let meanRatio = sub.isEmpty ? 0 : sub.map(\.downbeatBeatRatio).reduce(0, +) / Double(sub.count)
            let meanMs = sub.isEmpty ? 0 : sub.map(\.inferenceMs).reduce(0, +) / Double(sub.count)
            print(String(format: "  %-7@ meter correct %d/%d   mean downbeat:beat ratio %.3f   mean inference %.0f ms",
                         label as NSString, correct, truthed.count, meanRatio, meanMs))
        }
        print("""

          D-E asks whether the deltas justify 81 MB (vs 8.4 MB) and the prep latency
          above. A ratio that does not fall is the decisive negative: it would mean the
          bigger model does not fix the evidence problem DBN.2 identified.
        ============================================================

        """)
    }

    // MARK: - Helpers

    /// ±3-frame max-pool + >0.5 threshold — the reference minimal post-processor's rule.
    private static func peakCount(_ probs: [Float]) -> Int {
        var count = 0
        for i in probs.indices where probs[i] > 0.5 {
            let lo = max(0, i - 3), hi = min(probs.count - 1, i + 3)
            var maxV = probs[i]
            for j in lo...hi where probs[j] > maxV { maxV = probs[j] }
            if probs[i] == maxV { count += 1 }
        }
        return count
    }

    private static func locate(_ name: String, in dir: String) -> URL? {
        for ext in ["wav", "mp3", "m4a", "flac"] {
            let path = (dir as NSString).appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    private static func decodeMono22050(url: URL) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["ffmpeg", "-loglevel", "error", "-i", url.path,
                          "-ac", "1", "-ar", "22050", "-f", "f32le", "-"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        var raw = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            raw.append(chunk)
        }
        proc.waitUntilExit()
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: raw.count / 4))
        }
    }
}
