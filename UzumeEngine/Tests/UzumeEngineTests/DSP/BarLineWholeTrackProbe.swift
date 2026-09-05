// PR.15 — give BarLineEstimator the input its own documentation specifies.
//
// `BarLineEstimator.estimate`'s doc comment: "beats: … Typically `BeatGrid.beats` from a
// full-track decode (`BeatThisTiledInference`), NOT a 30 s window."
//
// In production it has never had that. `applyBarLineEstimate` receives `grid.beats` from
// the clamped predict, so FT.3's calibration, FT.4's A/B, FT.4.1's split and PR.3d's
// adoption attempt ALL fed it ~40–60 beats when it was designed for ~300–700. The four
// "failed attempts" on the bar problem share that confound, and PR.12 removed it.
//
// The estimator scores four meter hypotheses against a permutation null. Null-corrected
// margin grows with the number of observations, so more beats should mean higher margins
// and fewer declines — the decline rate was never a property of the music alone.
//
//   UZUME_BARLINE_WHOLETRACK=1 swift test --package-path UzumeEngine --filter BarLineWholeTrackProbe
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import Session

@Suite("BarLineWholeTrackProbe")
struct BarLineWholeTrackProbe {

    private struct GroundTruth: Decodable {
        let meterFromTaps: Int?
        let status: String?
        enum CodingKeys: String, CodingKey {
            case meterFromTaps = "meter_from_taps"
            case status
        }
    }

    /// Production-faithful decode: native rate, manual channel average.
    private static func decodeMono(url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return ([], 0) }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return ([], 0) }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channels[0], count: count)), format.sampleRate)
        }
        var mono = [Float](repeating: 0, count: count)
        let scale = 1.0 / Float(channelCount)
        for channel in 0..<channelCount {
            let ptr = UnsafeBufferPointer(start: channels[channel], count: count)
            for i in 0..<count { mono[i] += ptr[i] * scale }
        }
        return (mono, format.sampleRate)
    }



    /// PR.16 task 1 — the per-window margin distribution, LABELLED correct/incorrect
    /// against the tapped meter, so `declineThreshold` can be re-derived for windowed
    /// scoring the way FT.3 derived it for global scoring: the objective
    /// (correct kept − incorrect admitted) plateaus over an interval containing no
    /// observation, and the threshold is that interval's midpoint.
    ///
    /// The shipping 1.54 was fitted to ONE-ANSWER-PER-TRACK margins and is the wrong
    /// operating point here — PR.15 measured bleed 1.179, bohemian_rhapsody 1.419 and
    /// solsbury_hill 1.412 sitting just under it with no answer at all.
    @Test("per-window margin distribution, labelled",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_THRESHOLD"] == "1"))
    func thresholdDerivation() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)
        let beatsPerWindow = 80

        // (margin, isCorrect?) — nil isCorrect = track has no tapped meter, so the window
        // is neither correct nor incorrect and only informs the "never answer here" side.
        var samples: [(margin: Double, correct: Bool?)] = []

        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard grid.beats.count > beatsPerWindow else { continue }
            var start = 0
            while start + beatsPerWindow <= grid.beats.count {
                let slice = Array(grid.beats[start..<(start + beatsPerWindow)])
                let est = BarLineEstimator.estimate(
                    beats: slice, audio: audio, sampleRate: rate, options: opts)
                let correct: Bool? = gt?.meterFromTaps.map { est.beatsPerBar == $0 }
                samples.append((est.margin, correct))
                start += beatsPerWindow
            }
        }

        // Sweep every observed margin as a candidate threshold.
        let candidates = samples.map(\.margin).sorted()
        print("\n  Per-window threshold sweep — \(samples.count) windows\n")
        print("  threshold   kept  correct  INCORRECT  objective")
        var best: (thr: Double, objective: Int) = (0, Int.min)
        for cand in candidates {
            let kept = samples.filter { $0.margin >= cand }
            let correct = kept.filter { $0.correct == true }.count
            let incorrect = kept.filter { $0.correct == false }.count
            let objective = correct - incorrect
            if objective > best.objective { best = (cand, objective) }
        }
        // Print the interesting band around the optimum.
        for cand in candidates where abs(cand - best.thr) < 1.0 {
            let kept = samples.filter { $0.margin >= cand }
            let correct = kept.filter { $0.correct == true }.count
            let incorrect = kept.filter { $0.correct == false }.count
            print(String(format: "  %9.3f  %5d  %7d  %9d  %+9d",
                         cand, kept.count, correct, incorrect, correct - incorrect))
        }
        print("""

          best objective \(best.objective) first reached at margin \(String(format: "%.3f", best.thr))
          shipping threshold 1.54 keeps: \
        \(samples.filter { $0.margin >= 1.54 }.filter { $0.correct == true }.count) correct, \
        \(samples.filter { $0.margin >= 1.54 }.filter { $0.correct == false }.count) incorrect
        """)
    }

    /// Is bar structure LOCAL? Score the estimator over successive ~40 s windows of the
    /// whole-track beat sequence. If per-window margins are strong where the single global
    /// margin is weak, the bar is a local property and one answer per track is the wrong
    /// output shape — the same lesson tempo taught (record it over the duration, do not
    /// average it into one number).
    @Test("bar line per window vs one global answer",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_WINDOWED"] == "1"))
    func windowed() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)
        let thr = BarLineEstimator.declineThreshold
        let beatsPerWindow = 80          // ~40 s at 120 BPM

        print("\n  Per-window bar line (\(beatsPerWindow) beats/window). threshold = \(thr)\n")
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard grid.beats.count > beatsPerWindow else { continue }

            let global = BarLineEstimator.estimate(
                beats: grid.beats, audio: audio, sampleRate: rate, options: opts)
            var answers: [Int] = []
            var margins: [Double] = []
            var start = 0
            while start + beatsPerWindow <= grid.beats.count {
                let slice = Array(grid.beats[start..<(start + beatsPerWindow)])
                let est = BarLineEstimator.estimate(
                    beats: slice, audio: audio, sampleRate: rate, options: opts)
                margins.append(est.margin)
                if est.margin >= thr, let bpb = est.beatsPerBar { answers.append(bpb) }
                start += beatsPerWindow
            }
            var hist: [Int: Int] = [:]
            for a in answers { hist[a, default: 0] += 1 }
            let windows = max(margins.count, 1)
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            print("  \(name)\(pad) tapped \(gt?.meterFromTaps.map(String.init) ?? "-")"
                  + "  global \(String(format: "%6.3f", global.margin))"
                  + " -> \(global.margin >= thr ? String(global.beatsPerBar ?? 0) : "decline")"
                  + "  |  windows \(windows), answered \(answers.count)"
                  + ", max margin \(String(format: "%6.3f", margins.max() ?? 0))"
                  + ", answers \(hist.sorted { $0.key < $1.key })")
        }
    }

    @Test("bar line: 30 s beats vs whole-track beats",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_WHOLETRACK"] == "1"))
    func probe() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)
        let thr = BarLineEstimator.declineThreshold

        print("""

          BarLineEstimator with the input it was designed for. threshold = \(thr)

          track                tapped   30s: beats  margin  answer |  whole: beats  margin  answer
        """)
        var answered30 = 0, answeredWhole = 0, correct30 = 0, correctWhole = 0, total = 0
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }

            let clampCount = min(audio.count, Int(30 * rate))
            let g30 = analyzer.analyzeBeatGrid(
                samples: Array(audio[0..<clampCount]), sampleRate: rate, wholeTrack: false)
            let gWhole = analyzer.analyzeBeatGrid(
                samples: audio, sampleRate: rate, wholeTrack: true)
            let e30 = BarLineEstimator.estimate(
                beats: g30.beats, audio: audio, sampleRate: rate, options: opts)
            let eWhole = BarLineEstimator.estimate(
                beats: gWhole.beats, audio: audio, sampleRate: rate, options: opts)

            func verdict(_ e: BarLineEstimate) -> String {
                e.margin >= thr ? "\(e.beatsPerBar.map(String.init) ?? "?")" : "decline"
            }
            total += 1
            if e30.margin >= thr { answered30 += 1 }
            if eWhole.margin >= thr { answeredWhole += 1 }
            if let tapped = gt?.meterFromTaps {
                if e30.margin >= thr, e30.beatsPerBar == tapped { correct30 += 1 }
                if eWhole.margin >= thr, eWhole.beatsPerBar == tapped { correctWhole += 1 }
            }
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            let tapped = gt?.meterFromTaps.map(String.init) ?? "-"
            print("  \(name)\(pad) tapped \(tapped)"
                  + "  |  30s: \(g30.beats.count) beats "
                  + "margin \(String(format: "%7.3f", e30.margin)) -> \(verdict(e30))"
                  + "  |  whole: \(gWhole.beats.count) beats "
                  + "margin \(String(format: "%7.3f", eWhole.margin)) -> \(verdict(eWhole))")
        }
        print("""

          answered:  30 s \(answered30)/\(total)   whole-track \(answeredWhole)/\(total)
          correct (vs tapped meter, where one exists):  30 s \(correct30)   whole-track \(correctWhole)
        """)
    }
}
