// DownbeatStreamDiagnosticTests — DBN.1 task 7: is the downbeat activation stream
// informative enough for meter inference at all?
//
// The GT.3 baseline reports `beatsPerBar` correct on 2 of 9 tracks and downbeat F
// of 0.13–0.26 everywhere except billie_jean's 0.90. The grid reads meter 1 or 2
// on eight of nine tracks, which means the resolved downbeats land roughly every
// beat rather than every bar.
//
// Before specifying a bar-pointer decoder to fix that, this measures where the
// signal actually dies: in the model's downbeat probabilities, or in
// `BeatGridResolver`'s post-processing of them. Beat This! reports downbeat F1
// ≈ 0.78 on GTZAN using a minimal post-processor of the same shape, so a
// 0.13–0.26 result is a ~50-point gap against the same model — large enough that
// it should be explained before it is designed around.
//
// DIAGNOSTIC ONLY — env-gated, asserts nothing. The printed table is the artifact.
//
//   PHOSPHENE_DBN1_DOWNBEAT=1 \
//   swift test --package-path PhospheneEngine --filter DownbeatStreamDiagnostic
//
// Tracks default to a broken/working pair (money, billie_jean); override with
// PHOSPHENE_DBN1_TRACKS as a comma-separated list of fixture basenames.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import ML

@Suite("DownbeatStreamDiagnostic")
struct DownbeatStreamDiagnosticTests {

    @Test("DBN.1: where the downbeat signal dies — model stream vs resolver post-processing")
    func test_downbeatStreamDiagnostic() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_DBN1_DOWNBEAT"] == "1" else {
            print("[DBN.1] skipped — set PHOSPHENE_DBN1_DOWNBEAT=1 to run")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            Issue.record("no Metal device"); return
        }
        let env = ProcessInfo.processInfo.environment
        let fixturesDir = env["BEATBENCH_FIXTURES_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("phosphene_beatbench_fixtures")
        let names = (env["PHOSPHENE_DBN1_TRACKS"] ?? "money,billie_jean")
            .split(separator: ",").map(String.init)

        print("""

        ============ DBN.1 task 7 — downbeat stream vs resolver ============
        frame rate 50 fps (Beat This! hop 441 @ 22050 Hz); peak-pick = ±3-frame
        max-pool, prob > 0.5 — the same shape as the reference minimal post-processor.
        """)

        for name in names {
            guard let url = Self.locate(name: name, in: fixturesDir) else {
                print("  \(name): fixture not found in \(fixturesDir)"); continue
            }
            let samples = try Self.decodeMono22050(url: url)
            let pre = BeatThisPreprocessor()
            let (spect, frameCount) = pre.process(samples: samples, inputSampleRate: 22050.0)
            let model = try BeatThisModel(device: device)
            let (beatProbs, downbeatProbs) = try model.predict(spectrogram: spect, frameCount: frameCount)

            let beatPeaks = Self.peakPick(beatProbs)
            let dbPeaks = Self.peakPick(downbeatProbs)
            let frameRate = 50.0
            let beatTimes = beatPeaks.map { Double($0) / frameRate }
            let dbTimes = dbPeaks.map { Double($0) / frameRate }

            // Distance from each downbeat candidate to the nearest beat peak — this is
            // what the resolver's ±2-frame (40 ms) gate is applied to.
            var dists: [Double] = []
            for d in dbTimes {
                if let nearest = beatTimes.min(by: { abs($0 - d) < abs($1 - d) }) {
                    dists.append(abs(nearest - d) * 1000)
                }
            }
            let within40 = dists.filter { $0 <= 40 }.count
            let medianBeatPeriod = Self.medianIOI(beatTimes)
            // Median downbeat spacing expressed in beats — this is the quantity
            // `computeMeter` rounds to get `beatsPerBar`.
            let dbIOI = Self.medianIOI(dbTimes)
            let spacingInBeats = medianBeatPeriod > 0 ? dbIOI / medianBeatPeriod : 0

            let hiConf = downbeatProbs.filter { $0 > 0.5 }.count
            let peakMean = dbPeaks.isEmpty ? 0 : dbPeaks.map { downbeatProbs[$0] }.reduce(0, +) / Float(dbPeaks.count)

            print("""

            --- \(name) ---
              frames analysed      : \(frameCount)  (\(String(format: "%.1f", Double(frameCount) / frameRate)) s)
              beat peaks           : \(beatPeaks.count)   median period \(String(format: "%.3f", medianBeatPeriod)) s \
            (\(String(format: "%.1f", medianBeatPeriod > 0 ? 60 / medianBeatPeriod : 0)) BPM)
              downbeat peaks       : \(dbPeaks.count)   mean peak prob \(String(format: "%.3f", peakMean))
              downbeat:beat ratio  : \(String(format: "%.2f", beatPeaks.isEmpty ? 0 : Double(dbPeaks.count) / Double(beatPeaks.count)))
              frames w/ dbProb>0.5 : \(hiConf)
              median downbeat gap  : \(String(format: "%.2f", spacingInBeats)) beats  → round() = \(Int(spacingInBeats.rounded()))
              dist to nearest beat : median \(String(format: "%.1f", Self.percentile(dists, 0.5))) ms, \
            p90 \(String(format: "%.1f", Self.percentile(dists, 0.9))) ms
              survive ±40 ms gate  : \(within40)/\(dists.count) \
            (\(String(format: "%.0f", dists.isEmpty ? 0 : 100 * Double(within40) / Double(dists.count)))%)
            """)
        }
        print("""

        Read: `median downbeat gap` in beats IS what computeMeter rounds into
        `beatsPerBar`. A value near 1 means the model is emitting a downbeat on
        nearly every beat, which is a stream problem, not a snapping problem.
        ====================================================================

        """)
    }

    // MARK: - Helpers

    /// ±3-frame max-pool + >0.5 threshold, mirroring `BeatGridResolver.peakPick`
    /// (and the reference minimal post-processor) without depending on it.
    private static func peakPick(_ probs: [Float]) -> [Int] {
        var out: [Int] = []
        for i in probs.indices where probs[i] > 0.5 {
            let lo = max(0, i - 3), hi = min(probs.count - 1, i + 3)
            var maxV = probs[i]
            for j in lo...hi where probs[j] > maxV { maxV = probs[j] }
            if probs[i] == maxV { out.append(i) }
        }
        // dedup adjacent (distance <= 1), keep the higher probability
        var peaks: [Int] = []
        var k = 0
        while k < out.count {
            var best = out[k]
            var m = k + 1
            while m < out.count && out[m] - out[m - 1] <= 1 {
                if probs[out[m]] > probs[best] { best = out[m] }
                m += 1
            }
            peaks.append(best)
            k = m
        }
        return peaks
    }

    private static func medianIOI(_ times: [Double]) -> Double {
        guard times.count >= 2 else { return 0 }
        var iois: [Double] = []
        for i in 1..<times.count { iois.append(times[i] - times[i - 1]) }
        return percentile(iois, 0.5)
    }

    private static func percentile(_ v: [Double], _ q: Double) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[min(s.count - 1, max(0, Int(q * Double(s.count - 1) + 0.5)))]
    }

    private static func locate(name: String, in dir: String) -> URL? {
        let fm = FileManager.default
        for ext in ["wav", "mp3", "m4a", "flac"] {
            let p = (dir as NSString).appendingPathComponent("\(name).\(ext)")
            if fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
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
            let t = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: t.baseAddress, count: raw.count / 4))
        }
    }
}
