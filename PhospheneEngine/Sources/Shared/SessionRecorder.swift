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
    private let videoURL: URL
    private let featuresCSVURL: URL
    private let stemsCSVURL: URL
    private let logURL: URL
    /// First 30 seconds of interleaved Float32 samples straight from the
    /// Core Audio tap callback, before Phosphene's FFT / AGC / stem separation
    /// touch them.  This is Stage 4 ground truth for diagnosing where in the
    /// chain signal degradation (low-level peaks, high-frequency roll-off)
    /// is introduced.  Compare its spectrum against the per-stem WAVs to
    /// localise the culprit.
    private let rawTapURL: URL

    // MARK: IO

    private let queue = DispatchQueue(label: "com.phosphene.recorder", qos: .utility)

    private let featuresHandle: FileHandle
    private let stemsHandle: FileHandle
    private let logHandle: FileHandle

    // Video writer (lazy — initialized on first frame so we know the resolution).
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var videoStartTime: CMTime?
    private var lastVideoFrameTime: CFAbsoluteTime = 0
    /// Cap video to ~30 fps regardless of the render loop rate (reduces file size;
    /// diagnostic motion is readable at 30 fps).
    private let minVideoInterval: CFAbsoluteTime = 1.0 / 30.0

    // Capture texture (reused across frames; resized on view-size change).
    private var captureTexture: MTLTexture?

    // Drawable-size stability tracking. The first few frames after launch
    // sometimes report a transient drawable size (e.g. native-pixel size
    // before SwiftUI/MTKView layout finalizes the logical-point area).
    // Locking the AVAssetWriter to that early size produces a video where
    // later frames are blitted into a corner of the original buffer.
    // We defer writer initialization until we've observed the same drawable
    // size for `videoSizeStableThreshold` consecutive frames.
    private var lastObservedDims: (width: Int, height: Int)?
    private var sameDimsStreak: Int = 0
    private let videoSizeStableThreshold: Int = 30  // ~1s at 30fps capture

    /// Dimensions the AVAssetWriter is locked to (set in `setupVideoWriter`).
    /// Frames whose drawable size doesn't match are skipped from video,
    /// preventing geometry-mismatched blits that produce a corner-rendered
    /// video file. CSV/log writes are unaffected.
    private var writerLockedDims: (width: Int, height: Int)?
    private var skippedFrameCount: Int = 0

    // Writer-relock after bad initial lock. If the drawable settles at a
    // different steady-state size than the one we initially locked to
    // (e.g. launch observed Retina native 1802×1202 then the view stabilises
    // at logical 901×601), the locked writer would drop every subsequent
    // frame. We track how many consecutive frames arrive at a *different*
    // size and, once the streak exceeds `writerRelockThreshold`, throw
    // away the current writer and relock at the new size. This recovers
    // the video output without losing significant footage — the original
    // lock already had only `videoSizeStableThreshold` (30) transient
    // frames in it.
    private var mismatchedDims: (width: Int, height: Int)?
    private var mismatchedDimsStreak: Int = 0
    private let writerRelockThreshold: Int = 90  // ~3s at 30fps capture

    private var frameIndex: Int = 0
    private var stemDumpIndex: Int = 0

    // MARK: Raw-tap streaming WAV state (diagnostic — first 30s).
    //
    // Open on first sample submission; set the WAV format once we know the
    // tap's sample rate and channel count.  Stream interleaved Float32
    // samples appended as little-endian IEEE 754 PCM bytes.  Stop after
    // `rawTapMaxSamples` total samples have been written (30s × sampleRate
    // × channels).  Header chunk-sizes are patched in `finish()`.
    private var rawTapHandle: FileHandle?
    private var rawTapSampleRate: UInt32 = 0
    private var rawTapChannels: UInt16 = 0
    private var rawTapSamplesWritten: Int = 0
    private var rawTapMaxSamples: Int = 0        // set when format is known
    private var rawTapHeaderWritten: Bool = false
    /// Set once the 30s cap is reached or `finish()` closes the file.  Any
    /// subsequent `recordRawTapSamples` calls short-circuit.  Without this
    /// guard, a completed capture + continuing tap callbacks re-entered
    /// `appendRawTapBytes`, saw `rawTapHandle == nil`, and re-created the
    /// file via `FileManager.createFile(contents: nil)` — truncating the
    /// freshly-captured 30s to zero bytes (seen in session 20-57-06Z,
    /// where raw_tap.wav ended up at 44 bytes = header-only).
    private var rawTapDone: Bool = false
    private let rawTapDurationSeconds: Double = 30.0

    /// True once `finish()` has closed all handles. Guards against double-close
    /// when `deinit` runs after explicit `finish()` (common in tests).
    private var didFinish: Bool = false

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
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")  // colons are sketchy in paths
        let dir = root.appendingPathComponent(stamp, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("SessionRecorder could not create \(dir.path): \(error.localizedDescription)")
            return nil
        }

        self.sessionDir = dir
        self.videoURL = dir.appendingPathComponent("video.mp4")
        self.featuresCSVURL = dir.appendingPathComponent("features.csv")
        self.stemsCSVURL = dir.appendingPathComponent("stems.csv")
        self.logURL = dir.appendingPathComponent("session.log")
        self.rawTapURL = dir.appendingPathComponent("raw_tap.wav")

        // Create CSV files with headers and the log file.
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
        fh.seekToEndOfFile()
        sh.seekToEndOfFile()
        lh.seekToEndOfFile()
        self.featuresHandle = fh
        self.stemsHandle = sh
        self.logHandle = lh

        logger.info("SessionRecorder started: \(dir.path, privacy: .public)")

        // Startup banner — lets anyone inspecting session.log verify which
        // recorder version ran, where artifacts live, and what device recorded.
        // Also makes it immediately obvious if the log is missing when it
        // shouldn't be (e.g. recorder init failed silently).
        let proc = ProcessInfo.processInfo
        let osVersion = proc.operatingSystemVersionString
        let device = MTLCreateSystemDefaultDevice()?.name ?? "unknown"
        log("SessionRecorder started schema=1 dir=\(dir.path)")
        log("host macOS=\(osVersion) gpu=\(device) hostname=\(proc.hostName)")
    }

    deinit {
        finish()
    }

    // MARK: - Public API: Frame Capture

    /// Ensure a shared-storage capture texture matching the drawable size.
    /// The render pipeline blits the drawable into this texture inside the
    /// command buffer before commit; `recordFrame` reads it in the completion
    /// handler and feeds it to the AVAssetWriter.
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

    /// Record one rendered frame. Safe to call from the command buffer
    /// completion handler — heavy work is dispatched onto the recorder's queue.
    ///
    /// Reads the internal capture texture (populated by the RenderPipeline's
    /// per-frame blit) inside the recorder's queue. The caller does not pass
    /// the texture through the @Sendable completion handler — MTLTexture is
    /// not Sendable.
    public func recordFrame(features: FeatureVector, stems: StemFeatures) {
        let now = CFAbsoluteTimeGetCurrent()
        let throttled = (now - lastVideoFrameTime) < minVideoInterval
        queue.async { [weak self] in
            guard let self = self else { return }
            let idx = self.frameIndex
            self.frameIndex += 1

            // Features CSV row (every render frame — 60 fps, still cheap).
            let fRow = SessionRecorder.csvRow(features: features, frame: idx, wallclock: now)
            self.featuresHandle.write(fRow.data(using: .utf8) ?? Data())

            // Stems CSV row.
            let sRow = SessionRecorder.csvRow(stems: stems, frame: idx, wallclock: now)
            self.stemsHandle.write(sRow.data(using: .utf8) ?? Data())

            // Video frame — throttled to ~30 fps.
            guard !throttled, let tex = self.captureTexture else { return }
            self.lastVideoFrameTime = now
            self.appendVideoFrame(from: tex, wallclock: now)
        }
    }

    // MARK: - Public API: Stem Separation

    /// Dump the four separated stem waveforms as 16-bit PCM WAV files.
    /// Called once per stem-separation cycle (~5s).
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
            try? FileManager.default.createDirectory(at: dumpDir,
                                                     withIntermediateDirectories: true)
            for (i, waveform) in stemWaveforms.prefix(4).enumerated() {
                let url = dumpDir.appendingPathComponent("\(names[i]).wav")
                SessionRecorder.writeWav(samples: waveform, sampleRate: sampleRate, to: url)
            }
            // Write log line directly — calling self.log() would re-enqueue
            // on the same serial queue and miss the window opened by finish().
            self.writeLogLine("stem separation \(idx) "
                              + "(\(stemWaveforms[0].count) samples) "
                              + "track=\(safeTitle) → \(dumpDir.lastPathComponent)")
        }
    }

    /// Synchronous log write — for use from inside the recorder's own queue.
    private func writeLogLine(_ message: String) {
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

            // Raw tap WAV finalisation — patch chunk sizes before closing.
            // Handle may be nil if the duration cap was already reached
            // (finalizeRawTapHeader handles that by reopening for update).
            // Set rawTapDone FIRST so any in-flight appendRawTapBytes calls
            // enqueued before finish() short-circuit immediately.
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

    // MARK: - Video encoding

    private func appendVideoFrame(from tex: MTLTexture, wallclock: CFAbsoluteTime) {
        let width = tex.width
        let height = tex.height

        if videoWriter == nil {
            // Defer initial setup until drawable size has been stable for
            // `videoSizeStableThreshold` frames. Drops the very early frames
            // where size may not yet match the steady-state render area.
            if let last = lastObservedDims, last.width == width, last.height == height {
                sameDimsStreak += 1
            } else {
                lastObservedDims = (width, height)
                sameDimsStreak = 1
            }
            guard sameDimsStreak >= videoSizeStableThreshold else { return }
            guard setupVideoWriter(width: width, height: height) else { return }
            writerLockedDims = (width, height)
            writeLogLine("video writer locked to \(width)x\(height) after \(sameDimsStreak) stable frames")
        }

        // Compare against the WRITER's locked dimensions. If the drawable
        // doesn't match the lock, either (a) skip the frame (normal
        // mid-session resize), or (b) relock to the new size if it has
        // been the steady-state for `writerRelockThreshold` frames — this
        // recovers from a bad initial lock (session 2026-04-16T20-09-44Z
        // locked to Retina-native 1802×1202 then lost 1861 frames at the
        // steady-state 901×601).
        //
        // Lock-check MUST run before the adaptor/input guard below —
        // setupVideoWriter replaces pixelAdaptor and videoInput, so any
        // references captured before the relock would be stale.
        let lockedW = writerLockedDims?.width ?? 0
        let lockedH = writerLockedDims?.height ?? 0
        if lockedW != width || lockedH != height {
            skippedFrameCount += 1
            if let meta = mismatchedDims, meta.width == width, meta.height == height {
                mismatchedDimsStreak += 1
            } else {
                mismatchedDims = (width, height)
                mismatchedDimsStreak = 1
            }
            if mismatchedDimsStreak >= writerRelockThreshold {
                writeLogLine("video writer relocking: drawable stabilised at \(width)x\(height),"
                    + " was locked at \(lockedW)x\(lockedH) (skipped \(skippedFrameCount) frames)")
                tearDownVideoWriter()
                if setupVideoWriter(width: width, height: height) {
                    writerLockedDims = (width, height)
                    writeLogLine("video writer relocked to \(width)x\(height)")
                    skippedFrameCount = 0
                    mismatchedDims = nil
                    mismatchedDimsStreak = 0
                    // Fall through to write this frame into the new writer.
                } else {
                    writeLogLine("video writer relock FAILED — video output disabled")
                    return
                }
            } else {
                if skippedFrameCount % 30 == 1 {
                    writeLogLine("video frame skipped: drawable \(width)x\(height)"
                        + " != writer \(lockedW)x\(lockedH) (skip count: \(skippedFrameCount))")
                }
                return
            }
        }

        guard let adaptor = pixelAdaptor,
              let pool = adaptor.pixelBufferPool,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData else {
            return
        }

        var maybeBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer = maybeBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        tex.getBytes(base,
                     bytesPerRow: bytesPerRow,
                     from: MTLRegionMake2D(0, 0, width, height),
                     mipmapLevel: 0)

        if videoStartTime == nil {
            let startTime = CMTime(value: CMTimeValue(wallclock * 1_000_000),
                                   timescale: 1_000_000)
            videoStartTime = startTime
            videoWriter?.startSession(atSourceTime: startTime)
        }
        let pts = CMTime(value: CMTimeValue(wallclock * 1_000_000),
                         timescale: 1_000_000)
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    /// Tear down the current writer without finalising. Used only when the
    /// original lock was bad (drawable stabilised at a different size than
    /// the initial 30-frame streak). Discards the transient footage by
    /// deleting the partial file so setupVideoWriter can recreate it.
    private func tearDownVideoWriter() {
        if let input = videoInput {
            input.markAsFinished()
        }
        if let writer = videoWriter, writer.status == .writing {
            writer.cancelWriting()
        }
        videoWriter = nil
        videoInput = nil
        pixelAdaptor = nil
        videoStartTime = nil
        lastVideoFrameTime = 0
        // AVAssetWriter refuses to init with an existing output URL; remove
        // the partial file so setupVideoWriter can recreate it at the new size.
        try? FileManager.default.removeItem(at: videoURL)
    }

    private func setupVideoWriter(width: Int, height: Int) -> Bool {
        do {
            let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let pbAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: pbAttributes
            )
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            guard writer.startWriting() else {
                logger.error("AVAssetWriter.startWriting failed: \(writer.error?.localizedDescription ?? "nil")")
                return false
            }
            self.videoWriter = writer
            self.videoInput = input
            self.pixelAdaptor = adaptor
            return true
        } catch {
            logger.error("AVAssetWriter init failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - CSV row formatting

    // swiftlint:disable multiline_arguments
    private static func csvRow(features fv: FeatureVector, frame: Int, wallclock: CFAbsoluteTime) -> String {
        String(format: "%d,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                     + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f\n",
               frame, wallclock, fv.time, fv.deltaTime,
               fv.bass, fv.mid, fv.treble,
               fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high,
               fv.beatBass, fv.beatMid, fv.beatTreble, fv.beatComposite,
               fv.spectralCentroid, fv.spectralFlux, fv.valence, fv.arousal,
               fv.accumulatedAudioTime)
    }

    private static func csvRow(stems stems: StemFeatures, frame: Int, wallclock: CFAbsoluteTime) -> String {
        // Base (16) + MV-1 dev (8) + MV-3a rich (16) + MV-3c pitch (2) = 42 floats + frame + wallclock.
        let base = String(format: "%d,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                                + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
                          frame, wallclock,
                          stems.drumsEnergy, stems.drumsBeat, stems.drumsBand0, stems.drumsBand1,
                          stems.bassEnergy, stems.bassBeat, stems.bassBand0, stems.bassBand1,
                          stems.vocalsEnergy, stems.vocalsBeat, stems.vocalsBand0, stems.vocalsBand1,
                          stems.otherEnergy, stems.otherBeat, stems.otherBand0, stems.otherBand1)
        let dev = String(format: ",%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
                         stems.drumsEnergyRel, stems.drumsEnergyDev,
                         stems.bassEnergyRel, stems.bassEnergyDev,
                         stems.vocalsEnergyRel, stems.vocalsEnergyDev,
                         stems.otherEnergyRel, stems.otherEnergyDev)
        let rich = String(format: ",%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                                + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
                          stems.drumsOnsetRate, stems.drumsCentroid, stems.drumsAttackRatio, stems.drumsEnergySlope,
                          stems.bassOnsetRate, stems.bassCentroid, stems.bassAttackRatio, stems.bassEnergySlope,
                          stems.vocalsOnsetRate, stems.vocalsCentroid, stems.vocalsAttackRatio, stems.vocalsEnergySlope,
                          stems.otherOnsetRate, stems.otherCentroid, stems.otherAttackRatio, stems.otherEnergySlope)
        let pitch = String(format: ",%.3f,%.4f\n",
                           stems.vocalsPitchHz, stems.vocalsPitchConfidence)
        return base + dev + rich + pitch
    }
    // swiftlint:enable multiline_arguments

    // MARK: - Raw tap diagnostic capture

    /// Copy the most recent Core Audio tap samples into the raw_tap.wav
    /// diagnostic file.  Safe to call from the IO proc — heavy I/O is
    /// dispatched onto the recorder queue.  Automatically stops after
    /// `rawTapDurationSeconds` of audio to cap file size.
    ///
    /// The resulting WAV is stream-written as IEEE 754 Float32 PCM, which
    /// preserves the exact bytes the macOS audio server delivered to us —
    /// no sample-rate conversion, no bit-depth quantisation, no AGC.  This
    /// is Stage 4 ground truth for spectral diagnostics.
    public func recordRawTapSamples(
        pointer: UnsafePointer<Float>,
        count: Int,
        sampleRate: Float,
        channelCount: UInt32
    ) {
        guard count > 0 else { return }
        // Copy samples off the real-time thread before the pointer becomes
        // invalid.  Dispatch the write to the recorder queue.
        let byteCount = count * MemoryLayout<Float>.size
        let data = Data(bytes: pointer, count: byteCount)
        let sr = UInt32(sampleRate)
        let ch = UInt16(channelCount)
        queue.async { [weak self] in
            self?.appendRawTapBytes(
                data: data,
                sampleRate: sr,
                channelCount: ch,
                sampleCount: count
            )
        }
    }

    /// Recorder-queue work.  Opens the file on first call, writes a stub
    /// header with zero chunk sizes (finalized in `finish()`), appends the
    /// samples, and stops once the duration cap is reached.
    private func appendRawTapBytes(
        data: Data,
        sampleRate: UInt32,
        channelCount: UInt16,
        sampleCount: Int
    ) {
        // Honour the done flag and the recorder-wide shutdown flag — both
        // guard against reopening/truncating a completed capture.
        if rawTapDone || didFinish { return }

        if rawTapHandle == nil {
            // Lazy-open on first sample so we pick up the real format.
            rawTapSampleRate = sampleRate
            rawTapChannels = channelCount
            rawTapMaxSamples = Int(rawTapDurationSeconds * Double(sampleRate)
                                   * Double(channelCount))
            FileManager.default.createFile(atPath: rawTapURL.path, contents: nil)
            guard let fh = try? FileHandle(forWritingTo: rawTapURL) else {
                logger.error("SessionRecorder could not open raw_tap.wav")
                return
            }
            rawTapHandle = fh
            writeRawTapHeaderStub(
                to: fh,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
            rawTapHeaderWritten = true
            log("raw tap capture started sr=\(sampleRate) Hz ch=\(channelCount) max=\(Int(rawTapDurationSeconds))s")
        }

        guard let fh = rawTapHandle else { return }

        // Enforce the duration cap — never overshoot.
        let remaining = rawTapMaxSamples - rawTapSamplesWritten
        if remaining <= 0 {
            return
        }
        let samplesToWrite = min(sampleCount, remaining)
        let bytesToWrite = samplesToWrite * MemoryLayout<Float>.size
        if bytesToWrite == data.count {
            fh.write(data)
        } else {
            fh.write(data.prefix(bytesToWrite))
        }
        rawTapSamplesWritten += samplesToWrite

        if rawTapSamplesWritten >= rawTapMaxSamples {
            finalizeRawTapHeader()
            try? fh.close()
            rawTapHandle = nil
            rawTapDone = true
            log("raw tap capture complete \(rawTapSamplesWritten) samples (\(Int(rawTapDurationSeconds))s cap)")
        }
    }

    /// Write a 44-byte WAVE header with placeholder sizes.  Finalized in
    /// `finalizeRawTapHeader()` once we know how many bytes of audio data
    /// were actually captured.  Format is WAVE_FORMAT_IEEE_FLOAT (0x0003),
    /// 32-bit float, interleaved.
    private func writeRawTapHeaderStub(
        to fh: FileHandle,
        sampleRate: UInt32,
        channelCount: UInt16
    ) {
        let bytesPerSample: UInt16 = 4  // Float32
        let blockAlign: UInt16 = channelCount * bytesPerSample
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)

        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: UInt32(0).littleEndianBytes)                    // chunkSize — patched
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(contentsOf: UInt32(16).littleEndianBytes)                   // fmt chunk size
        header.append(contentsOf: UInt16(3).littleEndianBytes)                    // WAVE_FORMAT_IEEE_FLOAT
        header.append(contentsOf: channelCount.littleEndianBytes)
        header.append(contentsOf: sampleRate.littleEndianBytes)
        header.append(contentsOf: byteRate.littleEndianBytes)
        header.append(contentsOf: blockAlign.littleEndianBytes)
        header.append(contentsOf: UInt16(32).littleEndianBytes)                   // bits per sample
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: UInt32(0).littleEndianBytes)                    // data size — patched
        fh.write(header)
    }

    /// Patch the RIFF chunkSize and data chunkSize fields with the real
    /// byte counts.  Called when the duration cap is hit and in `finish()`.
    private func finalizeRawTapHeader() {
        guard let fh = rawTapHandle else {
            // Handle may have been closed already — reopen for patching.
            guard rawTapHeaderWritten,
                  let fh = try? FileHandle(forUpdating: rawTapURL) else { return }
            patchRawTapHeader(fh: fh)
            try? fh.close()
            return
        }
        patchRawTapHeader(fh: fh)
    }

    private func patchRawTapHeader(fh: FileHandle) {
        let dataBytes = UInt32(rawTapSamplesWritten * MemoryLayout<Float>.size)
        let riffChunkSize = UInt32(36) + dataBytes

        // Seek to offset 4 → RIFF chunkSize.
        try? fh.seek(toOffset: 4)
        fh.write(Data(riffChunkSize.littleEndianBytes))
        // Seek to offset 40 → data subchunk size.
        try? fh.seek(toOffset: 40)
        fh.write(Data(dataBytes.littleEndianBytes))
        // Restore write position to end so any later writes append correctly.
        _ = try? fh.seekToEnd()
    }

    // MARK: - WAV writer

    /// Write a mono Float32 waveform as a 16-bit PCM WAV file.
    private static func writeWav(samples: [Float], sampleRate: Int, to url: URL) {
        var data = Data()
        let byteRate = sampleRate * 2  // mono, 16-bit
        let dataSize = samples.count * 2
        let chunkSize = 36 + dataSize

        data.append(contentsOf: Array("RIFF".utf8))
        data.append(contentsOf: UInt32(chunkSize).littleEndianBytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.append(contentsOf: UInt32(16).littleEndianBytes)         // PCM chunk size
        data.append(contentsOf: UInt16(1).littleEndianBytes)          // PCM format
        data.append(contentsOf: UInt16(1).littleEndianBytes)          // mono
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: UInt32(byteRate).littleEndianBytes)
        data.append(contentsOf: UInt16(2).littleEndianBytes)          // block align
        data.append(contentsOf: UInt16(16).littleEndianBytes)         // bits per sample
        data.append(contentsOf: Array("data".utf8))
        data.append(contentsOf: UInt32(dataSize).littleEndianBytes)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            // Round to nearest integer — Int16(float) traps on non-integer values.
            let pcm = Int16((clamped * 32767.0).rounded())
            data.append(contentsOf: UInt16(bitPattern: pcm).littleEndianBytes)
        }
        try? data.write(to: url)
    }
}

// MARK: - Little-endian helpers

private extension UInt16 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF)]
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        [UInt8(self & 0xFF),
         UInt8((self >> 8) & 0xFF),
         UInt8((self >> 16) & 0xFF),
         UInt8((self >> 24) & 0xFF)]
    }
}
