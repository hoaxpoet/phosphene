// PR.3e — what does the adopted bar-line estimator actually do to Matt's own album?
//
// The five-suite table says take_five 0.26 -> 0.97 and seven fixtures go quiet. That is
// nine tracks of benchmark material. This asks the question that decides whether the
// change is an improvement to UZUME: on the album Matt reviewed, how many tracks get a
// bar at all, and does the meter it returns look like the music?
//
// Run: UZUME_LOW_PROBE=1 swift test --package-path UzumeEngine --filter LowBarLineProbe
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import Session

@Suite("LowBarLineProbe")
struct LowBarLineProbe {

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
            let pointer = UnsafeBufferPointer(start: channels[channel], count: count)
            for index in 0..<count { mono[index] += pointer[index] * scale }
        }
        return (mono, format.sampleRate)
    }


    @Test("PR.12 — grid coverage and cost on Low, clamped vs whole-track",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_LOW_COVERAGE"] == "1"))
    func coverage() throws {
        let dir = URL(fileURLWithPath: "/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let files = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "flac" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        print("\n  track                            len   clampSpan  cover   wholeSpan  cover   clamp_s  whole_s")
        var totalClamp = 0.0, totalWhole = 0.0
        for url in files {
            guard let (audio, rate) = try? Self.decodeMono(url: url), !audio.isEmpty else { continue }
            let len = Double(audio.count) / rate
            var t0 = Date()
            let clamp = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: false)
            let clampS = Date().timeIntervalSince(t0)
            t0 = Date()
            let whole = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            let wholeS = Date().timeIntervalSince(t0)
            totalClamp += clampS; totalWhole += wholeS
            let cs = (clamp.beats.last ?? 0) - (clamp.beats.first ?? 0)
            let ws = (whole.beats.last ?? 0) - (whole.beats.first ?? 0)
            let name = url.deletingPathExtension().lastPathComponent
            let pad = String(repeating: " ", count: max(0, 32 - name.count))
            // Downbeats per beat: >0.5 means the model's downbeat head is over-firing,
            // which counting reports faithfully and division hid behind an average.
            let dbRate = whole.beats.isEmpty ? 0
                : Double(whole.downbeats.count) / Double(whole.beats.count)
            print(String(format: "  %@%@%6.0fs %6.1f%% -> %5.1f%%  meter %d -> %d (conf %.2f)  db/beat %.2f",
                         name, pad, len, cs / len * 100, ws / len * 100,
                         clamp.beatsPerBar, whole.beatsPerBar, whole.barConfidence, dbRate))
        }
        print(String(format: "\n  TOTAL analysis time — clamped %.1f s, whole-track %.1f s (%.1fx)",
                     totalClamp, totalWhole, totalWhole / max(totalClamp, 0.001)))
    }

    @Test("bar line on Bowie's Low, before and after adoption",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_LOW_PROBE"] == "1"))
    func lowAlbum() throws {
        let dir = URL(fileURLWithPath:
            "/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let files = (try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "flac" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        print("\n  threshold = \(BarLineEstimator.declineThreshold)")
        print("  track                              bpm   OFF meter   margin   ON meter")
        var offBars = 0, onBars = 0
        for url in files {
            guard let (audio, rate) = try? Self.decodeMono(url: url), !audio.isEmpty else {
                print("  \(url.lastPathComponent) — could not decode"); continue
            }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate)
            var gaps = (0..<max(grid.beats.count - 1, 0)).map { grid.beats[$0 + 1] - grid.beats[$0] }
            gaps.sort()
            let bpm = gaps.isEmpty ? 0 : 60.0 / gaps[gaps.count / 2]
            let est = BarLineEstimator.estimate(
                beats: grid.beats,
                audio: audio,
                sampleRate: rate,
                options: .init(resampleToReferenceRate: true)
            )
            let answers = est.margin >= BarLineEstimator.declineThreshold
            // OFF = the model's downbeat head, i.e. grid.beatsPerBar; 1 means it collapsed.
            if grid.beatsPerBar > 1 { offBars += 1 }
            if answers { onBars += 1 }
            let name = url.deletingPathExtension().lastPathComponent
            let pad = String(repeating: " ", count: max(0, 34 - name.count))
            print("  \(name)\(pad) \(String(format: "%5.1f", bpm))   "
                  + "\(grid.beatsPerBar)          "
                  + "\(String(format: "%6.3f", est.margin))   "
                  + "\(answers ? String(est.beatsPerBar ?? 0) : "decline")")
        }
        print("\n  tracks with a bar — OFF: \(offBars)/\(files.count)   ON: \(onBars)/\(files.count)")
    }

    /// PR.17 — the third arm: bar line scored PER WINDOW over the whole-track grid.
    ///
    /// PR.3d measured two arms on this album and both were measured on a 30 s grid: the
    /// model's downbeat head (7 of 11 right, 4 wrong) and ONE global estimate (5 of 11,
    /// silencing two tracks that were right). PR.15 then showed bar structure is local.
    /// This asks what the windowed estimator does to Matt's own record — the measurement
    /// that has to come BEFORE any recommendation (PR.3d's standing rule).
    ///
    /// Run: UZUME_LOW_WINDOWED=1 swift test --package-path UzumeEngine --filter LowBarLineProbe
    @Test("PR.17 — windowed bar line on Low",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_LOW_WINDOWED"] == "1"))
    func lowWindowed() throws {
        let dir = URL(fileURLWithPath: "/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let files = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "flac" && !$0.lastPathComponent.hasPrefix("._") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let options = BarLineEstimator.Options(resampleToReferenceRate: true)

        print("\n  threshold \(BarLineEstimator.declineThreshold), "
              + "\(BarLineEstimator.defaultBeatsPerWindow) beats/window")
        print("  track                              beats  head  global   windowed: ans/tot  cover  meters")
        var headBars = 0, globalBars = 0, windowedBars = 0
        var totalWindowedSeconds = 0.0
        for url in files {
            guard let (audio, rate) = try? Self.decodeMono(url: url), !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard !grid.beats.isEmpty else { continue }
            let global = BarLineEstimator.estimate(
                beats: grid.beats, audio: audio, sampleRate: rate, options: options)
            let started = Date()
            let windowed = BarLineEstimator.estimateWindowed(
                beats: grid.beats, audio: audio, sampleRate: rate, options: options)
            // D-242 puts preparation on a 7.5 s/track budget, so a new per-track stage
            // states its cost rather than assuming it is free.
            let cost = Date().timeIntervalSince(started)
            totalWindowedSeconds += cost
            if grid.beatsPerBar > 1 { headBars += 1 }
            if global.isConfident { globalBars += 1 }
            if windowed.windowsAnswered > 0 { windowedBars += 1 }
            let meters = windowed.estimates.compactMap(\.beatsPerBar).map(String.init).joined(separator: ",")
            let name = url.deletingPathExtension().lastPathComponent
            let pad = String(repeating: " ", count: max(0, 34 - name.count))
            let globalText = global.beatsPerBar.map(String.init) ?? "-"
            let answered = "\(windowed.windowsAnswered)/\(windowed.windowCount)"
            print("  \(name)\(pad)"
                  + String(format: "%5d  %4d  %6@   %8@  %5.0f%%  ",
                           grid.beats.count, grid.beatsPerBar,
                           globalText as NSString, answered as NSString,
                           windowed.coverage * 100)
                  + (meters.isEmpty ? "-" : meters))
        }
        print("\n  tracks with any bar — head \(headBars)/\(files.count), "
              + "global \(globalBars)/\(files.count), windowed \(windowedBars)/\(files.count)")
        print(String(format: "  windowed estimator cost: %.1f s total, %.2f s/track (D-242 budget 7.5 s/track, all stages)",
                     totalWindowedSeconds, totalWindowedSeconds / Double(max(files.count, 1))))
    }
}
