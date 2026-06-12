// FixtureSessionCaptureGenerator — BUG-049 armed-path verification utility.
//
// Generates REAL session captures (stems.csv in SessionRecorder's exact schema) by
// running the repo's vendored tempo fixture clips through the PRODUCTION stem
// pipeline: ffmpeg decode (the suite's standard fixture decode, mono 44.1 kHz f32) →
// StemSeparator (MPSGraph, 10 s chunks at model rate) → StemAnalyzer per 1024-sample
// hop (the exact `SessionPreparer.warmUpAndAnalyze` framing, EMA/AGC state carried
// across the whole clip) → `SessionRecorder.csvRow` (the production CSV writer).
//
// WHY: the session-content-dependent cert gates (Skein colour-freeze, real-stem
// routing) arm only when `~/Documents/phosphene_sessions` holds a real capture.
// After BUG-049 they skip LOUDLY instead of going red when none exists — but a
// machine with no captures (fresh checkout, pruned Documents, CI) can then never
// exercise their armed path. This generator arms them from repo fixtures alone.
//
// FA #27 / feedback_synthetic_audio compliant: real music clips through the
// production separation + analysis chain — nothing hand-authored. The capture is
// NOT a live listening session (no features.csv, no video, no tap latency), so it
// arms stem-routing gates only; beat-sync and render-defect protocols still
// require real session captures.
//
// USAGE (env-gated; a normal suite pass skips it):
//   PHOSPHENE_GEN_SESSION_DIR="$HOME/Documents/phosphene_sessions" \
//     swift test --package-path PhospheneEngine --filter FixtureSessionCaptureGenerator
//
// Writes one `fixturegen-<name>/` session dir per fixture, each containing
// stems.csv + a provenance session.log. Re-running overwrites in place.

import Foundation
import Metal
import Testing
@testable import DSP
@testable import ML
@testable import Shared

// MARK: - FixtureSessionCaptureGenerator

struct FixtureSessionCaptureGenerator {

    /// Tempo fixtures with enough instrumentation contrast that different stems
    /// lead in different windows (what the colour-freeze gate's switch needs).
    private static let fixtures = ["love_rehab.m4a", "so_what.m4a", "there_there.m4a"]

    /// Cap analysis at preview-clip length — matches the production
    /// SessionPreparer input contract and bounds MPSGraph inference time.
    private static let maxSeconds: Float = 30

    @Test("Generate real-audio session captures from tempo fixtures (env-gated: PHOSPHENE_GEN_SESSION_DIR)")
    func generateFixtureSessionCaptures() throws {
        guard let outBase = ProcessInfo.processInfo.environment["PHOSPHENE_GEN_SESSION_DIR"],
              !outBase.isEmpty else {
            print("FixtureSessionCaptureGenerator: PHOSPHENE_GEN_SESSION_DIR not set, skipping")
            return
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("FixtureSessionCaptureGenerator: no Metal device, skipping")
            return
        }
        let outDir = URL(fileURLWithPath: (outBase as NSString).expandingTildeInPath)
        let fixturesDir = URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()  // Diagnostics/
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo")

        let separator = try StemSeparator(device: device)
        for fixture in Self.fixtures {
            let audioURL = fixturesDir.appendingPathComponent(fixture)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                Issue.record("Fixture absent at \(audioURL.path)")
                continue
            }
            let sessionName = "fixturegen-\(audioURL.deletingPathExtension().lastPathComponent)"
            let sessionDir = outDir.appendingPathComponent(sessionName)
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            let rows = try generateRows(audioURL: audioURL, separator: separator)
            #expect(rows.count > 400,
                    "\(fixture): \(rows.count) frames — too short to arm the session gates (need > 400)")
            try writeSession(rows: rows, to: sessionDir, fixture: fixture)
            print("FixtureSessionCaptureGenerator: wrote \(rows.count) frames → \(sessionDir.path)")
        }
    }

    // MARK: - Production-pipeline replay

    /// Decode → separate (10 s chunks) → analyze per 1024-hop, returning one
    /// production-format stems.csv row per analysis frame.
    private func generateRows(audioURL: URL, separator: StemSeparator) throws -> [String] {
        let sampleRate: Float = StemSeparator.modelSampleRate
        var samples = try Self.decodeMonoFloat32(url: audioURL, targetSampleRate: Int(sampleRate))
        let maxSamples = Int(Self.maxSeconds * sampleRate)
        if samples.count > maxSamples { samples = Array(samples.prefix(maxSamples)) }

        // Separate in ≤10 s chunks (the separator's output-buffer capacity);
        // trim each chunk's output to its input length to drop tail zero-pad.
        let chunkLen = 441_000
        var stemWaveforms: [[Float]] = [[], [], [], []]
        var offset = 0
        while offset < samples.count {
            let end = min(offset + chunkLen, samples.count)
            let chunk = Array(samples[offset..<end])
            guard chunk.count >= 4096 else { break }
            let result = try separator.separate(audio: chunk, channelCount: 1, sampleRate: sampleRate)
            let count = min(min(result.sampleCount, chunk.count), separator.stemBuffers[0].capacity)
            for i in 0..<4 {
                stemWaveforms[i].append(contentsOf: separator.stemBuffers[i].pointer.prefix(count))
            }
            offset = end
        }

        // Per-hop analysis — `SessionPreparer.warmUpAndAnalyze` framing, but
        // capturing EVERY frame instead of only the warmed-up last one.
        let analyzer = StemAnalyzer(sampleRate: sampleRate)
        let hop = 1024
        let fps = sampleRate / Float(hop)
        let sampleCount = stemWaveforms[0].count
        var rows: [String] = []
        var frame = 0
        var hopStart = 0
        while hopStart + hop <= sampleCount {
            var frameWaveforms: [[Float]] = []
            for stem in stemWaveforms {
                frameWaveforms.append(Array(stem[hopStart..<hopStart + hop]))
            }
            let features = analyzer.analyze(stemWaveforms: frameWaveforms, fps: fps)
            rows.append(SessionRecorder.csvRow(
                stems: features, frame: frame, wallclock: Double(frame) / Double(fps)))
            frame += 1
            hopStart += hop
        }
        return rows
    }

    // MARK: - Session writing

    /// stems.csv header — mirrors `SessionRecorder.createFiles()`'s `stemsHeader`
    /// verbatim (it is a function-local literal there). Consumers index columns
    /// by NAME (`loadStemFrames`), so a future appended column cannot break this;
    /// renaming an existing column would, and would equally break every recorded
    /// historical capture.
    private static let stemsHeader = """
        frame,wallclock_s,\
        drumsEnergy,drumsBeat,drumsBand0,drumsBand1,\
        bassEnergy,bassBeat,bassBand0,bassBand1,\
        vocalsEnergy,vocalsBeat,vocalsBand0,vocalsBand1,\
        otherEnergy,otherBeat,otherBand0,otherBand1,\
        drumsEnergyRel,drumsEnergyDev,\
        bassEnergyRel,bassEnergyDev,\
        vocalsEnergyRel,vocalsEnergyDev,\
        otherEnergyRel,otherEnergyDev,\
        drumsOnsetRate,drumsCentroid,drumsAttackRatio,drumsEnergySlope,\
        bassOnsetRate,bassCentroid,bassAttackRatio,bassEnergySlope,\
        vocalsOnsetRate,vocalsCentroid,vocalsAttackRatio,vocalsEnergySlope,\
        otherOnsetRate,otherCentroid,otherAttackRatio,otherEnergySlope,\
        vocalsPitchHz,vocalsPitchConfidence

        """

    private func writeSession(rows: [String], to sessionDir: URL, fixture: String) throws {
        let csv = Self.stemsHeader + rows.joined()
        try csv.write(to: sessionDir.appendingPathComponent("stems.csv"),
                      atomically: true, encoding: .utf8)
        let log = """
            FixtureSessionCaptureGenerator capture (BUG-049 armed-path verification)
            fixture=\(fixture) pipeline=StemSeparator(MPSGraph)+StemAnalyzer hop=1024
            Real audio through the production analysis chain (FA #27); NOT a live \
            listening session — no features.csv / video / tap latency.

            """
        try log.write(to: sessionDir.appendingPathComponent("session.log"),
                      atomically: true, encoding: .utf8)
    }

    // MARK: - Fixture decode (suite-standard ffmpeg path)

    private static func decodeMonoFloat32(url: URL, targetSampleRate: Int) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error",
            "-i", url.path,
            "-ac", "1",
            "-ar", "\(targetSampleRate)",
            "-f", "f32le", "-"
        ]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        try proc.run()
        let raw = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(
                domain: "FixtureSessionCaptureGenerator",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed for \(url.path)"]
            )
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
    }
}
