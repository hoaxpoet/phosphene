// TrunkTrajectoryReportTests — DYN.2c: what the trunk actually does, over a whole track.
//
// EVERY previous round of this feature was validated against something that was not the
// engine, and every one shipped broken:
//
//   DYN.2  — modelled by cascading a second EMA onto the already-smoothed `spectral_density`
//            COLUMN of a session CSV. The engine applies a single EMA to the RAW fraction.
//            The proxy predicted a 0.63→1.11 swing; the engine produced a flat 1.00.
//   DYN.2b — modelled the arithmetic correctly but not the WARMUP: a τ45 s normal seeded to
//            the section leg starts at exactly 1.00, so contrast cannot develop inside a
//            3-minute song. Live it spanned 1.00…1.17 and the trunk drifted with no structure.
//
// So this harness runs the REAL production objects — `LoudnessProfile.measure` for the
// offline profile and `SpectralAnalyzer` frame by frame — over a decoded FULL track, and
// reports the trunk value the shader would compute. No reconstruction, no CSV, no proxy.
//
//   SECDET_AUDIO=/path/to/track.mp3 swift test --package-path PhospheneEngine \
//     --filter TrunkTrajectoryReport
//
// Reporting, not asserting a verdict: whether the motion reads as musical is Matt's M7.
// The assertions cover only what is mechanically checkable — that the signal has range and
// is not pinned.

import Testing
import Foundation
import AVFoundation
@testable import Audio
@testable import DSP
@testable import Shared

@Suite("Trunk trajectory report (DYN.2c)")
struct TrunkTrajectoryReportTests {

    private static let fftSize = 1024

    private static func decodeMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return ([], 0)
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        guard count > 0, let channels = buffer.floatChannelData else { return ([], 0) }
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

    /// The shader's trunk formula (FractalTree.metal), kept in one place here so the report
    /// and the preset cannot drift apart silently.
    private static func trunk(sectionRatio: Float, surge: Float, arousalReach: Float) -> Float {
        func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
            let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
            return t * t * (3 - 2 * t)
        }
        let fullness = min(max(sectionRatio * 0.5, 0), 1)
        let gate = smoothstep(0.05, 0.30, surge)
        return min(max(max(0.10 * arousalReach, fullness) * gate, 0), 1)
    }

    @Test("report the trunk trajectory across a full track (SECDET_AUDIO=…)")
    func reportTrunk() throws {
        guard let path = ProcessInfo.processInfo.environment["SECDET_AUDIO"] else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let (samples, sampleRate) = try Self.decodeMono(url)
        #expect(!samples.isEmpty, "decoded no audio from \(url.path)")
        guard !samples.isEmpty else { return }

        // 1. The REAL offline profile, exactly as local-file preparation builds it —
        // UNLESS `TRUNK_PROFILE_JSON` points at a cached `metadata.json`, in which case the
        // profile is the one the LIVE path installed for that track. Measuring the profile
        // from the same audio you then rank against is the easy case; live, the profile is
        // measured from the FILE at preparation and evaluated against the TAP. This knob
        // reproduces that pairing offline.
        var profile = LoudnessProfile.measure(samples: samples, sampleRate: sampleRate)
        if let metaPath = ProcessInfo.processInfo.environment["TRUNK_PROFILE_JSON"],
           let data = FileManager.default.contents(atPath: (metaPath as NSString).expandingTildeInPath),
           let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let raw = root["loudnessProfile"] as? [String: Any],
           let db = raw["quantilesDB"] as? [Double],
           let dq = raw["densityQuantiles"] as? [Double] {
            profile = LoudnessProfile(quantilesDB: db.map(Float.init),
                                      densityQuantiles: dq.map(Float.init))
            print("  [profile] installed from cache: \(db.count) level / \(dq.count) density quantiles")
        }
        #expect(profile != nil, "measure() returned no usable profile")
        guard let profile else { return }

        // 2. The REAL analyzer, frame by frame, with that profile installed.
        let analyzer = SpectralAnalyzer(binCount: Self.fftSize / 2,
                                        sampleRate: Float(sampleRate),
                                        fftSize: Self.fftSize)
        analyzer.setLoudnessProfile(profile)
        let fft = try FFTMagnitudeKernel(fftSize: Self.fftSize)

        // HOP, and why it is a knob. The density legs are per-FRAME EMAs, so their time
        // constants scale with the analysis rate: τ_section = 1/(α·fps). This harness hops
        // a full window (43 fps at 44.1 kHz → the calibrated τ20 s / τ45 s), but the LIVE
        // path analyses at ~59.5 fps → τ14.5 s / τ32 s. That pushes the section and normal
        // legs together, which is the documented DYN.2 failure ("their ratio was a constant
        // 1.00 and the trunk never moved for a whole session"). `TRUNK_HOP` reproduces it.
        let hop = ProcessInfo.processInfo.environment["TRUNK_HOP"].flatMap { Int($0) } ?? Self.fftSize
        print("  [rate] hop \(hop) → \(String(format: "%.1f", sampleRate / Double(hop))) analysis fps")
        var trunks: [Float] = []
        var ratios: [Float] = []
        var offset = 0
        while offset + Self.fftSize <= samples.count {
            samples.withUnsafeBufferPointer { src in
                fft.windowed.withUnsafeMutableBufferPointer { dst in
                    guard let s = src.baseAddress, let d = dst.baseAddress else { return }
                    d.update(from: s.advanced(by: offset), count: Self.fftSize)
                }
            }
            fft.computeMagnitudes()
            // DYN.4 — dt is the HOP, so tau stays 20 s whatever rate this runs at.
            let result = analyzer.process(magnitudes: fft.magnitudes,
                                          deltaTime: Float(hop) / Float(sampleRate))
            // `arousal` is a mood-classifier output not modelled here; it only supplies a
            // floor (0.10×) and saturates in the body, so 1.0 is its steady-state value.
            trunks.append(Self.trunk(sectionRatio: result.sectionRatio,
                                     surge: result.surge,
                                     arousalReach: 1.0))
            ratios.append(result.sectionRatio)
            offset += hop
        }
        let fps = sampleRate / Double(hop)
        let duration = Double(samples.count) / sampleRate

        func mmss(_ s: Double) -> String {
            String(format: "%d:%04.1f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
        }
        let steps = zip(trunks, trunks.dropFirst()).map { abs($1 - $0) }
        let motion = steps.reduce(0, +) / Float(duration)
        print("""

        ── TRUNK TRAJECTORY ───────────────────────────────────────────────
        file          \(url.lastPathComponent)   \(mmss(duration))
        density q     \(profile.densityQuantiles.count) quantiles, median \(String(format: "%.4f", profile.densityQuantiles.isEmpty ? 0 : profile.densityQuantiles[LoudnessProfile.steps/2]))  (offline, full decode)
        ratio         \(String(format: "%.2f … %.2f", ratios.min() ?? 0, ratios.max() ?? 0))
        trunk         \(String(format: "%.2f … %.2f", trunks.min() ?? 0, trunks.max() ?? 0))
        motion        \(String(format: "%.4f", motion))/s   (arousal 0.011, FTR.3f failed at 0.092)
        """)
        // COLD START, at 5 s resolution. The 20 s buckets below describe a whole track;
        // they cannot show how long the tree sits at its floor before the section legs
        // (τ20 s) and the track normal have enough history to say anything. A listener
        // who watches one minute sees only this window.
        print("  cold start (first 90 s, 5 s resolution):")
        for mark in stride(from: 0.0, to: min(90.0, duration), by: 5.0) {
            let window = trunks.enumerated()
                .filter { abs(Double($0.offset) / fps - mark) <= 2.5 }
                .map(\.element)
            guard !window.isEmpty else { continue }
            let value = window.reduce(0, +) / Float(window.count)
            print(String(format: "  %6@  %.3f  %@", mmss(mark) as NSString, value,
                         String(repeating: "▉", count: Int((value * 40).rounded()))))
        }
        // How long until the canopy leaves its floor at all.
        let leaveFloor = trunks.firstIndex { $0 > 0.15 }.map { Double($0) / fps }
        print(String(format: "  time to reach 0.15: %@",
                     leaveFloor.map { String(format: "%.1f s", $0) } ?? "never"))

        for mark in stride(from: 0.0, to: duration, by: 20.0) {
            let window = trunks.enumerated()
                .filter { abs(Double($0.offset) / fps - mark) <= 2 }
                .map(\.element)
            guard !window.isEmpty else { continue }
            let value = window.reduce(0, +) / Float(window.count)
            let bar = String(repeating: "█", count: Int((value * 40).rounded()))
            print(String(format: "  %6@  %.2f  %@", mmss(mark) as NSString, value, bar))
        }
        print("───────────────────────────────────────────────────────────────────\n")

        // Mechanical claims only. "Does it read as musical" is the M7.
        let span = (trunks.max() ?? 0) - (trunks.min() ?? 0)
        #expect(span > 0.35, """
            The trunk spans only \(span) across the whole track. DYN.1e shipped a 10 % band \
            and Matt could not see it move; that is the failure this must not repeat.
            """)
        #expect(motion < 0.092, """
            Motion \(motion)/s meets or exceeds the raw-density figure that produced FTR.3f's \
            "the trunk of the tree is moving up and down constantly".
            """)
    }
}
