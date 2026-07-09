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

    /// Columns appended after the PERF.2-pass block, shifting every pre-existing from-end
    /// cell offset: the FBS Stage 1 pulse pair (`pulse_phase01,pulse_amp01`, D-153) followed
    /// by the Skein.5.2 structural trio (`section_index,section_start_s,section_confidence`).
    private let structTail = 7

    /// TONAL (D-178): 5 columns appended after everything else
    /// (`tonal_phase_fifths,tonal_phase_thirds,tonal_consonance,tonal_tension,harmonic_flux`),
    /// shifting every pre-existing from-end offset by another 5.
    private let tonalTail = 5

    /// QG.1: 10 primitive columns appended after TONAL (`bass_att,mid_att,treble_att,
    /// mid_rel,mid_dev,treb_rel,treb_dev,mid_att_rel,treb_att_rel,beats_until_next`) so
    /// route-coverage replay reaches every FeatureVector primitive presets consume,
    /// shifting every pre-existing from-end offset by another 10.
    private let qg1Tail = 10

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

    // MARK: - frame_cpu_ms / frame_gpu_ms / per-subsystem / render-loop / ray-march pass columns
    //
    // Combined appended tail (newest last): `pulse_phase01,pulse_amp01` (FBS Stage 1 /
    // D-153), `section_index,section_start_s,section_confidence` (Skein.5.2), then
    // `pulse_beat_index,pulse_regional_blend01` (FBS.S5 / D-158) —
    //   cells[count - 1] = pulse_regional_blend01   cells[count - 5] = section_index
    //   cells[count - 2] = pulse_beat_index         cells[count - 6] = pulse_amp01
    //   cells[count - 3] = section_confidence       cells[count - 7] = pulse_phase01
    //   cells[count - 4] = section_start_s
    // TONAL (D-178) then appended 5 more columns after all of the above, so
    // every from-end offset in this file is now additionally shifted by
    // `tonalTail` (5): the pulse/section tests read `count - tonalTail - N`,
    // the timing tests read `count - tonalTail - structTail - N`.
    // The offsets below are relative to `count - tonalTail - structTail`.
    //
    // CSV column layout from the end after PERF.2-pass (BUG-019 instrumentation):
    //   cells[count -  1] = post_process_pass_ms    (PERF.2-pass)
    //   cells[count -  2] = ssgi_pass_ms            (PERF.2-pass)
    //   cells[count -  3] = lighting_pass_ms        (PERF.2-pass)
    //   cells[count -  4] = gbuffer_pass_ms         (PERF.2-pass)
    //   cells[count -  5] = renderframe_cpu_ms      (PERF.2-render)
    //   cells[count -  6] = encode_cpu_ms           (PERF.2-render)
    //   cells[count -  7] = mood_classifier_ms      (PERF.1)
    //   cells[count -  8] = pitch_tracker_ms        (PERF.1)
    //   cells[count -  9] = beat_detector_ms        (PERF.1)
    //   cells[count - 10] = stem_analyzer_ms        (PERF.1)
    //   cells[count - 11] = mir_pipeline_ms         (PERF.1)
    //   cells[count - 12] = cached_bass_proportion  (CSP.3)
    //   cells[count - 13] = track_elapsed_s         (CSP.3)
    //   cells[count - 14] = frame_gpu_ms            (DM.3a)
    //   cells[count - 15] = frame_cpu_ms            (DM.3a)

    func test_featuresHeader_includesFrameTimingColumns() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let header = csv.split(separator: "\n").first ?? ""
        XCTAssertTrue(header.contains("frame_cpu_ms,frame_gpu_ms,track_elapsed_s,cached_bass_proportion"),
                      "features.csv header must contain DM.3a+CSP.3 timing block in order, got: \(header)")
        XCTAssertTrue(header.contains(
            "mir_pipeline_ms,stem_analyzer_ms,beat_detector_ms,pitch_tracker_ms,mood_classifier_ms"),
                      "features.csv header must contain the PERF.1 timing block, got: \(header)")
        XCTAssertTrue(header.contains("encode_cpu_ms,renderframe_cpu_ms"),
                      "features.csv header must contain the PERF.2-render timing block, got: \(header)")
        XCTAssertTrue(header.contains(
            "gbuffer_pass_ms,lighting_pass_ms,ssgi_pass_ms,post_process_pass_ms"),
                      "features.csv header must contain the PERF.2-pass timing block, got: \(header)")
        XCTAssertTrue(header.hasSuffix(
            "pulse_phase01,pulse_amp01,section_index,section_start_s,section_confidence,"
            + "pulse_beat_index,pulse_regional_blend01,"
            + "tonal_phase_fifths,tonal_phase_thirds,tonal_consonance,tonal_tension,harmonic_flux,"
            + "bass_att,mid_att,treble_att,mid_rel,mid_dev,treb_rel,treb_dev,"
            + "mid_att_rel,treb_att_rel,beats_until_next"),
                      "features.csv header must end with the FBS pulse pair + the Skein.5.2 "
                      + "structural block + the FBS.S5 pulse tail + the TONAL block (D-178) + the "
                      + "QG.1 primitive tail, got: \(header)")
    }

    // MARK: - BUG-039 — video writer death → segment-rolling recovery

    /// The live death certificate (session `2026-06-10T17-50-56Z`): the writer
    /// left `.writing` mid-session (AVFoundation -11800 / undocumented
    /// OSStatus -16341) and video stayed dead for the rest of the session.
    /// Recovery contract: the dead partial is RETAINED, a new segment file
    /// (`video_2.mp4`) starts within a frame, and both files are readable.
    /// The death is simulated by cancelling the live writer (status leaves
    /// `.writing`, same condition the recovery path checks).
    func test_videoWriterDeath_rollsToNewSegment_bothFilesReadable() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device")
        }
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir, videoEnabled: true))
        let width = 128, height = 72
        let captureTex = try XCTUnwrap(recorder.ensureCaptureTexture(
            device: device, width: width, height: height,
            pixelFormat: .bgra8Unorm_srgb))
        var pixels = [UInt8](repeating: 128, count: width * height * 4)
        captureTex.replace(region: MTLRegionMake2D(0, 0, width, height),
                           mipmapLevel: 0, withBytes: &pixels, bytesPerRow: width * 4)

        // Phase 1: enough frames to lock + write segment 1.
        for _ in 0..<45 {
            recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
            Thread.sleep(forTimeInterval: 0.04)
        }
        // Kill the writer so status leaves .writing WITH the partial retained —
        // matching the field failure (a .failed writer leaves its file; note
        // cancelWriting() would DELETE it, which is why it isn't used here).
        // Executed on the recorder's own queue to avoid racing in-flight appends.
        recorder.queue.sync {
            recorder.videoInput?.markAsFinished()
            let sema = DispatchSemaphore(value: 0)
            recorder.videoWriter?.finishWriting { sema.signal() }
            _ = sema.wait(timeout: .now() + 5)
        }

        // Phase 2: more frames — recovery must roll to video_2.mp4 and resume.
        for _ in 0..<45 {
            recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
            Thread.sleep(forTimeInterval: 0.04)
        }
        recorder.finish()

        let seg1 = recorder.sessionDir.appendingPathComponent("video.mp4")
        let seg2 = recorder.sessionDir.appendingPathComponent("video_2.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: seg1.path),
                      "the dead partial must be retained")
        XCTAssertTrue(FileManager.default.fileExists(atPath: seg2.path),
                      "recording must resume into a new segment after writer death")
        let tracks2 = AVURLAsset(url: seg2).tracks(withMediaType: .video)
        XCTAssertFalse(tracks2.isEmpty, "the recovery segment must contain a video track")
        // The recovery must be logged for diagnosability.
        let log = try String(contentsOf: recorder.sessionDir.appendingPathComponent("session.log"),
                             encoding: .utf8)
        XCTAssertTrue(log.contains("BUG-039 recovery"),
                      "the restart must be visible in session.log")
        // CLEAN.3.6 invariant: appends RESUMED after the roll (running ⟺ actually-writing),
        // and finish() reports the real video outcome — a recovered session is never a
        // silent "ran but wrote nothing".
        XCTAssertGreaterThan(recorder.videoFramesAppended, 0,
                             "video appends must resume after recovery")
        XCTAssertTrue(log.contains("SessionRecorder finished") && log.contains("appended /"),
                      "finish() must report the video-writing outcome")
        XCTAssertFalse(log.contains("invariant VIOLATED"),
                       "a recovered session is not a silent stop (restart is a logged cause)")
    }

    /// CLEAN.3.6: the running-vs-actually-writing invariant predicate. Pure, GPU-free —
    /// exercises the silent-stop signature and every excluded (explained) case directly.
    func test_bug039Invariant_silentStopPredicate() {
        let overThreshold = SessionRecorder.videoSilentStopFrameThreshold + 1
        // Silent stop: locked + appended, then stalled long before end, no logged cause.
        XCTAssertTrue(SessionRecorder.isSilentVideoStop(
            videoLocked: true, framesAppended: 120, restarts: 0, disabled: false,
            framesSinceLastAppend: overThreshold))
        // Healthy: appended within the throttle window of the end.
        XCTAssertFalse(SessionRecorder.isSilentVideoStop(
            videoLocked: true, framesAppended: 1000, restarts: 0, disabled: false,
            framesSinceLastAppend: 2))
        // Explained stops are NOT invariant violations:
        XCTAssertFalse(SessionRecorder.isSilentVideoStop(
            videoLocked: true, framesAppended: 120, restarts: 1, disabled: false,
            framesSinceLastAppend: overThreshold), "a restart is a logged cause")
        XCTAssertFalse(SessionRecorder.isSilentVideoStop(
            videoLocked: true, framesAppended: 120, restarts: 0, disabled: true,
            framesSinceLastAppend: overThreshold), "budget-exhausted disable is a logged cause")
        // Never locked (e.g. dims never stabilized) → no invariant to violate.
        XCTAssertFalse(SessionRecorder.isSilentVideoStop(
            videoLocked: false, framesAppended: 0, restarts: 0, disabled: false,
            framesSinceLastAppend: overThreshold))
    }

    // MARK: - CLEAN.3.8 disk-full / write-failure graceful degradation (GAP-6)

    /// The pure capacity predicate: enough space passes, low space fails, unknown is permissive.
    func test_diskGuard_capacityPredicate() {
        let need = SessionRecorder.minFreeBytesForRecording
        XCTAssertTrue(SessionRecorder.hasSufficientDiskSpace(availableBytes: need, required: need))
        XCTAssertTrue(SessionRecorder.hasSufficientDiskSpace(availableBytes: need + 1, required: need))
        XCTAssertFalse(SessionRecorder.hasSufficientDiskSpace(availableBytes: need - 1, required: need))
        XCTAssertTrue(SessionRecorder.hasSufficientDiskSpace(availableBytes: nil, required: need),
                      "unknown capacity is permissive — never refuse recording on a query failure")
    }

    /// Honest stop: once halted (the disk-full code path), no further rows are written and
    /// recordFrame does not crash — partial artifacts are retained, not corrupted.
    func test_diskGuard_haltStopsFurtherWrites() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        let csv = recorder.sessionDir.appendingPathComponent("features.csv")
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.queue.sync {}   // drain the async write
        let sizeBeforeHalt = fileSize(csv)

        // Simulate the disk-full halt the write-failure path would trigger.
        recorder.queue.sync { recorder.haltRecording(reason: "test: simulated disk full") }
        XCTAssertTrue(recorder.recordingHalted)

        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.queue.sync {}   // drain
        XCTAssertEqual(fileSize(csv), sizeBeforeHalt,
                       "no rows may be written after the recorder halts (honest stop)")

        // Idempotent — a second halt is a no-op.
        recorder.queue.sync { recorder.haltRecording(reason: "test: again") }
        XCTAssertTrue(recorder.recordingHalted)
    }

    private func fileSize(_ url: URL) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return 0 }
        return size
    }

    // MARK: - FBS Stage 1 (D-153) pulse columns

    func test_recordFrame_writesPulseColumns_beforeStructuralTail() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        var fv = FeatureVector.zero
        fv.pulsePhase01 = 0.625
        fv.pulseAmp01 = 1.0
        fv.pulseBeatIndex = 17
        fv.pulseRegionalBlend01 = 0.75
        recorder.recordFrame(features: fv, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 7]) ?? -1, 0.625, accuracy: 0.0001,
                       "pulse_phase01 round-trip — before the structural trio + TONAL tail")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 6]) ?? -1, 1.0, accuracy: 0.0001,
                       "pulse_amp01 round-trip")
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - 2], "17",
                       "pulse_beat_index round-trip (FBS.S5 tail, now before TONAL)")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 1]) ?? -1, 0.75, accuracy: 0.0001,
                       "pulse_regional_blend01 round-trip (FBS.S5 tail, now before TONAL)")
    }

    func test_recordStructuralPrediction_thenRecordFrame_writesSectionColumns() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.recordStructuralPrediction(StructuralPrediction(
            sectionIndex: 3, sectionStartTime: 42.5, predictedNextBoundary: 60, confidence: 0.73))
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2, "Header + 1 data row")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - 5], "3", "section_index round-trip")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 4]) ?? -1, 42.5, accuracy: 0.001,
                       "section_start_s round-trip")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 3]) ?? -1, 0.73, accuracy: 0.001,
                       "section_confidence round-trip")
    }

    func test_recordFrame_beforeAnyStructuralPrediction_writesZeroSectionColumns() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        // `.none` semantics: section 0, start 0, confidence 0 — "no prediction yet" is a
        // legitimate zero state (unlike the timing columns' empty-cell convention, the
        // structural zero IS the StructuralPrediction.none value the consumers see).
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - 5], "0")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 4]) ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - 3]) ?? -1, 0, accuracy: 0.0001)
    }

    func test_recordFrameTiming_thenRecordFrame_writesTimingValues() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.recordFrameTiming(cpuMs: 4.25, gpuMs: 1.75)
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2, "Header + 1 data row")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 15]) ?? -1, 4.25, accuracy: 0.001,
                       "frame_cpu_ms round-trip")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 14]) ?? -1, 1.75, accuracy: 0.001,
                       "frame_gpu_ms round-trip")
    }

    func test_recordFrame_beforeAnyTiming_writesEmptyTimingCells() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        // Cold-start case: no recordFrameTiming has fired yet (frame N where
        // the GPU completion handler hasn't returned). Both timing columns
        // should be empty cells, not 0 or -1 — empty cell distinguishes
        // "no measurement available" from "measurement was 0".
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - 15], "", "frame_cpu_ms empty before any timing observed")
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - 14], "", "frame_gpu_ms empty before any timing observed")
    }

    func test_recordFrameTiming_gpuNil_writesEmptyGPUCellOnly() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        // GPU timing nil case: cb.gpuEndTime <= cb.gpuStartTime in
        // RenderPipeline → gpuMs is nil → empty gpu cell, cpu cell still written.
        recorder.recordFrameTiming(cpuMs: 3.5, gpuMs: nil)
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 15]) ?? -1, 3.5, accuracy: 0.001,
                       "frame_cpu_ms still written when gpu nil")
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - 14], "",
                       "frame_gpu_ms empty when gpuMs is nil")
    }

    func test_recordFrame_csp3Fields_writtenToCSV() throws {
        // CSP.3 contract: features.csv carries trackElapsedS + cachedBassProportion
        // as trailing columns so the FFO cold-start A/B is verifiable from artifacts.
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        var fv = FeatureVector.zero
        fv.trackElapsedS = 7.234
        var stems = StemFeatures.zero
        stems.cachedBassProportion = 0.31415
        recorder.recordFrame(features: fv, stems: stems)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 13]) ?? -1, 7.234, accuracy: 0.0005,
                       "track_elapsed_s round-trip — column count-13 (post-PERF.2-pass)")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 12]) ?? -1, 0.31415, accuracy: 0.0001,
                       "cached_bass_proportion round-trip — column count-12 (post-PERF.2-pass)")
    }

    // MARK: - PERF.1 per-subsystem timing columns

    func test_recordSubsystemTimings_thenRecordFrame_writesAllFiveColumns() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.recordSubsystemTimings(
            mirPipelineMs: 0.42,
            stemAnalyzerMs: 1.85,
            beatDetectorMs: 0.31,
            pitchTrackerMs: 0.97,
            moodClassifierMs: 0.12
        )
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 11]) ?? -1, 0.42, accuracy: 0.001,
                       "mir_pipeline_ms round-trip — column count-11")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 10]) ?? -1, 1.85, accuracy: 0.001,
                       "stem_analyzer_ms round-trip — column count-10")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 9]) ?? -1, 0.31, accuracy: 0.001,
                       "beat_detector_ms round-trip — column count-9")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 8]) ?? -1, 0.97, accuracy: 0.001,
                       "pitch_tracker_ms round-trip — column count-8")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 7]) ?? -1, 0.12, accuracy: 0.001,
                       "mood_classifier_ms round-trip — column count-7")
    }

    func test_recordFrame_beforeAnySubsystemTimings_writesEmptyCells() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        // Cold-start case: analysis-frame hasn't fired yet (first ~10 ms of
        // session before the analysis queue produces its first row).
        // All five subsystem columns should be empty cells, distinguishing
        // "no measurement available" from "measurement was 0".
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        // PERF.1 columns are at count-7 through count-11 after PERF.2-render +
        // PERF.2-pass appended six columns at the end. All five must be empty pre-firing.
        for offset in 7...11 {
            XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - offset], "",
                           "subsystem timing column count-\(offset) must be empty before first observation")
        }
    }

    // MARK: - PERF.2-render render-loop timing columns

    func test_recordRenderTimings_thenRecordFrame_writesBothColumns() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.recordRenderTimings(encodeCpuMs: 2.34, renderFrameCpuMs: 1.50)
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 6]) ?? -1, 2.34, accuracy: 0.001,
                       "encode_cpu_ms round-trip — column count-6")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 5]) ?? -1, 1.50, accuracy: 0.001,
                       "renderframe_cpu_ms round-trip — column count-5")
    }

    func test_recordFrame_beforeAnyRenderTimings_writesEmptyCells() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        // Cold-start case: render-loop completion hasn't fired yet.
        // Both render-timing columns should be empty cells.
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - 6], "", "encode_cpu_ms empty before first observation")
        XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - 5], "", "renderframe_cpu_ms empty before first observation")
    }

    // MARK: - PERF.2-pass ray-march per-pass timing columns

    func test_recordRayMarchPassTimings_thenRecordFrame_writesAllFourColumns() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        recorder.recordRayMarchPassTimings(
            gbufferMs: 0.61,
            lightingMs: 0.84,
            ssgiMs: 0.0,
            postProcessMs: 0.42
        )
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.count, 2)
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 4]) ?? -1, 0.61, accuracy: 0.001,
                       "gbuffer_pass_ms round-trip — column count-4")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 3]) ?? -1, 0.84, accuracy: 0.001,
                       "lighting_pass_ms round-trip — column count-3")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 2]) ?? -1, 0.0, accuracy: 0.001,
                       "ssgi_pass_ms round-trip — column count-2 (0.0 = SSGI suppressed this frame)")
        XCTAssertEqual(Float(cells[cells.count - qg1Tail - tonalTail - structTail - 1]) ?? -1, 0.42, accuracy: 0.001,
                       "post_process_pass_ms round-trip — column count-1 (last)")
    }

    func test_recordFrame_beforeAnyRayMarchPassTimings_writesEmptyCells() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))
        // Cold-start (or non-ray-march preset): no recordRayMarchPassTimings
        // has fired. All four pass columns must be empty cells.
        recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"),
            encoding: .utf8)
        let rows = csv.split(separator: "\n")
        let cells = rows[1].split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        for offset in 1...4 {
            XCTAssertEqual(cells[cells.count - qg1Tail - tonalTail - structTail - offset], "",
                           "ray-march pass column count-\(offset) must be empty before first observation")
        }
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

    // MARK: - BUG-050 — video gated off by default; CSV always records

    func test_videoDisabled_noCaptureTexture_csvStillRecords() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir, videoEnabled: false))

        // The gate: ensureCaptureTexture returns nil even with a valid device, so
        // the caller skips the blit and recordFrame skips the ~7 ms encode (BUG-050).
        if let device = MTLCreateSystemDefaultDevice() {
            XCTAssertNil(
                recorder.ensureCaptureTexture(device: device, width: 64, height: 64, pixelFormat: .bgra8Unorm),
                "video disabled → no capture texture (blit + encode gated off)")
        }

        // CSV recording is unaffected — that's where the diagnostic value lives.
        recorder.recordFrame(features: FeatureVector(bass: 0.3, mid: 0.4, treble: 0.5, time: 1.0),
                             stems: StemFeatures.zero)
        recorder.finish()

        let csv = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("features.csv"), encoding: .utf8)
        XCTAssertEqual(csv.split(separator: "\n").count, 2,
                       "header + 1 data row — features.csv records with video off")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: recorder.sessionDir.appendingPathComponent("video.mp4").path),
            "no video.mp4 when video is disabled")
    }

    func test_videoEnabled_allocatesCaptureTexture() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir, videoEnabled: true))
        XCTAssertNotNil(
            recorder.ensureCaptureTexture(device: device, width: 64, height: 64, pixelFormat: .bgra8Unorm),
            "video enabled → capture texture allocates")
        recorder.finish()
    }

    // MARK: - Video file is created and readable

    func test_recordFrame_withCaptureTexture_producesReadableVideo() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir, videoEnabled: true))

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

    // MARK: - Relock on drawable size change after bad initial lock
    //
    // Simulates the Tea Lights session (2026-04-16T20-09-44Z) where the
    // drawable reported Retina-native 1802×1202 for the first ~30 frames
    // then stabilised at logical-point 901×601. Before the fix, the writer
    // locked to the transient Retina size and skipped all 1861 subsequent
    // frames. The fix: if a different size arrives consistently for
    // ≥ writerRelockThreshold (90) frames after initial lock, relock to it.

    func test_recordFrame_relocksWhenDrawableStabilisesAtDifferentSize() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir, videoEnabled: true))

        // Phase 1: 35 frames at the "transient" Retina-native size.
        // Passes the 30-frame stability threshold → writer locks here.
        let badW = 256
        let badH = 144
        let badTex = try XCTUnwrap(recorder.ensureCaptureTexture(
            device: device, width: badW, height: badH,
            pixelFormat: .bgra8Unorm_srgb))
        var badPixels = [UInt8](repeating: 0, count: badW * badH * 4)
        for i in 0..<(badW * badH) {
            badPixels[i * 4 + 2] = 255; badPixels[i * 4 + 3] = 255   // red
        }
        badTex.replace(region: MTLRegionMake2D(0, 0, badW, badH),
                       mipmapLevel: 0, withBytes: &badPixels,
                       bytesPerRow: badW * 4)
        for _ in 0..<35 {
            recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
            Thread.sleep(forTimeInterval: 0.04)
        }

        // Phase 2: 120 frames at the logical-point "good" size (clears the
        // 90-frame relock threshold). The recorder should throw away the
        // bad lock, recreate the writer at goodW×goodH, and start writing.
        let goodW = 128
        let goodH = 72
        let goodTex = try XCTUnwrap(recorder.ensureCaptureTexture(
            device: device, width: goodW, height: goodH,
            pixelFormat: .bgra8Unorm_srgb))
        var goodPixels = [UInt8](repeating: 0, count: goodW * goodH * 4)
        for i in 0..<(goodW * goodH) {
            goodPixels[i * 4 + 0] = 255; goodPixels[i * 4 + 3] = 255  // blue
        }
        goodTex.replace(region: MTLRegionMake2D(0, 0, goodW, goodH),
                        mipmapLevel: 0, withBytes: &goodPixels,
                        bytesPerRow: goodW * 4)
        for _ in 0..<120 {
            recorder.recordFrame(features: FeatureVector.zero, stems: StemFeatures.zero)
            Thread.sleep(forTimeInterval: 0.04)
        }
        recorder.finish()

        // Log must document the relock.
        let log = try String(
            contentsOf: recorder.sessionDir.appendingPathComponent("session.log"),
            encoding: .utf8)
        XCTAssertTrue(log.contains("video writer relocking"),
                      "log must record the relock event, got:\n\(log)")
        XCTAssertTrue(log.contains("video writer relocked to \(goodW)x\(goodH)"),
                      "log must record the new locked size")

        // Video must exist and match the POST-relock size, not the bad size.
        let videoURL = recorder.sessionDir.appendingPathComponent("video.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: videoURL.path),
                      "video.mp4 must be written after relock")
        let asset = AVURLAsset(url: videoURL)
        let tracks = asset.tracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "video.mp4 must contain a video track after relock")
        if let track = tracks.first {
            let naturalSize = track.naturalSize
            XCTAssertEqual(Int(naturalSize.width), goodW,
                           "video width must match the relocked (good) size")
            XCTAssertEqual(Int(naturalSize.height), goodH,
                           "video height must match the relocked (good) size")
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

    // MARK: - Raw tap WAV persists after duration cap (regression: session 20-57-06Z)

    /// After `recordRawTapSamples` accumulates more than the duration cap, the
    /// file must remain on disk with the captured audio intact.  Earlier bug:
    /// completing the cap set `rawTapHandle = nil` without a "done" flag, so
    /// the next sample callback treated the nil handle as a fresh session and
    /// `FileManager.createFile(atPath:contents:nil)` truncated the file to a
    /// 44-byte header-only stub — wiping all the captured audio.
    func test_rawTapCapture_persistsAfterDurationCap_evenWithContinuingCallbacks() throws {
        let recorder = try XCTUnwrap(SessionRecorder(baseDir: tempDir))

        // Feed 35 seconds of audio at 48 kHz stereo (30s cap + 5s of "kept
        // arriving after done").  Use a chunked submission so we actually
        // cross the cap mid-stream and then continue submitting.
        let sampleRate: Float = 48_000
        let channels: UInt32 = 2
        let chunkFrames = 1024
        let totalSeconds: Float = 35
        let totalChunks = Int((totalSeconds * sampleRate) / Float(chunkFrames))

        // Fill chunk buffer with a distinguishable ramp so bytes aren't all zeros.
        var chunk = [Float](repeating: 0, count: chunkFrames * Int(channels))
        for i in 0..<chunk.count {
            chunk[i] = Float(i % 97) / 97.0 * 0.5
        }

        for _ in 0..<totalChunks {
            chunk.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                recorder.recordRawTapSamples(
                    pointer: base, count: chunk.count,
                    sampleRate: sampleRate, channelCount: channels)
            }
        }
        recorder.finish()

        let url = recorder.sessionDir.appendingPathComponent("raw_tap.wav")
        let data = try Data(contentsOf: url)

        // A 30s capture at 48 kHz stereo Float32 = 11 520 044 bytes (44 header
        // + 11 520 000 PCM).  The header-only bug produced exactly 44 bytes.
        // Expect at least 10 MB so the test is unambiguous.
        XCTAssertGreaterThan(data.count, 10_000_000,
            "raw_tap.wav must contain the captured audio; got only \(data.count) bytes "
            + "(header-only bug would produce exactly 44)")

        // Validate IEEE 754 Float WAV format markers (our stub writes fmt=3, bits=32).
        let riff = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")
        let fmtCode = data.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt16.self) }
        XCTAssertEqual(fmtCode, 3, "WAVE_FORMAT_IEEE_FLOAT expected")
        let bits = data.withUnsafeBytes { $0.load(fromByteOffset: 34, as: UInt16.self) }
        XCTAssertEqual(bits, 32, "32-bit float samples expected")

        // Confirm a non-zero sample actually landed in the PCM region.
        let anyNonZero = data.suffix(from: 44).contains { $0 != 0 }
        XCTAssertTrue(anyNonZero, "PCM region must contain captured audio, not zeros")
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
