// SessionRecorder — Continuous diagnostic capture during real playback.
// swiftlint:disable file_length
//
// File grew past the 400-line warning when PERF.1 + PERF.2-render +
// PERF.2-pass added per-subsystem and per-pass timing storage. The CSV
// header + setter methods are split into +CSV / +Timing extensions where
// possible; what remains is the class core (init, recordFrame, raw-tap
// streaming, video writer) — splitting further would obscure the
// recorder's threading model.
//
// Writes to ~/Documents/phosphene_sessions/<ISO-timestamp>/ while the app is
// running, producing:
//
//   video.mp4             H.264 video of the rendered output (30 fps cap).
//   features.csv          Per-frame FeatureVector (bass/mid/treble/bands/beats/accum).
//   stems.csv             Per-frame StemFeatures: base energy/beat/band + MV-1 rel/dev
//                         + MV-3a rich metadata (onsetRate/centroid/attackRatio/energySlope)
//                         + MV-3c vocals pitch.
//   session.log           Plain-text log of events (track/preset/state changes, errors).
//   stems/<N>_<title>/    One directory per stem-separation invocation:
//       drums.wav bass.wav vocals.wav other.wav
//   raw_tap.wav           First 30s of interleaved Float32 PCM straight from
//                         the Core Audio tap callback — before any Phosphene
//                         DSP (FFT, AGC, stem separation).  Stage 4 ground
//                         truth for diagnosing signal-chain degradation.
//                         Compare its spectrum against stems/*/*.wav to
//                         localise where band-limiting or attenuation enters.
//
// The recorder is created once at VisualizerEngine init and runs continuously
// — there is no "start" button. Every rendered frame from the real app, driven
// by real audio from the Core Audio tap (Apple Music / Spotify / any source
// feeding the system tap), lands in the capture directory.
//
// Video capture works by blitting the drawable texture to a shared-storage
// capture texture *inside* the render command buffer, then reading that
// texture's bytes in the buffer's completion handler and feeding them to the
// AVAssetWriter on a dedicated serial queue.

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene", category: "SessionRecorder")

// MARK: - SessionRecorder

/// Continuously records diagnostic data from a running Phosphene session.
///
/// Thread-safe: hot path methods (`recordFrame`, `recordStemSeparation`, `log`)
/// dispatch onto an internal serial queue; callers do not need to synchronize.
public final class SessionRecorder: @unchecked Sendable {

    // MARK: Paths

    public let sessionDir: URL
    let videoURL: URL
    private let featuresCSVURL: URL
    private let stemsCSVURL: URL
    private let logURL: URL
    /// First 30 seconds of interleaved Float32 samples straight from the
    /// Core Audio tap callback, before Phosphene's FFT / AGC / stem separation
    /// touch them.  This is Stage 4 ground truth for diagnosing where in the
    /// chain signal degradation (low-level peaks, high-frequency roll-off)
    /// is introduced.  Compare its spectrum against the per-stem WAVs to
    /// localise the culprit.
    let rawTapURL: URL

    // MARK: IO

    let queue = DispatchQueue(label: "com.phosphene.recorder", qos: .utility)

    private let featuresHandle: FileHandle
    private let stemsHandle: FileHandle
    private let logHandle: FileHandle

    private struct CSVHandles {
        var features: FileHandle
        var stems: FileHandle
        var log: FileHandle
    }

    // Video writer (lazy — initialized on first frame so we know the resolution).
    var videoWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var videoStartTime: CMTime?
    var lastVideoFrameTime: CFAbsoluteTime = 0
    /// Cap video to ~30 fps regardless of the render loop rate (reduces file size;
    /// diagnostic motion is readable at 30 fps).
    private let minVideoInterval: CFAbsoluteTime = 1.0 / 30.0

    /// BUG-050: gate for the per-frame video capture. The drawable blit →
    /// `tex.getBytes` → AVAssetWriter append costs ~7 ms/frame, additive to
    /// render, ≈ doubling the app's CPU for the entire session (sustained
    /// power/heat — no fps cost). It is **OFF by default**; the CSV / log /
    /// raw-tap / stem artifacts (nearly free, and where ~all the diagnostic
    /// value lives) always record. Enable per session with
    /// `PHOSPHENE_RECORD_VIDEO=1` (e.g. to capture a quality reel). When off,
    /// `ensureCaptureTexture` returns nil → the blit, the byte read, and the
    /// encoder are all skipped.
    let videoEnabled: Bool

    // Capture texture (reused across frames; resized on view-size change).
    var captureTexture: MTLTexture?

    // Drawable-size stability tracking.
    var lastObservedDims: (width: Int, height: Int)?
    var sameDimsStreak: Int = 0
    let videoSizeStableThreshold: Int = 30  // ~1s at 30fps capture

    /// Dimensions the AVAssetWriter is locked to (set in `setupVideoWriter`).
    var writerLockedDims: (width: Int, height: Int)?
    var skippedFrameCount: Int = 0

    // Writer-relock after bad initial lock.
    var mismatchedDims: (width: Int, height: Int)?
    var mismatchedDimsStreak: Int = 0
    let writerRelockThreshold: Int = 90  // ~3s at 30fps capture

    var frameIndex: Int = 0
    var stemDumpIndex: Int = 0

    // MARK: Frame timing (DM.3a — full-pipeline perf capture).
    //
    // Updated by `recordFrameTiming(cpuMs:gpuMs:)` from RenderPipeline's
    // command-buffer completion handler (`onFrameTimingObserved`). Consumed by
    // the next `recordFrame` row write. Both unset → empty cells in
    // features.csv (cold-start frames before the first GPU completion).
    //
    // Lag: 1–3 frames behind the features the row carries. RenderPipeline
    // triple-buffers, so when frame N's `onFrameRendered` fires (synchronous
    // in `draw(in:)`), the most-recent completion handler we've executed is
    // for some earlier frame in [N-3, N-1]. Adequate for percentile capture
    // over a 60 s window; slight misalignment for single-frame correlation.
    // Both fields accessed only from the serial `queue` — no separate lock.
    var latestFrameCPUms: Float?
    var latestFrameGPUms: Float?

    // MARK: Per-subsystem analysis timing (PERF.1 — BUG-019 instrumentation).
    // Setter + threading contract in `SessionRecorder+Timing.swift`.
    var latestMIRPipelineMs: Float?
    var latestStemAnalyzerMs: Float?
    var latestBeatDetectorMs: Float?
    var latestPitchTrackerMs: Float?
    var latestMoodClassifierMs: Float?

    // MARK: Render-loop CPU breakdown (PERF.2-render + PERF.2-pass — BUG-019).
    // Setters in `SessionRecorder+Timing.swift`. Ray-march-pass fields stay
    // nil on frames where the active preset doesn't take the ray-march path.
    var latestEncodeCPUms: Float?
    var latestRenderFrameCPUms: Float?
    var latestGBufferPassMs: Float?
    var latestLightingPassMs: Float?
    var latestSSGIPassMs: Float?
    var latestPostProcessPassMs: Float?

    // MARK: Video-stall instrumentation (BUG-039). All accessed only from the
    // serial `queue`. The append/not-ready/pool counters throttle their log
    // lines; `videoFailureLogged` makes the one-shot writer-failed line fire once.
    var videoFailureLogged = false

    /// BUG-039 recovery — 1-based index of the video segment currently being
    /// written. Segment 1 = `video.mp4` (unchanged layout); each writer death
    /// rolls to `video_<n>.mp4` so the dead partial (playable to its last
    /// fragment) is retained and recording RESUMES instead of dying for the
    /// rest of the session. The writer's death certificate from session
    /// 2026-06-10T17-50-56Z (AVFoundation -11800 / undocumented OSStatus
    /// -16341, 10 s after lock) is an intermittent encoder-session failure —
    /// unrecoverable in place, so the recorder restarts around it.
    var videoSegmentIndex = 1
    /// Restarts performed this session; capped so a pathological failure loop
    /// can't churn files forever.
    var videoWriterRestartCount = 0
    static let maxVideoWriterRestarts = 8

    /// URL for the CURRENT video segment.
    var currentVideoURL: URL {
        videoSegmentIndex <= 1
            ? videoURL
            : videoURL.deletingLastPathComponent()
                .appendingPathComponent("video_\(videoSegmentIndex).mp4")
    }
    var videoNotReadyCount = 0
    var videoPoolFailCount = 0
    var videoAppendFailCount = 0

    /// BUG-039 invariant (CLEAN.3.6): successful video appends this session and the
    /// `frameIndex` at the most recent one. `finish()` asserts the running-vs-actually-
    /// writing invariant from these — the recorder keeps "running" (CSV/log advance) even
    /// when the video writer silently stops, so a writer that locked then stopped appending
    /// well before session end, with no death/restart and not disabled, is the silent-stop
    /// signature and is logged loudly. Accessed only from the serial `queue`.
    var videoFramesAppended = 0
    var lastVideoAppendFrameIndex = 0
    /// Frames the recorder may run past the last successful append before `finish()` calls
    /// it a silent stop (≈5 s at 60 fps; the field signature was tens of thousands).
    static let videoSilentStopFrameThreshold = 300

    // MARK: Structural prediction (Skein.5.2 — section evidence in artifacts).
    // Updated by `recordStructuralPrediction(_:)` from the per-frame MIR publish
    // (the same site that calls `RenderPipeline.setStructuralPrediction`).
    // Emitted as the `section_index` / `section_start_s` / `section_confidence`
    // tail columns of features.csv, so section firing — and BUG-035-class
    // corruption (sub-second "sections") — is verifiable from session artifacts.
    // Accessed only from the serial `queue`.
    var latestStructuralPrediction = StructuralPrediction.none

    // MARK: Raw-tap streaming WAV state (diagnostic — first 30s).
    var rawTapHandle: FileHandle?
    var rawTapSampleRate: UInt32 = 0
    var rawTapChannels: UInt16 = 0
    var rawTapSamplesWritten: Int = 0
    var rawTapMaxSamples: Int = 0
    var rawTapHeaderWritten: Bool = false
    /// Set once the duration cap is reached or `finish()` closes the file.
    var rawTapDone: Bool = false
    /// Default 30 s diagnostic cap. Set `PHOSPHENE_FULL_RAW_TAP=1` to capture
    /// the entire session — required by `QualityReelAnalyzer`, which needs
    /// audio coverage matching the visual reel for beat alignment.
    let rawTapDurationSeconds: Double = ProcessInfo.processInfo
        .environment["PHOSPHENE_FULL_RAW_TAP"] == "1" ? 86_400.0 : 30.0

    /// True once `finish()` has closed all handles.
    var didFinish: Bool = false

    /// Set when a session-file write fails (disk full / ENOSPC). Once halted, all writes
    /// early-out — the recorder stops honestly instead of crashing on the non-throwing
    /// `FileHandle.write` exception or writing partial/corrupt rows. Only ever set by
    /// `haltRecording` (SessionRecorder+DiskGuard); accessed on the serial `queue`.
    /// CLEAN.3.8 / GAP-6.
    var recordingHalted = false

    // MARK: Init

    /// Create a new session directory under ~/Documents/phosphene_sessions/.
    /// Returns `nil` if disabled or if the directory could not be created.
    ///
    /// - Parameter videoEnabled: gate the per-frame video capture (BUG-050).
    ///   `nil` (the production default) reads `PHOSPHENE_RECORD_VIDEO` from the
    ///   environment → off unless set to `1`. Tests pass an explicit value.
    public init?(baseDir: URL? = nil, enabled: Bool = true, videoEnabled: Bool? = nil) {
        guard enabled else {
            logger.info("SessionRecorder: disabled by settings — no session directory created")
            return nil
        }
        let root: URL
        if let baseDir = baseDir {
            root = baseDir
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            guard let documents = documents else { return nil }
            root = documents.appendingPathComponent("phosphene_sessions", isDirectory: true)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = root.appendingPathComponent(stamp, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("SessionRecorder could not create \(dir.path): \(error.localizedDescription)")
            return nil
        }

        self.sessionDir     = dir
        self.videoURL       = dir.appendingPathComponent("video.mp4")
        self.featuresCSVURL = dir.appendingPathComponent("features.csv")
        self.stemsCSVURL    = dir.appendingPathComponent("stems.csv")
        self.logURL         = dir.appendingPathComponent("session.log")
        self.rawTapURL      = dir.appendingPathComponent("raw_tap.wav")

        guard let handles = Self.makeFileHandles(
            featuresCSVURL: dir.appendingPathComponent("features.csv"),
            stemsCSVURL: dir.appendingPathComponent("stems.csv"),
            logURL: dir.appendingPathComponent("session.log")
        ) else { return nil }
        self.featuresHandle = handles.features
        self.stemsHandle    = handles.stems
        self.logHandle      = handles.log
        self.videoEnabled   = videoEnabled
            ?? (ProcessInfo.processInfo.environment["PHOSPHENE_RECORD_VIDEO"] == "1")

        logger.info("SessionRecorder started: \(dir.path, privacy: .public)")
        writeStartupBanner(dir: dir)
        Self.warnIfLowDiskSpace(at: dir)   // CLEAN.3.8: pre-flight capacity check
    }

    deinit {
        finish()
    }

    // MARK: - Public API: Frame Capture

    /// Ensure a shared-storage capture texture matching the drawable size.
    public func ensureCaptureTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat
    ) -> MTLTexture? {
        // BUG-050: video off → no capture texture, so the caller skips the blit
        // and `recordFrame`'s `captureTexture` guard skips the encode entirely.
        guard videoEnabled else { return nil }
        if let existing = captureTexture,
           existing.width == width,
           existing.height == height,
           existing.pixelFormat == pixelFormat {
            return existing
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)
        captureTexture = tex
        return tex
    }

    /// Record one rendered frame. Safe to call from the command buffer completion handler.
    public func recordFrame(features: FeatureVector, stems: StemFeatures) {
        recordFrame(features: features, stems: stems, beatSync: .zero)
    }

    /// Record one rendered frame with beat-sync diagnostic columns.
    /// Safe to call from the command buffer completion handler.
    public func recordFrame(features: FeatureVector, stems: StemFeatures, beatSync: BeatSyncSnapshot) {
        let now = CFAbsoluteTimeGetCurrent()
        let throttled = (now - lastVideoFrameTime) < minVideoInterval
        queue.async { [weak self] in
            guard let self = self, !self.recordingHalted else { return }
            let idx = self.frameIndex
            self.frameIndex += 1
            let cpuMs = self.latestFrameCPUms
            let gpuMs = self.latestFrameGPUms
            let subsystem = SubsystemTimingSnapshot(
                mirPipelineMs: self.latestMIRPipelineMs,
                stemAnalyzerMs: self.latestStemAnalyzerMs,
                beatDetectorMs: self.latestBeatDetectorMs,
                pitchTrackerMs: self.latestPitchTrackerMs,
                moodClassifierMs: self.latestMoodClassifierMs
            )
            let renderTiming = RenderTimingSnapshot(
                encodeCpuMs: self.latestEncodeCPUms,
                renderFrameCpuMs: self.latestRenderFrameCPUms
            )
            let passTiming = RayMarchPassTimingSnapshot(
                gbufferPassMs: self.latestGBufferPassMs,
                lightingPassMs: self.latestLightingPassMs,
                ssgiPassMs: self.latestSSGIPassMs,
                postProcessPassMs: self.latestPostProcessPassMs
            )
            // swiftlint:disable multiline_arguments
            let fRow = SessionRecorder.csvRow(features: features, stems: stems, beatSync: beatSync,
                                              frame: idx, wallclock: now,
                                              frameCPUms: cpuMs, frameGPUms: gpuMs,
                                              subsystem: subsystem, renderTiming: renderTiming,
                                              rayMarchPass: passTiming,
                                              structure: self.latestStructuralPrediction)
            // swiftlint:enable multiline_arguments
            self.safeWrite(fRow.data(using: .utf8) ?? Data(), to: self.featuresHandle)
            let sRow = SessionRecorder.csvRow(stems: stems, frame: idx, wallclock: now)
            self.safeWrite(sRow.data(using: .utf8) ?? Data(), to: self.stemsHandle)
            guard !throttled, let tex = self.captureTexture else { return }
            self.lastVideoFrameTime = now
            self.appendVideoFrame(from: tex, wallclock: now)
        }
    }

    /// Synchronous log write — for use from inside the recorder's own queue.
    func writeLogLine(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        self.safeWrite(line.data(using: .utf8) ?? Data(), to: self.logHandle)
    }

    // MARK: - Public API: Logging

    /// Append a timestamped line to session.log.
    public func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        queue.async { [weak self] in
            guard let self = self, !self.didFinish else { return }
            self.safeWrite(line.data(using: .utf8) ?? Data(), to: self.logHandle)
        }
    }

    // MARK: - Public API: Finish

    /// Flush all writers. Safe to call multiple times; idempotent after first call.
    public func finish() {
        queue.sync {
            guard !self.didFinish else { return }
            self.didFinish = true
            if let writer = self.videoWriter, writer.status == .writing {
                self.videoInput?.markAsFinished()
                let sema = DispatchSemaphore(value: 0)
                writer.finishWriting { sema.signal() }
                _ = sema.wait(timeout: .now() + 5)
            }
            try? self.featuresHandle.close()
            try? self.stemsHandle.close()
            self.rawTapDone = true
            if self.rawTapHeaderWritten {
                self.finalizeRawTapHeader()
                if let fh = self.rawTapHandle {
                    try? fh.close()
                    self.rawTapHandle = nil
                }
            }
            // BUG-039 invariant (CLEAN.3.6): flag a silent video stop + summarise the real
            // video-writing outcome, so a recorder that kept "running" while the writer
            // stopped can never look healthy from the artifacts. (Logic lives in the
            // SessionRecorder+Video extension to keep this type under `type_body_length`.)
            let videoSummary = self.finalizeVideoInvariant()
            let msg = "SessionRecorder finished (\(self.frameIndex) frames, "
                    + "\(self.stemDumpIndex) stem dumps; \(videoSummary))\n"
            try? self.logHandle.write(contentsOf: Data(msg.utf8))
            try? self.logHandle.close()
        }
    }

    // MARK: - Init Helpers

    private static func makeFileHandles(
        featuresCSVURL: URL,
        stemsCSVURL: URL,
        logURL: URL
    ) -> CSVHandles? {
        // CSV headers live in SessionRecorder+CSV.swift next to the row
        // writers (QG.1 — single source; FixtureSessionCaptureGenerator had a
        // stale private copy that drifted when IFC.4 appended columns).
        FileManager.default.createFile(atPath: featuresCSVURL.path,
                                       contents: Self.featuresCSVHeader.data(using: .utf8))
        FileManager.default.createFile(atPath: stemsCSVURL.path,
                                       contents: Self.stemsCSVHeader.data(using: .utf8))
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: featuresCSVURL),
              let sh = try? FileHandle(forWritingTo: stemsCSVURL),
              let lh = try? FileHandle(forWritingTo: logURL) else {
            logger.error("SessionRecorder failed to open CSV/log handles")
            return nil
        }
        fh.seekToEndOfFile(); sh.seekToEndOfFile(); lh.seekToEndOfFile()
        return CSVHandles(features: fh, stems: sh, log: lh)
    }

    private func writeStartupBanner(dir: URL) {
        let proc = ProcessInfo.processInfo
        let osVersion = proc.operatingSystemVersionString
        let device = MTLCreateSystemDefaultDevice()?.name ?? "unknown"
        log("SessionRecorder started schema=1 dir=\(dir.path)")
        log("host macOS=\(osVersion) gpu=\(device) hostname=\(proc.hostName)")
        let videoState = videoEnabled
            ? "ENABLED"
            : "OFF — CSV/log/stems only (BUG-050; set PHOSPHENE_RECORD_VIDEO=1 to capture video.mp4)"
        log("video recording: \(videoState)")
    }
}
