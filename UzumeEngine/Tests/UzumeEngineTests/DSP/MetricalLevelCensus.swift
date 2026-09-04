// PR.3c — is there a metrical-level problem, and on what?
//
// D-210 declined to correct the grid's metrical level on the grounds that its two
// exhibits pulled in opposite directions: "money wants halving at 116 BPM and bleed
// wants doubling at 115 — same tempo, opposite corrections". BOTH references were
// revised afterwards (BUG-102.1 / BUG-102.2, 2026-08-27): money 60.97 -> 121.06 and
// bleed 226.72 -> 115.38. This census re-asks the question against what the ground
// truth says NOW, before any corrector is designed.
//
// Run: UZUME_LEVEL_CENSUS=1 swift test --package-path UzumeEngine --filter MetricalLevelCensus
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import Session

@Suite("MetricalLevelCensus")
struct MetricalLevelCensus {

    private struct GroundTruth: Decodable {
        enum CodingKeys: String, CodingKey {
            case beatsS = "beats_s"
            case meterFromTaps = "meter_from_taps"
            case tapBpm = "tap_bpm"
            case status, source
        }
        let beatsS: [Double]?
        let meterFromTaps: Int?
        let tapBpm: Double?
        let status: String?
        let source: String?
    }

    /// Production-faithful decode: native rate, manual channel average — byte-identical
    /// to `AudioDecode.monoFloat32` in BeatBench and to the local-file path in
    /// `SessionTypes`. An `AVAudioConverter` mono downmix is NOT the same thing and moved
    /// bleed's margin across the decline threshold when this probe first used one.
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
            let pointer = UnsafeBufferPointer(start: channels[channel], count: count)
            for index in 0..<count { mono[index] += pointer[index] * scale }
        }
        return (mono, format.sampleRate)
    }

    private static func medianBPM(_ beats: [Double]) -> Double {
        guard beats.count > 4 else { return 0 }
        var gaps = (0..<(beats.count - 1)).map { beats[$0 + 1] - beats[$0] }
        gaps.sort()
        let ibi = gaps[gaps.count / 2]
        return ibi > 0 ? 60.0 / ibi : 0
    }

    /// How the grid's level relates to the reference's: 1x, 2x, 0.5x, or neither.
    private static func levelLabel(grid: Double, truth: Double) -> String {
        guard grid > 0, truth > 0 else { return "n/a" }
        let ratio = grid / truth
        for (factor, name) in [(1.0, "correct"), (2.0, "DOUBLE"), (0.5, "HALF"),
                               (3.0, "3x"), (1.0 / 3.0, "1/3x")] {
            if abs(ratio / factor - 1.0) < 0.06 { return name }
        }
        return String(format: "other %.3fx", ratio)
    }

    @Test("grid level vs ground-truth level, per fixture",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_LEVEL_CENSUS"] == "1"))
    func census() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)

        print("\n  track                truth_bpm  status            grid_bpm  level")
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(
                of: ".groundtruth.json", with: "")
            guard let gt = try? JSONDecoder().decode(GroundTruth.self,
                                                     from: Data(contentsOf: gtURL)),
                  let truthBeats = gt.beatsS, truthBeats.count > 4 else { continue }
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL,
                  let (audio, rate) = try? Self.decodeMono(url: audioURL), !audio.isEmpty
            else {
                print("  \(name)  — fixture missing, not measured")
                continue
            }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate)
            let est = BarLineEstimator.estimate(
                beats: grid.beats,
                audio: audio,
                sampleRate: rate,
                options: .init(resampleToReferenceRate: true)
            )
            let truthBPM = Self.medianBPM(truthBeats)
            let gridBPM = Self.medianBPM(grid.beats)
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            print("  \(name)\(pad) \(String(format: "%8.2f", truthBPM))  "
                  + "\(gt.status ?? "?")\(String(repeating: " ", count: max(0, 18 - (gt.status ?? "?").count)))"
                  + "\(String(format: "%8.2f", gridBPM))  \(Self.levelLabel(grid: gridBPM, truth: truthBPM))"
                  + "   meter \(gt.meterFromTaps.map(String.init) ?? "-")  gridMeter \(grid.beatsPerBar)"
                  + "   | \(Int(rate))Hz margin \(String(format: "%6.3f", est.margin))"
                  + " -> \(est.beatsPerBar.map(String.init) ?? "decline")"
                  + " \(est.margin >= BarLineEstimator.declineThreshold ? "ANSWER" : "")")
        }
    }
}
