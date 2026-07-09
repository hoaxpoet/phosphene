// FixtureSessionCaptureGenerator — BUG-049 armed-path verification utility,
// extended at QG.1 to emit BOTH session CSVs.
//
// Generates REAL session captures (features.csv + stems.csv in SessionRecorder's
// exact schema) by running the repo's vendored tempo fixture clips through the
// PRODUCTION pipelines:
//
//   stems half (BUG-049): ffmpeg decode (the suite's standard fixture decode,
//   mono 44.1 kHz f32) → StemSeparator (MPSGraph, 10 s chunks at model rate) →
//   StemAnalyzer per 1024-sample hop (the exact `SessionPreparer.warmUpAndAnalyze`
//   framing, EMA/AGC state carried across the whole clip) → `SessionRecorder.csvRow`.
//
//   features half (QG.1): the same decoded samples → BeatGridAnalyzer (Beat This!,
//   the production cached-grid path, installed via `mir.setBeatGrid` exactly as
//   VisualizerEngine does at track start) → FFTProcessor per 1024-sample hop (the
//   live Metal FFT — never a reimplemented magnitude formula, BUG-066) →
//   `MIRPipeline.process` (the complete production FeatureVector assembler:
//   bands, deviation primitives, beat accents, grid-driven beat/bar phase, pulse,
//   tonal, structural prediction) → MoodClassifier at the production 30-frame
//   cadence (analyzeMIR) → `SessionRecorder.csvRow(features:stems:beatSync:...)`.
//
// WHY: (a) the session-content-dependent cert gates (Skein colour-freeze,
// real-stem routing) arm only when `~/Documents/phosphene_sessions` holds a real
// capture; (b) QG.1's RouteCoverageTests replay checked-in copies of these
// captures (Fixtures/route_coverage/) to assert every declared `audio_routes`
// primitive actually fires on real music. Regenerate + re-copy when the CSV
// schema appends columns.
//
// FA #27 / feedback_synthetic_audio compliant: real music clips through the
// production analysis chain — nothing hand-authored. The capture is NOT a live
// listening session (no video, no tap latency, no live perf columns — those
// cells are empty exactly as live cold-start frames are), so beat-sync and
// render-defect protocols still require real session captures.
//
// USAGE (env-gated; a normal suite pass skips it):
//   PHOSPHENE_GEN_SESSION_DIR="$HOME/Documents/phosphene_sessions" \
//     swift test --package-path PhospheneEngine --filter FixtureSessionCaptureGenerator
//
// Writes one `fixturegen-<name>/` session dir per fixture, each containing
// features.csv + stems.csv + a provenance session.log. Re-running overwrites
// in place. To refresh the checked-in route-coverage fixtures afterwards:
//   for f in love_rehab so_what there_there; do
//     cp ~/Documents/phosphene_sessions/fixturegen-$f/{features,stems}.csv \
//        PhospheneEngine/Tests/PhospheneEngineTests/Fixtures/route_coverage/$f/
//   done

import Foundation
import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

// MARK: - FixtureSessionCaptureGenerator

struct FixtureSessionCaptureGenerator {

    /// Tempo fixtures with enough instrumentation contrast that different stems
    /// lead in different windows (what the colour-freeze gate's switch needs).
    private static let fixtures = ["love_rehab.m4a", "so_what.m4a", "there_there.m4a"]

    /// Cap analysis at preview-clip length — matches the production
    /// SessionPreparer input contract and bounds MPSGraph inference time.
    private static let maxSeconds: Float = 30

    /// Analysis hop — FFTProcessor.fftSize / the live analysis cadence.
    private static let hop = 1024

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
                Issue.record("Fixture absent at \(audioURL.path) — run Scripts/fetch_tempo_fixtures.sh")
                continue
            }
            let sessionName = "fixturegen-\(audioURL.deletingPathExtension().lastPathComponent)"
            let sessionDir = outDir.appendingPathComponent(sessionName)
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

            let sampleRate = StemSeparator.modelSampleRate
            var samples = try Self.decodeMonoFloat32(url: audioURL, targetSampleRate: Int(sampleRate))
            let maxSamples = Int(Self.maxSeconds * sampleRate)
            if samples.count > maxSamples { samples = Array(samples.prefix(maxSamples)) }

            var stemRows = try generateStemRows(samples: samples, separator: separator)
            var featureRows = try generateFeatureRows(samples: samples, device: device)
            // SessionDataLoader requires features/stems row alignment; the stem
            // waveforms can run a hop short of the input (chunk-tail trim).
            let frames = min(stemRows.count, featureRows.count)
            stemRows = Array(stemRows.prefix(frames))
            featureRows = Array(featureRows.prefix(frames))
            #expect(frames > 400,
                    "\(fixture): \(frames) frames — too short to arm the session gates (need > 400)")
            try writeSession(featureRows: featureRows, stemRows: stemRows,
                             to: sessionDir, fixture: fixture)
            print("FixtureSessionCaptureGenerator: wrote \(frames) frames → \(sessionDir.path)")
        }
    }

    // MARK: - Production-pipeline replay: stems half (BUG-049)

    /// Separate (10 s chunks) → analyze per 1024-hop, returning one
    /// production-format stems.csv row per analysis frame.
    private func generateStemRows(samples: [Float], separator: StemSeparator) throws -> [String] {
        let sampleRate = StemSeparator.modelSampleRate
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
        let fps = sampleRate / Float(Self.hop)
        let sampleCount = stemWaveforms[0].count
        var rows: [String] = []
        var frame = 0
        var hopStart = 0
        while hopStart + Self.hop <= sampleCount {
            var frameWaveforms: [[Float]] = []
            for stem in stemWaveforms {
                frameWaveforms.append(Array(stem[hopStart..<hopStart + Self.hop]))
            }
            let features = analyzer.analyze(stemWaveforms: frameWaveforms, fps: fps)
            rows.append(SessionRecorder.csvRow(
                stems: features, frame: frame, wallclock: Double(frame) / Double(fps)))
            frame += 1
            hopStart += Self.hop
        }
        return rows
    }

    // MARK: - Production-pipeline replay: features half (QG.1)

    /// Beat This! grid install → FFTProcessor + MIRPipeline per 1024-hop →
    /// MoodClassifier at the 30-frame production cadence, returning one
    /// production-format features.csv row per analysis frame.
    private func generateFeatureRows(samples: [Float], device: MTLDevice) throws -> [String] {
        let sampleRate = StemSeparator.modelSampleRate
        let fps = sampleRate / Float(Self.hop)
        let deltaTime = Float(Self.hop) / sampleRate

        // Cached-grid install — the production track-start contract (Layer 4 /
        // D-153): BeatGridAnalyzer(Beat This!) on the clip, installed before the
        // first frame, so beatPhase01/barPhase01 are grid-driven, not the
        // reactive BeatPredictor fallback.
        let gridAnalyzer = try DefaultBeatGridAnalyzer(device: device)
        let grid = gridAnalyzer.analyzeBeatGrid(samples: samples, sampleRate: Double(sampleRate))

        let fft = try FFTProcessor(device: device)
        let mir = MIRPipeline(binCount: 512, sampleRate: sampleRate, fftSize: Self.hop)
        mir.setBeatGrid(grid)
        let mood = MoodClassifier()

        var rows: [String] = []
        var latestValence: Float = 0
        var latestArousal: Float = 0
        var frame = 0
        var offset = 0
        while offset + Self.hop <= samples.count {
            let window = Array(samples[offset..<offset + Self.hop])
            _ = fft.process(samples: window, sampleRate: sampleRate)
            let magnitudes = Array(fft.magnitudeBuffer.pointer)
            var fv = mir.process(
                magnitudes: magnitudes, fps: fps,
                time: Float(frame) * deltaTime, deltaTime: deltaTime)

            // Mood at the production classify cadence (analyzeMIR: every 30
            // frames, EMA-accumulated); fv carries the latest state between
            // classifications, exactly as the live engine publishes it.
            if frame % 30 == 0 {
                let input: [Float] = [
                    fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high,
                    fv.spectralCentroid, mir.rawSmoothedFlux,
                    mir.latestMajorKeyCorrelation, mir.latestMinorKeyCorrelation,
                ]
                if let state = try? mood.classify(features: input) {
                    latestValence = state.valence
                    latestArousal = state.arousal
                }
            }
            fv.valence = latestValence
            fv.arousal = latestArousal

            // BeatSyncSnapshot mirrors VisualizerEngine's per-frame construction
            // (fv-derived bar fields + grid BPM). sessionMode/lockState/driftMs
            // are live-tracker diagnostics, not routing primitives — left 0 here.
            let beatsPerBar = max(1, Int(fv.beatsPerBar.rounded()))
            let beatInBar = max(1, min(Int(fv.barPhase01 * Float(beatsPerBar)) + 1, beatsPerBar))
            let snapshot = BeatSyncSnapshot(
                barPhase01: fv.barPhase01,
                beatsPerBar: beatsPerBar,
                beatInBar: beatInBar,
                isDownbeat: beatInBar == 1,
                sessionMode: 0,
                lockState: 0,
                gridBPM: Float(grid.bpm),
                playbackTimeS: Float(mir.elapsedSeconds),
                driftMs: 0)

            rows.append(SessionRecorder.csvRow(
                features: fv, stems: .zero, beatSync: snapshot,
                frame: frame, wallclock: Double(frame) / Double(fps),
                structure: mir.latestStructuralPrediction))
            frame += 1
            offset += Self.hop
        }
        return rows
    }

    // MARK: - Session writing

    private func writeSession(featureRows: [String], stemRows: [String],
                              to sessionDir: URL, fixture: String) throws {
        // Headers come from SessionRecorder's single source (QG.1) — a private
        // copy here went stale when IFC.4 appended the instrument-family block.
        let featuresCSV = SessionRecorder.featuresCSVHeader + featureRows.joined()
        try featuresCSV.write(to: sessionDir.appendingPathComponent("features.csv"),
                              atomically: true, encoding: .utf8)
        let stemsCSV = SessionRecorder.stemsCSVHeader + stemRows.joined()
        try stemsCSV.write(to: sessionDir.appendingPathComponent("stems.csv"),
                           atomically: true, encoding: .utf8)
        let log = """
            FixtureSessionCaptureGenerator capture (BUG-049 armed-path verification; QG.1 features half)
            fixture=\(fixture) stems=StemSeparator(MPSGraph)+StemAnalyzer hop=1024
            features=BeatGridAnalyzer(BeatThis grid install)+FFTProcessor+MIRPipeline+MoodClassifier(30-frame cadence) hop=1024
            Real audio through the production analysis chain (FA #27); NOT a live \
            listening session — no video / tap latency; perf columns empty as at live cold-start.

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
