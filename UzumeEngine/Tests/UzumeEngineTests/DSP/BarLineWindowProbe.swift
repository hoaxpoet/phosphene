// Temporary PR.3 probe — does the per-beat analysis window's DURATION change the
// estimator's margins? `nFFT = 2048` is fixed in SAMPLES, so the window is 93 ms at
// the 22050 Hz the threshold was calibrated on and ~46 ms at the 44.1 kHz production
// feeds it. Run: UZUME_BARLINE_WINDOW_PROBE=1 swift test --filter BarLineWindowProbe
import Testing
import Foundation
import AVFoundation
@testable import DSP
import Metal
import Session

@Suite("BarLineWindowProbe")
struct BarLineWindowProbe {

    private struct BeatsDump: Decodable { let beats: [Double] }

    private static func decodeMono(url: URL, rate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: rate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: file.processingFormat, to: outFmt),
              let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: inBuf)
        let cap = AVAudioFrameCount(Double(file.length) * rate / file.processingFormat.sampleRate) + 4096
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return [] }
        var done = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if done { status.pointee = .endOfStream; return nil }
            done = true; status.pointee = .haveData; return inBuf
        }
        guard let ch = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    @Test("PR.3 arms A/B", .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_WINDOW_PROBE"] == "1"))
    func probe() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let thr = BarLineEstimator.declineThreshold

        let arms: [(String, Double, BarLineEstimator.Options)] = [
            ("legacy @22050 (calibration)", 22050, .legacy),
            ("legacy @44100 (production) ", 44100, .legacy),
            ("A: resample only          ", 44100, .init(resampleToReferenceRate: true)),
            ("B: full-beat only         ", 44100, .init(fullBeatWindow: true)),
            ("A+B  (beat avg, all feats)", 44100, .init(resampleToReferenceRate: true, fullBeatWindow: true)),
            ("A+C  (beat avg, chroma only)", 44100, .init(resampleToReferenceRate: true, fullBeatWindow: true, beatAveragedChromaOnly: true))
        ]
        print("\n  threshold = \(thr)")
        let names = ["billie_jean", "bleed", "bohemian_rhapsody", "clair_de_lune",
                     "around_the_world", "giorgio_by_moroder", "dance_yrself_clean",
                     "girl_from_ipanema"]
        var kept = [String: Int]()
        for name in names {
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL,
                  let native = try? Self.decodeMono(url: audioURL, rate: 44100), !native.isEmpty
            else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: native, sampleRate: 44100)
            guard grid.beats.count > 14 else { continue }
            print("\n  \(name)  (\(grid.beats.count) beats)")
            for (label, rate, opts) in arms {
                guard let audio = try? Self.decodeMono(url: audioURL, rate: rate), !audio.isEmpty
                else { continue }
                let e = BarLineEstimator.estimate(
                    beats: grid.beats, audio: audio, sampleRate: rate, options: opts)
                let verdict = e.margin >= thr ? "ANSWER" : "decline"
                if verdict == "ANSWER" { kept[label, default: 0] += 1 }
                print("    \(label)  meter \(e.beatsPerBar.map(String.init) ?? "-")"
                      + "  phase \(e.barLinePhase.map(String.init) ?? "-")"
                      + "  margin \(String(format: "%7.3f", e.margin))  \(verdict)")
            }
        }
        print("\n  ANSWERED counts:")
        for (label, _, _) in arms { print("    \(label)  \(kept[label] ?? 0)") }
    }
}
