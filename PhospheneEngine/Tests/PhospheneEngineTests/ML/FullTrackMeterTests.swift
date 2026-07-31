// FullTrackMeterTests — FT.1's payoff measurement, and the D-208 amendment's test.
//
// Every meter measurement in the beat-sync program so far came from the first 30 s of a
// track, because `BeatThisModel.tMax = 1500`. money's meter was decided from **51 beats
// of a 380-second track**. Meter is a periodicity question, and 51 beats is a materially
// weaker problem than the ~700 a full track offers.
//
// D-208 originally concluded that categories 2 and 4 "need a changed premise". That was
// amended: the 30 s window is an untested confound, and this is the test. If odd meters
// stay broken with full-track context, the premise really is exhausted and the
// model-family question becomes real. If they improve, DBN.3 comes back to life.
//
// DIAGNOSTIC ONLY — env-gated, asserts nothing. The printed table is the artifact.
//
//   PHOSPHENE_FT1_FULLTRACK=1 \
//   swift test --package-path PhospheneEngine --filter FullTrackMeter

import Testing
import Foundation
import Metal
@testable import DSP
@testable import ML

@Suite("FullTrackMeter")
struct FullTrackMeterTests {

    /// Ground-truth meters from `Tests/Fixtures/beatbench/groundtruth/`; nil = no stable
    /// meter. money and solsbury_hill are 7 of the FAST pulse — their tapped BPM is
    /// half-time (see `money.groundtruth.json` `meter_note`).
    static let catalogue: [(name: String, meter: Int?)] = [
        ("billie_jean", 4), ("money", 7), ("solsbury_hill", 7), ("take_five", 5),
        ("bohemian_rhapsody", 4), ("bleed", 4),
        ("pyramid_song", nil), ("yyz", nil), ("clair_de_lune", nil)
    ]

    @Test("FT.1: 30 s window vs full-track tiling — does meter improve?")
    func test_fullTrackMeter() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_FT1_FULLTRACK"] == "1" else {
            print("[FT.1] skipped — set PHOSPHENE_FT1_FULLTRACK=1 to run")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else { Issue.record("no Metal"); return }
        let dir = ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("phosphene_beatbench_fixtures")
        let model = try BeatThisModel(device: device)
        let decoder = BeatActivationDecoder()

        print("""

        ============ FT.1 — 30 s window vs full-track tiling ============
        resolver = BeatGridResolver (incumbent peak-pick); decoder = BeatActivationDecoder
        (DBN.2, declines below its margin threshold — shown as "—").
        \(String(repeating: "-", count: 96))
        track                truth   30s:res  30s:dec   full:res  full:dec   frames    windows
        """)

        var improved: [String] = []
        var regressed: [String] = []

        for entry in Self.catalogue {
            guard let url = Self.locate(entry.name, in: dir) else {
                print("  \(entry.name): fixture missing"); continue
            }
            let samples = try Self.decodeMono22050(url: url)
            let (spect, frames) = BeatThisPreprocessor().process(samples: samples, inputSampleRate: 22050.0)

            // --- 30 s window (what every prior measurement used) ---
            let shortFrames = min(frames, BeatThisModel.tMax)
            let shortSpect = Array(spect[0..<(shortFrames * BeatThisModel.inputMels)])
            let shortAct = try model.predict(spectrogram: shortSpect, frameCount: shortFrames)
            let shortGrid = BeatGridResolver.resolve(
                beatProbs: shortAct.beats, downbeatProbs: shortAct.downbeats, frameRate: 50.0
            )
            let shortDec = decoder.decode(
                beatProbs: shortAct.beats, downbeatProbs: shortAct.downbeats,
                frameRate: 50.0, tempoHintBPM: max(shortGrid.bpm, 1)
            )

            // --- full track (FT.1) ---
            let fullAct = try BeatThisTiledInference.predictFullTrack(
                model: model, spectrogram: spect, frameCount: frames
            )
            let fullGrid = BeatGridResolver.resolve(
                beatProbs: fullAct.beats, downbeatProbs: fullAct.downbeats, frameRate: 50.0
            )
            let fullDec = decoder.decode(
                beatProbs: fullAct.beats, downbeatProbs: fullAct.downbeats,
                frameRate: 50.0, tempoHintBPM: max(fullGrid.bpm, 1)
            )

            let windows = BeatThisTiledInference.windowStarts(frameCount: frames).count
            func mark(_ value: Int?) -> String {
                guard let truth = entry.meter else { return value.map(String.init) ?? "—" }
                guard let value else { return "—" }
                return "\(value)\(value == truth ? "✓" : "✗")"
            }
            print(String(format: "  %-20@ %5@   %7@  %7@   %8@  %8@   %6d %6d",
                         entry.name as NSString,
                         (entry.meter.map(String.init) ?? "—") as NSString,
                         mark(shortGrid.beatsPerBar) as NSString,
                         mark(shortDec.beatsPerBar) as NSString,
                         mark(fullGrid.beatsPerBar) as NSString,
                         mark(fullDec.beatsPerBar) as NSString,
                         frames, windows))

            if let truth = entry.meter {
                let wasRight = shortGrid.beatsPerBar == truth || shortDec.beatsPerBar == truth
                let nowRight = fullGrid.beatsPerBar == truth || fullDec.beatsPerBar == truth
                if !wasRight && nowRight { improved.append(entry.name) }
                if wasRight && !nowRight { regressed.append(entry.name) }
            }
        }

        print("""
        \(String(repeating: "-", count: 96))
          improved with full-track context : \(improved.isEmpty ? "none" : improved.joined(separator: ", "))
          regressed                        : \(regressed.isEmpty ? "none" : regressed.joined(separator: ", "))

          This is the D-208 amendment's test. "none improved" means the 30 s window was
          NOT the confound and the evidence really is thin — the model-family question
          then becomes real. Anything improved means DBN.3 returns unchanged.
        ==================================================================

        """)
    }

    // MARK: - Helpers

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
