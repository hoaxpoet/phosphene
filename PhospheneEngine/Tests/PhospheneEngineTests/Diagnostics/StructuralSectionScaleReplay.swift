// StructuralSectionScaleReplay — CLEAN.6.2 / BUG-042 validation diagnostic.
//
// Replays the repo's vendored tempo fixtures through the PRODUCTION structural
// path — ffmpeg decode (mono f32 @ 48 kHz) → FFTProcessor (512 bins) →
// MIRPipeline.process → StructuralAnalyzer — and reports the detected section
// boundaries. This is the "after" half of BUG-042's before/after structural-stream
// artifact: the documented "before" (note-scale geometry) machine-gunned a
// boundary every ~1.3–2.5 s (30 in ~50 s on Love Rehab, KNOWN_ISSUES §BUG-042);
// the section-scale decimation should yield 0–few boundaries on a 30 s clip,
// none closer than the 8 s minimum section.
//
// FA #27 / feedback_synthetic_audio compliant: real music clips through the real
// production FFT + MIR chain — nothing hand-authored.
//
// Env-gated (opt-in; a normal suite pass skips it — it needs the gitignored tempo
// fixtures + a Metal device + ffmpeg):
//   PHOSPHENE_STRUCT_REPLAY=1 swift test --package-path PhospheneEngine \
//     --filter StructuralSectionScaleReplay
//
// NOTE: a 30 s preview clip rarely contains a true musical section change, so
// 0 boundaries is a PASS (the point is the absence of note-scale junk, not a
// specific count). The musical-feel half (does orchestrator preset-switching
// land on real sections) is Matt's live read — this diagnostic cannot judge it.

import Foundation
import Metal
import Testing
@testable import DSP
@testable import Audio

// MARK: - StructuralSectionScaleReplay

struct StructuralSectionScaleReplay {

    private static let fixtures = ["love_rehab.m4a", "so_what.m4a", "there_there.m4a"]
    private static let sampleRate: Float = 48_000          // production tap rate

    @Test("Section-scale structural replay on real fixtures (env-gated: PHOSPHENE_STRUCT_REPLAY)")
    func replaySectionScale() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_STRUCT_REPLAY"] == "1" else {
            print("StructuralSectionScaleReplay: PHOSPHENE_STRUCT_REPLAY != 1, skipping")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("StructuralSectionScaleReplay: no Metal device, skipping")
            return
        }

        // Diagnostic override: replay one arbitrary capture (e.g. a session's
        // raw_tap.wav — a full real track, not a 30 s preview) to validate the
        // POSITIVE direction (does it find real 15–60 s sections?). No assertions
        // (arbitrary input); prints the boundary table for offline diagnosis.
        if let wav = ProcessInfo.processInfo.environment["PHOSPHENE_REPLAY_WAV"], !wav.isEmpty {
            let sr = Float(ProcessInfo.processInfo.environment["PHOSPHENE_REPLAY_SR"] ?? "") ?? 44_100
            let url = URL(fileURLWithPath: (wav as NSString).expandingTildeInPath)
            let samples = try Self.decodeMonoFloat32(url: url, targetSampleRate: Int(sr))
            print("=== BUG-042 floor/threshold sweep: \(url.lastPathComponent) @ \(Int(sr)) Hz, "
                  + String(format: "%.0fs ===", Float(samples.count) / sr))
            print("  (production default = floor 0.02, threshold 1.5; lower = more sensitive)")
            for th: Float in [1.5, 0.8] {
                for fl: Float in [0.02, 0.01, 0.005, 0.002, 0.0] {
                    let mir = MIRPipeline(sampleRate: sr, structuralAnalyzer:
                        StructuralAnalyzer(minNoveltyFloor: fl, thresholdMultiplier: th))
                    let (boundaries, _, conf) = try runThrough(samples: samples, device: device, sampleRate: sr, mir: mir)
                    print(String(format: "  thr=%.1f floor=%.3f → %2d boundary(ies)  conf=%.2f  @[%@]s",
                                 th, fl, boundaries.count, conf,
                                 boundaries.prefix(14).map { String(format: "%.0f", $0) }.joined(separator: ",") as NSString))
                }
            }
            return
        }

        let fixturesDir = URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tempo")

        print("=== BUG-042 section-scale structural replay (after) ===")
        for fixture in Self.fixtures {
            let url = fixturesDir.appendingPathComponent(fixture)
            guard FileManager.default.fileExists(atPath: url.path) else {
                Issue.record("Fixture absent: \(url.path)")
                continue
            }
            let (boundaries, durationS, finalConf) = try replay(url: url, device: device, sampleRate: Self.sampleRate)

            // Inter-boundary gaps (section durations between detected boundaries).
            let gaps = zip(boundaries.dropFirst(), boundaries).map { $0 - $1 }
            let minGap = gaps.min() ?? .infinity
            let gapStr = gaps.isEmpty ? "—" : gaps.map { String(format: "%.1f", $0) }.joined(separator: ", ")
            print(String(
                format: "%-16@  %.1fs clip  →  %d boundary(ies) @ [%@]  gaps=[%@]s  conf=%.2f",
                fixture as NSString, durationS, boundaries.count,
                boundaries.map { String(format: "%.1f", $0) }.joined(separator: ", ") as NSString,
                gapStr as NSString, finalConf))

            // Section-scale sanity (NOT a feel judgement): no note-scale machine-gun.
            // A 30 s clip must not produce more than ~3 sections, and any two
            // boundaries must be ≥ 6 s apart (the 8 s minPeakDistance minus the
            // 4 s-kernel / 0.5 s-bucket localization slack).
            #expect(boundaries.count <= 3,
                    "\(fixture): \(boundaries.count) boundaries on a \(Int(durationS))s clip — note-scale junk regressed (BUG-042).")
            #expect(minGap >= 6.0,
                    "\(fixture): boundaries \(String(format: "%.1f", minGap))s apart — under the 8 s minimum section (BUG-042).")
        }
        print("=== before (documented, note-scale): ~1.3–2.5 s cadence, 30 boundaries in ~50 s ===")
    }

    // MARK: - Production-path replay

    /// Decode → FFT (1024/512) → MIRPipeline.process per 1024-hop, returning the
    /// detected boundary timestamps, the clip duration, and the final confidence.
    private func replay(url: URL, device: MTLDevice, sampleRate: Float) throws -> (boundaries: [Float], durationS: Float, finalConf: Float) {
        let samples = try Self.decodeMonoFloat32(url: url, targetSampleRate: Int(sampleRate))
        return try runThrough(samples: samples, device: device, sampleRate: sampleRate,
                              mir: MIRPipeline(sampleRate: sampleRate))
    }

    /// Drive a decoded clip through FFT → the given MIRPipeline, returning the
    /// detected boundary timestamps, the clip duration, and the final confidence.
    private func runThrough(samples: [Float], device: MTLDevice, sampleRate: Float, mir: MIRPipeline)
        throws -> (boundaries: [Float], durationS: Float, finalConf: Float) {
        let fft = try FFTProcessor(device: device)
        var magnitudes = [Float](repeating: 0, count: FFTProcessor.binCount)
        let hop = FFTProcessor.fftSize                 // 1024
        let dt = Float(hop) / sampleRate               // feed interval
        let fps = 1.0 / dt
        var elapsed: Float = 0
        var finalConf: Float = 0
        var start = 0
        while start + hop <= samples.count {
            let frame = Array(samples[start..<start + hop])
            _ = fft.process(samples: frame, sampleRate: sampleRate)
            for bin in 0..<FFTProcessor.binCount { magnitudes[bin] = fft.magnitudeBuffer[bin] }
            _ = mir.process(magnitudes: magnitudes, fps: fps, time: elapsed, deltaTime: dt)
            finalConf = mir.latestStructuralPrediction.confidence
            elapsed += dt
            start += hop
        }
        return (mir.structuralAnalyzer.boundaryTimestamps, elapsed, finalConf)
    }

    // MARK: - Fixture decode (suite-standard ffmpeg path)

    private static func decodeMonoFloat32(url: URL, targetSampleRate: Int) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error", "-i", url.path,
            "-ac", "1", "-ar", "\(targetSampleRate)", "-f", "f32le", "-"
        ]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        try proc.run()
        let raw = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "StructuralSectionScaleReplay", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed for \(url.path)"])
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            Array(UnsafeBufferPointer(start: buf.bindMemory(to: Float.self).baseAddress, count: count))
        }
    }
}
