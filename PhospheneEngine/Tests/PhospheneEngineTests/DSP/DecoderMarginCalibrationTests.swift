// DecoderMarginCalibrationTests — DBN.2: set the decline threshold from data.
//
// D-207 requires the decoder to decline when it cannot tell what the bar is, and
// requires the threshold to be "set from the margin's measured distribution across
// the 9 ground-truthed tracks — from data, not taste". This measures that
// distribution by running the decoder on real Beat This! activations.
//
// This does NOT wire the decoder into `BeatGridResolver` — that is DBN.3. It reads
// activations and calls the decoder directly, so no shipped behaviour changes.
//
// DIAGNOSTIC ONLY — env-gated, asserts nothing.
//
//   PHOSPHENE_DBN2_CALIBRATE=1 \
//   swift test --package-path PhospheneEngine --filter DecoderMarginCalibration

import Testing
import Foundation
import Metal
@testable import DSP
@testable import ML

@Suite("DecoderMarginCalibration")
struct DecoderMarginCalibrationTests {

    /// Ground truth meters from `Tests/Fixtures/beatbench/groundtruth/` as recorded in
    /// the GT.3 baseline. `nil` = no stable meter in the ground truth.
    static let truth: [(name: String, meter: Int?, bpm: Double)] = [
        ("billie_jean", 4, 117.44),
        ("money", 7, 60.97),
        ("solsbury_hill", 7, 102.44),
        ("take_five", 5, 167.07),
        ("bohemian_rhapsody", 4, 71.10),
        ("bleed", 4, 226.72),
        ("pyramid_song", nil, 66.60),
        ("yyz", nil, 272.27),
        ("clair_de_lune", nil, 49.91)
    ]

    @Test("DBN.2: meter-margin distribution across the ground-truthed catalogue")
    func test_marginCalibration() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_DBN2_CALIBRATE"] == "1" else {
            print("[DBN.2] skipped — set PHOSPHENE_DBN2_CALIBRATE=1 to run")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else { Issue.record("no Metal"); return }
        let dir = ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("phosphene_beatbench_fixtures")

        let decoder = BeatActivationDecoder()
        print("""

        ===== DBN.2 margin calibration — decoder on real activations =====
        decoder defaults; incumbent grid BPM used as the tempo hint.
        \(String(repeating: "-", count: 78))
        track                 truth  decoded   margin      per-meter logLik
        """)

        var correct: [Double] = []
        var wrong: [Double] = []
        var noTruth: [Double] = []

        for entry in Self.truth {
            guard let url = Self.locate(entry.name, in: dir) else {
                print("  \(entry.name): fixture missing"); continue
            }
            let samples = try Self.decodeMono22050(url: url)
            let (spect, frames) = BeatThisPreprocessor().process(samples: samples, inputSampleRate: 22050.0)
            let model = try BeatThisModel(device: device)
            let (beatProbs, downbeatProbs) = try model.predict(spectrogram: spect, frameCount: frames)

            // Tempo hint = the incumbent resolver's own estimate, which is what DBN.3
            // will feed it. Using ground-truth BPM here would flatter the decoder.
            let incumbent = BeatGridResolver.resolve(
                beatProbs: beatProbs, downbeatProbs: downbeatProbs, frameRate: 50.0
            )
            guard incumbent.bpm > 0 else { print("  \(entry.name): no incumbent BPM"); continue }

            let r = decoder.decode(beatProbs: beatProbs, downbeatProbs: downbeatProbs,
                                   frameRate: 50.0, tempoHintBPM: incumbent.bpm)
            let ll = r.perMeterLogLikelihood.sorted { $0.key < $1.key }
                .map { "\($0.key):\(String(format: "%.0f", $0.value))" }.joined(separator: " ")
            let decoded = r.beatsPerBar.map(String.init) ?? "—"
            let truthStr = entry.meter.map(String.init) ?? "—"
            print(String(format: "  %-20@ %5@  %7@  %.5f   %@",
                         entry.name as NSString, truthStr as NSString,
                         decoded as NSString, r.meterMargin, ll as NSString))

            if let t = entry.meter {
                if r.beatsPerBar == t { correct.append(r.meterMargin) } else { wrong.append(r.meterMargin) }
            } else {
                noTruth.append(r.meterMargin)
            }
        }

        func summarise(_ label: String, _ v: [Double]) {
            guard !v.isEmpty else { print("  \(label): none"); return }
            let s = v.sorted()
            print(String(format: "  %-24@ n=%d  min %.5f  median %.5f  max %.5f",
                         label as NSString, v.count, s.first!, s[s.count / 2], s.last!))
        }
        print("\n  --- margin by outcome (this is what sets the threshold) ---")
        summarise("meter CORRECT", correct)
        summarise("meter WRONG", wrong)
        summarise("no stable truth meter", noTruth)
        print("""

          A usable threshold separates CORRECT's low end from WRONG's high end. If the
          distributions overlap, the margin is not a sufficient decline signal on its
          own and D-207's decline path needs a different discriminator — say so rather
          than picking a number that splits the difference.
        ==================================================================

        """)
    }

    /// Why does money decode as 4 when its bar is 7?
    ///
    /// The tempo hint is NOT the cause — money's ground truth records `tap_bpm 60.97` but
    /// both reference backends put the real pulse at ~122 BPM and label the taps
    /// "double the tapped pulse (×2.01)", with `meter_note` "beats tapped at HALF the bar
    /// pulse, so the bar is 7". The incumbent hint (~116–123) therefore already sits on
    /// the true pulse and the ±10 % band contains it.
    ///
    /// The remaining suspect is the two-stream observation model (spec §5.1). When the
    /// downbeat stream is dense — DBN.1 measured a confident downbeat on 90 % of money's
    /// beats — a small meter labels a larger *fraction* of beats as downbeats, so it
    /// collects more `log(d)` reward and eats less `log(1−d)` penalty. If that is the
    /// mechanism, the preference for small meters should grow with `downbeatWeight`, and
    /// the meters should converge as it goes to zero.
    @Test("DBN.2: is money's meter collapse driven by downbeatWeight, not the tempo hint?")
    func test_moneyMeterCollapse() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_DBN2_CALIBRATE"] == "1" else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { Issue.record("no Metal"); return }
        let dir = ProcessInfo.processInfo.environment["BEATBENCH_FIXTURES_DIR"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("phosphene_beatbench_fixtures")
        guard let url = Self.locate("money", in: dir) else { Issue.record("no fixture"); return }

        let samples = try Self.decodeMono22050(url: url)
        let (spect, frames) = BeatThisPreprocessor().process(samples: samples, inputSampleRate: 22050.0)
        let model = try BeatThisModel(device: device)
        let (beatProbs, downbeatProbs) = try model.predict(spectrogram: spect, frameCount: frames)
        let incumbent = BeatGridResolver.resolve(
            beatProbs: beatProbs, downbeatProbs: downbeatProbs, frameRate: 50.0
        )
        print("""

        ===== money: meter collapse diagnosis =====
        truth: bar = 7 beats of the ~122 BPM pulse (taps are half-time at 60.97).
        incumbent grid BPM \(String(format: "%.2f", incumbent.bpm)) — already on the true pulse.
        """)

        print("\n  -- downbeatWeight sweep (tempo hint = incumbent) --")
        for weight in [0.0, 0.5, 1.0, 2.0, 5.0, 10.0] {
            var tunables = BeatActivationDecoder.Tunables()
            tunables.downbeatWeight = weight
            tunables.meterMarginThreshold = 0        // report the raw winner
            let r = BeatActivationDecoder(tunables: tunables).decode(
                beatProbs: beatProbs, downbeatProbs: downbeatProbs,
                frameRate: 50.0, tempoHintBPM: incumbent.bpm
            )
            let ll = r.perMeterLogLikelihood.sorted { $0.key < $1.key }
                .map { "\($0.key):\(String(format: "%.0f", $0.value))" }.joined(separator: " ")
            print(String(format: "   w=%5.1f  winner=%@   %@",
                         weight, String(describing: r.beatsPerBar) as NSString, ll as NSString))
        }

        // If the hint were the problem, forcing the half-time pulse would help. It should not.
        print("\n  -- tempo hint forced to the half-time tap pulse (60.97) --")
        var tunables = BeatActivationDecoder.Tunables()
        tunables.meterMarginThreshold = 0
        let halfTime = BeatActivationDecoder(tunables: tunables).decode(
            beatProbs: beatProbs, downbeatProbs: downbeatProbs, frameRate: 50.0, tempoHintBPM: 60.97
        )
        let hll = halfTime.perMeterLogLikelihood.sorted { $0.key < $1.key }
            .map { "\($0.key):\(String(format: "%.0f", $0.value))" }.joined(separator: " ")
        print("   winner=\(String(describing: halfTime.beatsPerBar))   \(hll)")
        print("\n===========================================\n")
    }

    // MARK: - Helpers

    private static func locate(_ name: String, in dir: String) -> URL? {
        for ext in ["wav", "mp3", "m4a", "flac"] {
            let p = (dir as NSString).appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
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
