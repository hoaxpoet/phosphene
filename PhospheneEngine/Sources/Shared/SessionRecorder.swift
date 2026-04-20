// SessionRecorder — Continuous diagnostic capture during real playback.
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

    // MARK: Raw-tap streaming WAV state (diagnostic — first 30s).
    var rawTapHandle: FileHandle?
    var rawTapSampleRate: UInt32 = 0
    var rawTapChannels: UInt16 = 0
    var rawTapSamplesWritten: Int = 0
    var rawTapMaxSamples: Int = 0
    var rawTapHeaderWritten: Bool = false
    /// Set once the 30s cap is reached or `finish()` closes the file.
    var rawTapDone: Bool = false
    let rawTapDurationSeconds: Double = 30.0

    /// True once `finish()` has closed all handles.
    var didFinish: Bool = false

    // MARK: Init

    /// Create a new session directory under ~/Documents/phosphene_sessions/.
    /// Returns `nil` if the directory could not be created.
    public init?(baseDir: URL? = nil) {
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

        logger.info("SessionRecorder started: \(dir.path, privacy: .public)")
        writeStartupBanner(dir: dir)
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
        let now = CFAbsoluteTimeGetCurrent()
        let throttled = (now - lastVideoFrameTime) < minVideoInterval
        queue.async { [weak self] in
            guard let self = self else { return }
            let idx = self.frameIndex
            self.frameIndex += 1
            let fRow = SessionRecorder.csvRow(features: features, frame: idx, wallclock: now)
            self.featuresHandle.write(fRow.data(using: .utf8) ?? Data())
            let sRow = SessionRecorder.csvRow(stems: stems, frame: idx, wallclock: now)
            self.stemsHandle.write(sRow.data(using: .utf8) ?? Data())
            guard !throttled, let tex = self.captureTexture else { return }
            self.lastVideoFrameTime = now
            self.appendVideoFrame(from: tex, wallclock: now)
        }
    }

    // MARK: - Public API: Stem Separation

    /// Dump the four separated stem waveforms as 16-bit PCM WAV files.
    public func recordStemSeparation(
        stemWaveforms: [[Float]],
        sampleRate: Int,
        trackTitle: String?
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard stemWaveforms.count >= 4 else { return }
            let names = ["drums", "bass", "vocals", "other"]
            let idx = self.stemDumpIndex
            self.stemDumpIndex += 1
            let safeTitle = (trackTitle ?? "unknown")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .prefix(60)
            let dumpDir = self.sessionDir
                .appendingPathComponent("stems", isDirectory: true)
                .appendingPathComponent(String(format: "%04d_%@", idx, String(safeTitle)),
                                        isDirectory: true)
            try? FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
            for (i, waveform) in stemWaveforms.prefix(4).enumerated() {
                let url = dumpDir.appendingPathComponent("\(names[i]).wav")
                SessionRecorder.writeWav(samples: waveform, sampleRate: sampleRate, to: url)
            }
            self.writeLogLine("stem separation \(idx) "
                              + "(\(stemWaveforms[0].count) samples) "
                              + "track=\(safeTitle) → \(dumpDir.lastPathComponent)")
        }
    }

    /// Synchronous log write — for use from inside the recorder's own queue.
    func writeLogLine(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        self.logHandle.write(line.data(using: .utf8) ?? Data())
    }

    // MARK: - Public API: Logging

    /// Append a timestamped line to session.log.
    public func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        queue.async { [weak self] in
            guard let self = self, !self.didFinish else { return }
            self.logHandle.write(line.data(using: .utf8) ?? Data())
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
            let msg = "SessionRecorder finished (\(self.frameIndex) frames, "
                    + "\(self.stemDumpIndex) stem dumps)\n"
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
        let featuresHeader = """
            frame,wallclock_s,time,deltaTime,bass,mid,treble,\
            subBass,lowBass,lowMid,midHigh,highMid,high,\
            beatBass,beatMid,beatTreble,beatComposite,\
            spectralCentroid,spectralFlux,valence,arousal,accumulatedAudioTime

            """
        let stemsHeader = """
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
        FileManager.default.createFile(atPath: featuresCSVURL.path,
                                       contents: featuresHeader.data(using: .utf8))
        FileManager.default.createFile(atPath: stemsCSVURL.path,
                                       contents: stemsHeader.data(using: .utf8))
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
    }
}
