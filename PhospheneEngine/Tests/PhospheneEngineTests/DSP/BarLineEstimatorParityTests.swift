// BarLineEstimatorParityTests — FT.3 task 4's gate: the Swift port must reproduce the
// Python reference's per-track margins to within 1e-3.
//
// A re-derivation that "looks right" is not acceptable (the D-077 lesson), so this test
// compares the four per-meter margins on every ground-truthed track, not just the meter
// each side picked — a port can pick the same meter for the wrong reasons.
//
// ENV-GATED: it needs the full-track beats dump and the out-of-repo audio fixtures.
//
//   mkdir -p /tmp/barprobe
//   PHOSPHENE_FT1_FULLTRACK=1 PHOSPHENE_BEATS_DUMP=/tmp/barprobe \
//     swift test --package-path PhospheneEngine --filter FullTrackMeter
//   ~/phosphene-ml-env/bin/python tools/barline_parity.py \
//     --beats-dir /tmp/barprobe --fixtures ~/phosphene_beatbench_fixtures \
//     --out /tmp/barprobe/parity.json
//   PHOSPHENE_BARLINE_PARITY=/tmp/barprobe/parity.json \
//     swift test --package-path PhospheneEngine --filter BarLineParity

import Testing
import Foundation
@testable import DSP

@Suite("BarLineParity")
struct BarLineEstimatorParityTests {

    static let tolerance = 1e-3

    struct Reference: Decodable {
        let meter: Int
        let phase: Int
        let margin: Double
        let gap: Double
        let margins: [String: Double]
        let truthMeter: Int?
        let beats: Int

        enum CodingKeys: String, CodingKey {
            case meter, phase, margin, gap, margins, beats
            case truthMeter = "truth_meter"
        }
    }

    struct BeatsDump: Decodable {
        let track: String
        let beats: [Double]
    }

    @Test("Swift margins match the Python reference to 1e-3")
    func test_pythonParity() throws {
        guard let parityPath = ProcessInfo.processInfo.environment["PHOSPHENE_BARLINE_PARITY"] else {
            print("[FT.3] BarLineParity skipped — set PHOSPHENE_BARLINE_PARITY=<parity.json>")
            return
        }
        let parityURL = URL(fileURLWithPath: parityPath)
        let reference = try JSONDecoder().decode(
            [String: Reference].self, from: Data(contentsOf: parityURL)
        )
        let beatsDir = ProcessInfo.processInfo.environment["PHOSPHENE_BEATS_DUMP"]
            .map { URL(fileURLWithPath: $0) } ?? parityURL.deletingLastPathComponent()
        let fixtures = ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("phosphene_beatbench_fixtures")

        #expect(!reference.isEmpty, "parity.json has no tracks")
        var worst = 0.0
        var worstTrack = "—"
        var compared = 0

        print("\n  FT.3 task 4 — Python -> Swift parity (margins, sum_margin, deterministic null)")
        print("  \(pad("track", 22)) \(pad("meter", 12)) \(pad("phase", 12)) max |Δmargin|")

        for (track, expected) in reference.sorted(by: { $0.key < $1.key }) {
            let dumpURL = beatsDir.appendingPathComponent("\(track).beats.json")
            guard let dumpData = try? Data(contentsOf: dumpURL),
                  let dump = try? JSONDecoder().decode(BeatsDump.self, from: dumpData) else {
                print("  \(pad(track, 22)) beats dump missing — not compared")
                continue
            }
            guard let audioURL = Self.locate(track, in: fixtures),
                  let audio = try? Self.decodeMono22050(url: audioURL) else {
                print("  \(pad(track, 22)) fixture missing — not compared")
                continue
            }

            let estimate = BarLineEstimator.estimate(beats: dump.beats, audio: audio)
            var trackWorst = 0.0
            for (meterKey, expectedMargin) in expected.margins {
                guard let meter = Int(meterKey), let actual = estimate.marginsByMeter[meter] else {
                    Issue.record("\(track): no Swift margin for meter \(meterKey)")
                    continue
                }
                trackWorst = max(trackWorst, abs(actual - expectedMargin))
            }
            if trackWorst > worst { worst = trackWorst; worstTrack = track }
            compared += 1

            // The margins are the gate; the decisions must also agree.
            let swiftMeter = estimate.beatsPerBar ?? Self.argmaxMeter(estimate.marginsByMeter)
            let swiftPhase = estimate.barLinePhase
            #expect(trackWorst <= Self.tolerance,
                    "\(track): max |Δmargin| \(trackWorst) exceeds \(Self.tolerance)")
            #expect(swiftMeter == expected.meter, "\(track): meter \(swiftMeter) vs \(expected.meter)")
            if estimate.isConfident {
                #expect(swiftPhase == expected.phase,
                        "\(track): phase \(String(describing: swiftPhase)) vs \(expected.phase)")
            }
            print("  \(pad(track, 22)) \(pad("\(swiftMeter) / \(expected.meter)", 12)) "
                  + "\(pad("\(swiftPhase.map(String.init) ?? "—") / \(expected.phase)", 12)) "
                  + String(format: "%.3e", trackWorst))
        }

        print("  compared \(compared) tracks; worst |Δmargin| \(String(format: "%.3e", worst))"
              + " on \(worstTrack) (gate \(Self.tolerance))\n")
        #expect(compared > 0, "parity ran against zero tracks — the gate proved nothing")
    }

    // MARK: - Helpers

    private static func argmaxMeter(_ margins: [Int: Double]) -> Int {
        BarLineEstimator.meters.max { (margins[$0] ?? 0) < (margins[$1] ?? 0) } ?? 4
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private static func locate(_ name: String, in dir: String) -> URL? {
        for ext in ["wav", "mp3", "m4a", "flac"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// Same ffmpeg invocation as `FullTrackMeterTests` and `barline_probe.decode`, so the
    /// Python and Swift arms analyse bit-identical samples and the gate measures the port
    /// rather than two decoders.
    private static func decodeMono22050(url: URL) throws -> [Float] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-loglevel", "error", "-i", url.path,
                             "-ac", "1", "-ar", "22050", "-f", "f32le", "-"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        var raw = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            raw.append(chunk)
        }
        process.waitUntilExit()
        return raw.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
