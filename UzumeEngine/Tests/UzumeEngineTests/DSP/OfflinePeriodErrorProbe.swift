// BUG-065 / PR.11 — is the grid's PERIOD error recoverable offline?
//
// D-206 parked phase TRK after two levers failed, on the deciding finding that only
// 15–25 % of detected onsets land within ±50 ms of a beat, so any tracker fed onset
// evidence inherits a 75–85 % off-beat rate. That kills ONLINE PHASE TRACKING. It does
// not speak to OFFLINE PERIOD REFINEMENT, which is a different question with a different
// evidence layer, and which the local-file path can afford because it holds the whole
// track at preparation time.
//
// The physics being tested. If the cached grid's period P_g differs from the track's true
// period P_t, phase error accumulates LINEARLY:
//
//     drift_rate (ms/s) = 1000 × (P_g/P_t − 1) = 1000 × (BPM_t/BPM_g − 1)
//
// So a 0.1 % BPM error yields ~1 ms/s — which over a 383 s track is 383 ms, and PR.1
// measured exactly that shape on Bowie's Low: a linear ramp on 11 of 13 segments,
// R² 0.63–0.91, both signs, implying 0.04–0.20 % period error.
//
// What this probe answers, per fixture with confirmed ground truth:
//   1. How far is the production grid's BPM from the truth, and what drift does that predict?
//   2. Does a MULTI-WINDOW estimate land closer to the truth than production's single
//      first-window decode? If yes, the error is recoverable offline and the fix is a
//      better period estimate, not a phase controller.
//   3. Or do the windows disagree with each other — in which case the tempo genuinely
//      varies (BUG-107's money case) and NO constant grid can be right, which is a
//      different and larger finding.
//
// Run: UZUME_PERIOD_PROBE=1 swift test --package-path UzumeEngine --filter OfflinePeriodErrorProbe
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import Session

@Suite("OfflinePeriodErrorProbe")
struct OfflinePeriodErrorProbe {

    private struct GroundTruth: Decodable {
        let beatsS: [Double]?
        let status: String?
        enum CodingKeys: String, CodingKey { case beatsS = "beats_s"; case status }
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
            let p = UnsafeBufferPointer(start: channels[channel], count: count)
            for i in 0..<count { mono[i] += p[i] * scale }
        }
        return (mono, format.sampleRate)
    }

    /// BPM from a least-squares fit of beat TIME against beat INDEX; the slope is the
    /// period. Not the median inter-beat interval — Beat This! emits beats on a 50 fps
    /// frame grid, so every IBI is quantised to 20 ms and the median can only take
    /// discrete values (115.38 BPM is exactly 26 frames). At ~117 BPM that quantisation
    /// is ±3.9 %, which swamps the 0.04–0.20 % period errors this probe exists to
    /// measure. Regressing over hundreds of beats averages the quantisation away.
    ///
    /// Beats are first split at gaps larger than 1.5x the running period, so a dropped
    /// or doubled beat starts a new run rather than tilting the whole fit.
    private static func bpm(_ beats: [Double]) -> Double {
        guard beats.count > 8 else { return 0 }
        var gaps = (0..<(beats.count - 1)).map { beats[$0 + 1] - beats[$0] }
        gaps.sort()
        let nominal = gaps[gaps.count / 2]
        guard nominal > 0 else { return 0 }

        // Longest run of consecutive beats spaced within 25 % of nominal.
        var bestLo = 0, bestLen = 1, lo = 0
        for i in 1..<beats.count {
            let d = beats[i] - beats[i - 1]
            if abs(d / nominal - 1) < 0.25 {
                if i - lo + 1 > bestLen { bestLen = i - lo + 1; bestLo = lo }
            } else {
                lo = i
            }
        }
        guard bestLen > 8 else { return 60.0 / nominal }
        let run = Array(beats[bestLo..<(bestLo + bestLen)])
        let n = Double(run.count)
        let meanIdx = (n - 1) / 2
        let meanT = run.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (i, t) in run.enumerated() {
            let di = Double(i) - meanIdx
            num += di * (t - meanT); den += di * di
        }
        guard den > 0, num > 0 else { return 60.0 / nominal }
        return 60.0 / (num / den)
    }

    /// Truth BPM over the SAME span as a window, so a tempo-varying track is compared
    /// like-for-like rather than against its whole-track average.
    private static func truthBPM(_ beats: [Double], from: Double, to: Double) -> Double {
        bpm(beats.filter { $0 >= from && $0 <= to })
    }


    /// F-measure at +/-70 ms, greedy one-to-one — BeatBench's headline metric, recomputed
    /// here so both grids can be scored over an IDENTICAL span.
    private static func fMeasure(reference: [Double], estimate: [Double]) -> Double {
        guard !reference.isEmpty, !estimate.isEmpty else { return 0 }
        var used = [Bool](repeating: false, count: estimate.count)
        var hits = 0
        for r in reference {
            var best = -1
            var bestD = 0.070
            for (i, e) in estimate.enumerated() where !used[i] {
                let d = abs(e - r)
                if d <= bestD { bestD = d; best = i }
            }
            if best >= 0 { used[best] = true; hits += 1 }
        }
        let p = Double(hits) / Double(estimate.count)
        let rc = Double(hits) / Double(reference.count)
        return (p + rc) > 0 ? 2 * p * rc / (p + rc) : 0
    }

    @Test("fair comparison: 30 s clamp vs whole-track, scored over the SAME span",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_FAIR_SPAN"] == "1"))
    func fairSpan() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)

        print("""

          Both grids scored over the CLAMP's span only (the first ~30 s), so the
          comparison is like-for-like. BeatBench trims the reference to each grid's own
          span, which grades the 30 s grid on 30 s and the whole-track grid on the whole
          track — not the same exam.

          track                 clampF  wholeF   clampSpan  wholeSpan  coverage
        """)
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            guard let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL)),
                  let truth = gt.beatsS, truth.count > 8 else { continue }
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            setenv("UZUME_FULLTRACK_DECODE", "0", 1)
            let clamp = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate).beats
            setenv("UZUME_FULLTRACK_DECODE", "1", 1)
            let whole = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate).beats
            setenv("UZUME_FULLTRACK_DECODE", "0", 1)
            guard let lo = clamp.first, let hi = clamp.last, hi > lo else { continue }
            let ref = truth.filter { $0 >= lo - 1 && $0 <= hi + 1 }
            let clampIn = clamp.filter { $0 >= lo - 1 && $0 <= hi + 1 }
            let wholeIn = whole.filter { $0 >= lo - 1 && $0 <= hi + 1 }
            guard ref.count > 4 else { continue }
            let trackLen = Double(audio.count) / rate
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            print(String(format: "  %@%@ %6.2f  %6.2f   %7.1fs  %8.1fs  %6.1f%%",
                         name, pad,
                         Self.fMeasure(reference: ref, estimate: clampIn),
                         Self.fMeasure(reference: ref, estimate: wholeIn),
                         hi - lo, (whole.last ?? 0) - (whole.first ?? 0),
                         (hi - lo) / trackLen * 100))
        }
        print("""

          coverage = how much of the track the 30 s clamp's grid actually spans.
        """)
    }

    @Test("offline period error: single-window vs multi-window",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_PERIOD_PROBE"] == "1"))
    func probe() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let windowSeconds = 30.0
        let offsetsFraction = [0.0, 0.2, 0.4, 0.6, 0.8]

        print("""

          BUG-065 — is the grid's period error recoverable from the whole file?
          drift_rate(ms/s) = 1000 x (BPM_truth / BPM_grid - 1)

          track                status        truthBPM  prodBPM   err%   predDrift  multiBPM   err%  spread%
        """)
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            guard let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL)),
                  let truthBeats = gt.beatsS, truthBeats.count > 8 else { continue }
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }

            let durationS = Double(audio.count) / rate
            let truth = Self.bpm(truthBeats)
            guard truth > 0 else { continue }

            // Production: ONE decode over the whole input; the model's own ~30 s window
            // (FT.4 OFF) means this is effectively the head of the track.
            let prodBPM = Self.bpm(analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate).beats)

            // Multi-window: independent 30 s decodes across the track, median of the
            // per-window BPMs. NOT the tiler — each window is a separate clean predict,
            // so this cannot inherit the tiler's beat regression (FT.4.1).
            var windowBPMs: [Double] = []
            for f in offsetsFraction {
                let startS = f * max(durationS - windowSeconds, 0)
                let lo = Int(startS * rate)
                let hi = min(lo + Int(windowSeconds * rate), audio.count)
                guard hi - lo > Int(rate * 5) else { continue }
                let slice = Array(audio[lo..<hi])
                let b = Self.bpm(analyzer.analyzeBeatGrid(samples: slice, sampleRate: rate).beats)
                if b > 20, b < 400 { windowBPMs.append(b) }
            }
            guard !windowBPMs.isEmpty else { continue }
            let sorted = windowBPMs.sorted()
            let multiBPM = sorted[sorted.count / 2]
            let spread = (sorted.last! - sorted.first!) / multiBPM * 100

            let prodErr = (truth / prodBPM - 1) * 100
            let multiErr = (truth / multiBPM - 1) * 100
            let predDrift = 1000 * (truth / prodBPM - 1)
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            let st = (gt.status ?? "?")
            let stPad = String(repeating: " ", count: max(0, 13 - st.count))
            print(String(format: "  %@%@%@%@%8.2f %8.2f %+6.2f %+9.2f %9.2f %+6.2f %7.2f",
                         name, pad, st, stPad, truth, prodBPM, prodErr, predDrift,
                         multiBPM, multiErr, spread))
        }
        // ── Low: no ground truth, so validate against the MEASURED ramp instead ──
        // PR.1 measured a per-track drift slope on Matt's session. If the ramp really is
        // a constant period error, then a better offline period estimate must differ
        // from production's by that same fraction, in that direction. Predicting a
        // number measured independently is a far stronger test than internal agreement.
        let measuredSlope: [String: Double] = [   // ms/s, PR.1 linear fit of drift_ms
            "01 - Speed Of Life": -0.697, "02 - Breaking Glass": -1.382,
            "03 - What In The World": -0.852, "04 - Sound And Vision": -1.073,
            "05 - Always Crashing In The Same Car": 0.626, "06 - Be My Wife": -0.437,
            "07 - A New Career In A New Town": 0.357, "08 - Warszawa": 0.529,
            "09 - Art Decade": 0.708, "10 - Weeping Wall": -0.082,
            "11 - Subterraneans": 0.142
        ]
        let lowDir = URL(fileURLWithPath: "/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low")
        if let lowFiles = try? FileManager.default.contentsOfDirectory(
            at: lowDir, includingPropertiesForKeys: nil) {
            print("""

              Low — predicted vs MEASURED drift (no ground truth; the ramp IS the reference)
              track                            prodBPM  multiBPM  delta%  predicted  measured  spread%
            """)
            for url in lowFiles.filter({ $0.pathExtension == "flac"
                && !$0.lastPathComponent.hasPrefix("._") })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.deletingPathExtension().lastPathComponent
                guard let measured = measuredSlope[name],
                      let (audio, rate) = try? Self.decodeMono(url: url), !audio.isEmpty
                else { continue }
                let durationS = Double(audio.count) / rate
                let prod = Self.bpm(analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate).beats)
                var wins: [Double] = []
                for f in offsetsFraction {
                    let startS = f * max(durationS - windowSeconds, 0)
                    let lo = Int(startS * rate)
                    let hi = min(lo + Int(windowSeconds * rate), audio.count)
                    guard hi - lo > Int(rate * 5) else { continue }
                    let b = Self.bpm(analyzer.analyzeBeatGrid(
                        samples: Array(audio[lo..<hi]), sampleRate: rate).beats)
                    if b > 20, b < 400 { wins.append(b) }
                }
                guard !wins.isEmpty, prod > 0 else { continue }
                let sorted = wins.sorted()
                let multi = sorted[sorted.count / 2]
                let spread = (sorted.last! - sorted.first!) / multi * 100
                let deltaPct = (multi / prod - 1) * 100
                let predicted = 1000 * (multi / prod - 1)
                let pad = String(repeating: " ", count: max(0, 32 - name.count))
                print(String(format: "  %@%@%8.2f %9.2f %+7.3f %+10.2f %+9.3f %8.2f",
                             name, pad, prod, multi, deltaPct, predicted, measured, spread))
            }
            print("""

              If the ramp is a constant period error, `predicted` should track `measured`
              in SIGN and rough MAGNITUDE. If it does not, the drift is not explained by a
              recoverable offline period error and BUG-065 needs a different mechanism.
            """)
        }

        print("""

          err%     = how far the estimate is from tapped truth (+ = estimate too SLOW)
          predDrift= ms/s of phase drift that error predicts. |predDrift| x track seconds
                     is the accumulated error; BUG-065's window is ~60 ms.
          spread%  = disagreement BETWEEN windows. Large spread = the tempo genuinely
                     varies and no constant grid can be right (BUG-107's money case).
        """)
    }
}
