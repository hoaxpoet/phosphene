// SessionRecorderTests — Validate the recorder against known inputs.
//
// This exists to answer exactly one question: if a real playback session
// produces a suspicious recording (silent stems, blank video, all-zero
// features), can we trust that the recorder is faithfully capturing what
// the app produced — i.e. the problem is in the app — or is the recorder
// itself buggy?
//
// Each test drives the recorder with KNOWN inputs and verifies the outputs
// round-trip exactly. A passing run is evidence that:
//   · CSV rows contain the exact FeatureVector/StemFeatures values passed in
//   · Stem WAV files contain the exact PCM samples passed in
//   · The video file is created and readable by AVAsset
//   · Log entries are written and preserved across finish()
//   · Session directory structure matches the documented layout
//
// If a real-world recording then shows zero features during music playback,
// the recorder is not the culprit — the VisualizerEngine audio path is.

import XCTest
import AVFoundation
import Foundation
import Metal
@testable import Shared

final class SessionRecorderTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("phosphene_recorder_tests_\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Init creates session dir with expected files

    func test_init_createsSessionDirectoryWithCSVsAndLog() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.finish()  // flush any init-time log writes

        XCTAssertTrue(FileManager.default.fileExists(atPath: recorder.sessionDir.path),
                      "Session dir must exist")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recorder.sessionDir.appendingPathComponent("features.csv").path),
            "features.csv must be created at init")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recorder.sessionDir.appendingPathComponent("stems.csv").path),
            "stems.csv must be created at init")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recorder.sessionDir.appendingPathComponent("session.log").path),
            "session.log must be created at init")
    }

    // MARK: - Features CSV round-trips known FeatureVectors exactly

    func test_recordFrame_writesFeatureVectorExactly() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))

        let f1 = FeatureVector(
            bass: 0.25, mid: 0.5, treble: 0.125,
            subBass: 0.1, lowBass: 0.2,
            beatBass: 0.75,
            time: 1.5, deltaTime: 0.016,
            accumulatedAudioTime: 3.5
        )
        let f2 = FeatureVector(
            bass: 0.9, mid: 0.1, treble: 0.4,
            beatBass: 0.0,
            time: 2.0,
            accumulatedAudioTime: 5.0
        )
        recorder.recordFrame(features: f1, stems: StemFeatures.zero)
        recorder.recordFrame(features: f2, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")

        XCTAssertEqual(rows.count, 3, "Header + 2 data rows = 3 lines")
        XCTAssertTrue(rows[0].starts(with: "frame,wallclock_s,time,deltaTime,bass,mid,treble"),
                      "CSV header must match documented schema, got: \(rows[0])")

        let row1 = rows[1].split(separator: ",").map(String.init)
        XCTAssertEqual(row1[0], "0", "frame index starts at 0")
        XCTAssertEqual(Float(row1[4]) ?? -1, 0.25, accuracy: 0.0001, "bass round-trip")
        XCTAssertEqual(Float(row1[5]) ?? -1, 0.5,  accuracy: 0.0001, "mid round-trip")
        XCTAssertEqual(Float(row1[6]) ?? -1, 0.125, accuracy: 0.0001, "treble round-trip")
        XCTAssertEqual(Float(row1[13]) ?? -1, 0.75, accuracy: 0.0001, "beatBass round-trip")
        XCTAssertEqual(Float(row1[21]) ?? -1, 3.5, accuracy: 0.0001, "accumulatedAudioTime round-trip")

        let row2 = rows[2].split(separator: ",").map(String.init)
        XCTAssertEqual(row2[0], "1", "frame index increments")
        XCTAssertEqual(Float(row2[4]) ?? -1, 0.9, accuracy: 0.0001)
    }

    // MARK: - Stems CSV round-trips known StemFeatures exactly

    func test_recordFrame_writesStemFeaturesExactly() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))

        let s1 = StemFeatures(
            vocalsEnergy: 0.3,
            drumsEnergy: 0.4, drumsBeat: 0.9,
            bassEnergy: 0.6,
            otherEnergy: 0.2
        )
        recorder.recordFrame(features: FeatureVector.zero, stems: s1)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("stems.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2, "Header + 1 data row")

        let row = rows[1].split(separator: ",").map(String.init)
        XCTAssertEqual(Float(row[2])  ?? -1, 0.4, accuracy: 0.0001, "drumsEnergy round-trip")
        XCTAssertEqual(Float(row[3])  ?? -1, 0.9, accuracy: 0.0001, "drumsBeat round-trip")
        XCTAssertEqual(Float(row[6])  ?? -1, 0.6, accuracy: 0.0001, "bassEnergy round-trip")
        XCTAssertEqual(Float(row[10]) ?? -1, 0.3, accuracy: 0.0001, "vocalsEnergy round-trip")
        XCTAssertEqual(Float(row[14]) ?? -1, 0.2, accuracy: 0.0001, "otherEnergy round-trip")
    }

    // MARK: - Stem WAV files are valid PCM and decode to the original samples

    func test_recordStemSeparation_writesWavFilesThatDecodeBackToInput() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))

        // Known non-trivial waveform: ramp up, hold, ramp down — 1 second at 44.1 kHz.
        let sampleRate = 44100
        var drums = [Float](repeating: 0, count: sampleRate)
        for i in 0..<sampleRate {
            let t = Float(i) / Float(sampleRate)
            drums[i] = sin(Float.pi * 2 * 440 * t) * 0.5   // 440 Hz sine at half amplitude
        }
        let bass = drums.map { -$0 }                      // inverted copy to distinguish channels
        let vocals = [Float](repeating: 0.25, count: sampleRate)
        let other = [Float](repeating: -0.25, count: sampleRate)

        recorder.recordStemSeparation(
            stemWaveforms: [drums, bass, vocals, other],
            sampleRate: sampleRate,
            trackTitle: "Test Track")
        recorder.finish()

        // Find the stem directory — format is stems/0000_<title>/.
        let stemsRoot = recorder.sessionDir.appendingPathComponent("stems")
        let contents = try FileManager.default.contentsOfDirectory(
            at: stemsRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(contents.count, 1, "Exactly one stem dump directory expected")
        let dumpDir = contents[0]

        for (name, expected) in [("drums", drums), ("bass", bass),
                                 ("vocals", vocals), ("other", other)] {
            let url = dumpDir.appendingPathComponent("\(name).wav")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "\(name).wav must exist")
            let decoded = try decodeWavAsFloat(url: url)
            XCTAssertEqual(decoded.count, expected.count, "\(name).wav sample count")

            // 16-bit PCM quantization introduces ~1/32767 error. Allow 2× headroom.
            let tolerance: Float = 2.0 / 32767.0
            var maxErr: Float = 0
            for i in 0..<min(decoded.count, expected.count) {
                maxErr = max(maxErr, abs(decoded[i] - expected[i]))
            }
            XCTAssertLessThan(maxErr, tolerance,
                              "\(name).wav round-trip error \(maxErr) exceeds quantization")
        }
    }

    // MARK: - Video file is created and readable

    func test_recordFrame_withCaptureTexture_producesReadableVideo() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))

        // Allocate a known capture texture and fill with a solid color pattern.
        let width = 128
        let height = 72
        let captureTex = try XCTUnwrap(recorder.ensureCaptureTexture(
            device: device, width: width, height: height,
            pixelFormat: .bgra8Unorm_srgb))
        // Fill with solid blue (BGRA=255,0,0,255).
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4 + 0] = 255   // B
            pixels[i * 4 + 1] = 0     // G
            pixels[i * 4 + 2] = 0     // R
            pixels[i * 4 + 3] = 255   // A
        }
        captureTex.replace(region: MTLRegionMake2D(0, 0, width, height),
                           mipmapLevel: 0,
                           withBytes: &pixels,
                           bytesPerRow: width * 4)

        // Write 50 frames with 50 ms spacing. The recorder defers video writer
        // initialization until 30 consecutive same-size frames have arrived
        // (to avoid locking the writer to a transient launch-time drawable
        // size); 50 frames clears that threshold with margin to spare.
        for _ in 0..<50 {
            recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
            Thread.sleep(forTimeInterval: 0.05)
        }
        recorder.finish()

        let videoURL = recorder.sessionDir.appendingPathComponent("video.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path),
                      "video.mp4 must be written")
        let size = try FileManager.default.attributesOfItem(
            atPath: videoURL.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000,
            "video.mp4 must contain encoded data (got \(size) bytes)")

        let asset = AVURLAsset(url: videoURL)
        let tracks = asset.tracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "video.mp4 must contain a video track")
        if let track = tracks.first {
            let naturalSize = track.naturalSize
            XCTAssertEqual(Int(naturalSize.width), width, "video width must match capture texture")
            XCTAssertEqual(Int(naturalSize.height), height, "video height must match capture texture")
        }
    }

    // MARK: - Log entries are preserved

    func test_log_writesTimestampedEntriesToSessionLog() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.log("track → Test Track")
        recorder.log("preset → Glass Brutalist")
        recorder.log("audio signal → active")
        recorder.finish()

        let log = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("session.log"),
            encoding: .utf8)
        XCTAssertTrue(log.contains("track → Test Track"),
                      "log must contain track entry, got: \(log)")
        XCTAssertTrue(log.contains("preset → Glass Brutalist"),
                      "log must contain preset entry")
        XCTAssertTrue(log.contains("audio signal → active"),
                      "log must contain signal entry")
        XCTAssertTrue(log.contains("SessionRecorder started"),
                      "init must log a startup line")
        XCTAssertTrue(log.contains("SessionRecorder finished"),
                      "finish must log a closing line")
    }

    // MARK: - WAV decoder (test-only)

    /// Minimal 16-bit PCM WAV decoder for validating the recorder's writer.
    private func decodeWavAsFloat(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count >= 44 else {
            throw NSError(domain: "WAV", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "WAV shorter than header"])
        }
        // Header sanity.
        let riff = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        let wave = String(data: data.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF", "WAV must start with RIFF")
        XCTAssertEqual(wave, "WAVE", "RIFF form must be WAVE")
        // PCM samples begin at offset 44 (standard WAVE fmt chunk).
        let pcmData = data.subdata(in: 44..<data.count)
        let sampleCount = pcmData.count / 2
        var samples = [Float](repeating: 0, count: sampleCount)
        pcmData.withUnsafeBytes { raw in
            let pcm = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(pcm[i]) / 32767.0
            }
        }
        return samples
    }
}
