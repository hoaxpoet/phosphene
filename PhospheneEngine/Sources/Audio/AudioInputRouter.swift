// AudioInputRouter — Unified audio input abstraction.
// Routes audio from one of four sources into a callback:
//   1. System audio via Core Audio taps (default)
//   2. Specific-app audio via Core Audio taps
//   3. Local file via AVAudioFile (diagnostic / offline injection — does NOT play audio)
//   4. Local file via AVAudioEngine playback (plays audio + taps player node — LF.1)
//
// Consumers receive audio via a callback regardless of source.
// Mode switching is seamless.

import Foundation
import AVFoundation
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.audio", category: "AudioInputRouter")

// MARK: - InputMode

/// The active audio input source.
public enum InputMode: Sendable, Equatable {
    /// Capture entire system audio mix (default).
    case systemAudio
    /// Capture audio from a specific application.
    case application(bundleIdentifier: String)
    /// Feed PCM from a local audio file into the analysis pipeline at
    /// near-real-time, without playing audio through speakers. Used by
    /// `SoakTestHarness` and the diagnostic capture-mode toggle (D-052).
    /// Does NOT install a process tap and does NOT participate in the
    /// tap-reinstall scheduler.
    case localFile(URL)
    /// Play a local audio file through the default output device via
    /// `AVAudioEngine`, with the analysis tap installed on the player
    /// node (pre-mixer, pre-volume). Bypasses Core Audio process taps
    /// entirely — no screen-capture permission required. LF.1 spike.
    case localFilePlayback(URL)
}

// MARK: - AudioInputRouter

/// Provides unified audio input from any supported source.
///
/// Set `onAudioSamples` before calling `start()`. Audio data is delivered
/// as interleaved float32 PCM on a real-time audio thread (for system/app
/// capture) or a background thread (for file playback).
@available(macOS 14.2, *)
public final class AudioInputRouter: @unchecked Sendable {

    // MARK: - State

    var currentMode: InputMode?
    let systemCapture: any AudioCapturing
    private let metadataProvider: (any MetadataProviding)?
    private var filePlaybackTask: Task<Void, Never>?
    /// Owned by the router while `.localFilePlayback(URL)` is active.
    /// Created in `startFilePlayback(playback:)` and torn down in
    /// `stopInternal()`. LF.1.
    private var localFilePlaybackProvider: LocalFilePlaybackProvider?
    let lock = NSLock()

    /// Monotonically increasing timestamp base.
    private var captureStartTime: Double = 0

    /// Silence / DRM detection state machine.
    let silenceDetector: SilenceDetector

    // MARK: - Tap Reinstall (scrub-recovery)

    /// Serial queue for tap teardown/reinstall work. Off the realtime thread
    /// because reinstalling involves destroying + recreating Core Audio devices.
    let tapMgmtQueue = DispatchQueue(
        label: "com.phosphene.audio.tap-mgmt", qos: .utility)

    /// Number of reinstall attempts since the most recent `.silent` entry.
    /// Reset on transition to `.active`.
    var reinstallAttempts: Int = 0

    /// Pending reinstall work item, if any. Cancelled on `.active`.
    var reinstallWorkItem: DispatchWorkItem?

    /// Backoff schedule for tap-reinstall attempts after entering `.silent`.
    /// 3 attempts is enough to ride out a typical scrub-induced disconnect
    /// without thrashing if the user actually paused the music.
    let reinstallDelays: [TimeInterval] = [3.0, 10.0, 30.0]

    // MARK: - Init

    /// Create an AudioInputRouter.
    ///
    /// - Parameters:
    ///   - capture: Audio capture backend. Defaults to `SystemAudioCapture`.
    ///   - metadata: Optional metadata provider for track change detection.
    public init(capture: any AudioCapturing = SystemAudioCapture(),
                metadata: (any MetadataProviding)? = nil) {
        self.systemCapture = capture
        self.metadataProvider = metadata
        self.silenceDetector = SilenceDetector()

        silenceDetector.onStateChanged = { [weak self] newState in
            self?.handleSignalStateChange(newState)
        }
    }

    /// Internal initializer with injectable silence detector (used by tests).
    init(capture: any AudioCapturing,
         metadata: (any MetadataProviding)?,
         silenceDetector: SilenceDetector) {
        self.systemCapture = capture
        self.metadataProvider = metadata
        self.silenceDetector = silenceDetector

        silenceDetector.onStateChanged = { [weak self] newState in
            self?.handleSignalStateChange(newState)
        }
    }

    // MARK: - Callbacks

    /// Called for each chunk of audio samples.
    /// Parameters: (pointer to interleaved float32 samples, sample count, sample rate, channel count).
    /// For system/app capture this is called on a real-time audio thread — do not allocate or block.
    public var onAudioSamples: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                                 _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    /// Called with the latest analyzed frame from the analysis head (real-time).
    /// Use for anticipatory decisions (e.g., Orchestrator pre-planning transitions).
    public var onAnalysisFrame: ((_ frame: AnalyzedFrame) -> Void)?

    /// Called with the delayed analyzed frame from the render head.
    /// Use for synchronized visual rendering (lags analysis head by `LookaheadBuffer.delay`).
    public var onRenderFrame: ((_ frame: AnalyzedFrame) -> Void)?

    /// Called when the currently playing track changes.
    public var onTrackChange: ((_ event: TrackChangeEvent) -> Void)?

    /// Called when the audio signal state transitions (e.g., `.active` → `.silent`).
    ///
    /// Invoked on the real-time audio thread for system/app capture, or on a background
    /// thread for file playback. Dispatch to the main actor before touching UI or
    /// `@Published` properties.
    public var onSignalStateChanged: ((_ state: AudioSignalState) -> Void)?

    /// LF.5 — Fires when the `.localFilePlayback(URL)` mode's audio file
    /// reaches end-of-stream. When set, the underlying
    /// `LocalFilePlaybackProvider` will NOT loop the file at EOF; instead
    /// this callback drives the LF.5 queue advance via
    /// `VisualizerEngine.advanceLocalFileQueue()`. When nil (LF.1 / LF.4
    /// default), the provider loops the file forever (preserved single-file
    /// dev workflow).
    ///
    /// MUST be set BEFORE `start(mode: .localFilePlayback(url))`; the value
    /// captured at start time is relayed into the provider's `onFileEnded`.
    /// Subsequent assignments take effect on the NEXT `start()`, not
    /// retroactively. Engine consumers re-bind on every per-track restart.
    ///
    /// Invoked on the AVAudioEngine scheduleFile completion thread; consumers
    /// hop to MainActor before touching UI or @Published state.
    public var onLocalFilePlaybackEnded: (@Sendable () -> Void)?

    /// BUG-021 (2026-05-28) — diagnostic hook forwarded into the
    /// `LocalFilePlaybackProvider` so each `_stopLocked` sub-step writes a
    /// breadcrumb on the call thread. App-layer wires this to
    /// `SessionRecorder.log`. Captured at install time in
    /// `startLocalFilePlayback`; subsequent changes apply only after the
    /// next `start()`.
    public var onLocalFilePlaybackDiagnostic: ((String) -> Void)?

    /// BUG-057 sink — `SystemAudioCapture` install/RMS lines + this router's
    /// `.silent → reinstall` events. App wires it to `SessionRecorder.log`.
    public var onAudioCaptureDiagnostic: ((String) -> Void)?

    /// Current audio signal state as determined by the silence detector.
    public var signalState: AudioSignalState {
        silenceDetector.state
    }

    // MARK: - Public API

    /// Start audio input with the given mode.
    ///
    /// - Parameter mode: Which source to use. Defaults to `.systemAudio`.
    public func start(mode: InputMode = .systemAudio) throws {
        stopInternal()

        // BUG-057: forward capture install/RMS diagnostics to the app sink (cold install + device-change reinstalls).
        systemCapture.onCaptureDiagnostic = { [weak self] msg in
            self?.onAudioCaptureDiagnostic?(msg)
        }

        captureStartTime = CACurrentMediaTime()
        lock.withLock { currentMode = mode }
        silenceDetector.resetSignalHistory()  // BUG-057: clear "ever had audio" latch (fresh session)
        switch mode {
        case .systemAudio:
            systemCapture.onAudioBuffer = { [weak self] samples, count, rate, channels in
                self?.silenceDetector.update(samples: samples, count: count)
                self?.onAudioSamples?(samples, count, rate, channels)
            }
            try systemCapture.startCapture(mode: .systemAudio)
            logger.info("Router started: system audio")

        case .application(let bundleID):
            systemCapture.onAudioBuffer = { [weak self] samples, count, rate, channels in
                self?.silenceDetector.update(samples: samples, count: count)
                self?.onAudioSamples?(samples, count, rate, channels)
            }
            try systemCapture.startCapture(mode: .application(bundleIdentifier: bundleID))
            logger.info("Router started: app audio (\(bundleID))")

        case .localFile(let url):
            startFilePlayback(url: url)
            logger.info("Router started: local file (\(url.lastPathComponent))")

        case .localFilePlayback(let url):
            try startLocalFilePlayback(url: url)
            logger.info(
                "[LF.1] Router started: local-file playback (\(url.lastPathComponent))")
        }

        // Wire metadata observation if a provider is configured.
        if let provider = metadataProvider {
            provider.onTrackChange = { [weak self] event in
                self?.onTrackChange?(event)
            }
            provider.startObserving()
        }
    }

    /// Start metadata observation without audio capture.
    ///
    /// Metadata polling (MediaRemote) does not require screen capture permission,
    /// so it can start before permission is granted. Call `start(mode:)` separately
    /// once audio capture permission is available.
    public func startMetadataOnly() {
        if let provider = metadataProvider {
            provider.onTrackChange = { [weak self] event in
                self?.onTrackChange?(event)
            }
            provider.startObserving()
            logger.info("Metadata observation started (audio capture pending)")
        }
    }

    /// Stop all audio input.
    public func stop() {
        stopInternal()
        logger.info("Router stopped")
    }

    /// Pause LF playback in place (engine + tap stay alive; player retains
    /// position). No-op for non-LF modes. LF.5.fix D-LF5-3.
    public func pauseLocalFilePlayback() {
        localFilePlaybackProvider?.pause()
    }

    /// Resume LF playback from the paused position. No-op for non-LF modes
    /// or when the player isn't paused.
    public func resumeLocalFilePlayback() {
        localFilePlaybackProvider?.resume()
    }

    /// `true` when LF playback is paused (engine alive, player not playing).
    /// `false` in every other state (stopped / actively playing / non-LF mode).
    public var isLocalFilePlaybackPaused: Bool {
        localFilePlaybackProvider?.isPaused ?? false
    }

    /// The currently active input mode, or nil if stopped.
    public var activeMode: InputMode? {
        lock.withLock { currentMode }
    }

    /// The sample rate of the active capture (from Core Audio tap format).
    public var sampleRate: Float {
        systemCapture.sampleRate
    }

    /// The channel count of the active capture.
    public var channelCount: UInt32 {
        systemCapture.channelCount
    }

    /// The currently detected track metadata, or nil if unavailable.
    public var currentTrack: TrackMetadata? {
        metadataProvider?.currentTrack
    }

    // MARK: - Local File Playback (LF.1 — speakers + analysis tap)

    /// Start `LocalFilePlaybackProvider` and forward its analysis tap into
    /// the router's `onAudioSamples` callback + `SilenceDetector`. The
    /// callback signature matches the process-tap path exactly, so the
    /// downstream analysis pipeline is source-agnostic.
    ///
    /// LF.5: when `onLocalFilePlaybackEnded` is non-nil, it is relayed into
    /// the provider's `onFileEnded` so the queue advances at EOF instead of
    /// looping. Nil-callback preserves the LF.1 loop-forever default.
    private func startLocalFilePlayback(url: URL) throws {
        let provider = LocalFilePlaybackProvider(url: url)
        provider.onAudioSamples = { [weak self] samples, count, rate, channels in
            self?.silenceDetector.update(samples: samples, count: count)
            self?.onAudioSamples?(samples, count, rate, channels)
        }
        provider.onFileEnded = onLocalFilePlaybackEnded
        provider.onDiagnosticEvent = onLocalFilePlaybackDiagnostic
        try provider.start()
        localFilePlaybackProvider = provider
    }

    // MARK: - Local File Diagnostic Injection (offline — does NOT play audio)

    private func startFilePlayback(url: URL) {
        let callback = onAudioSamples
        filePlaybackTask = Task.detached { [weak self] in
            do {
                let file = try AVAudioFile(forReading: url)
                let format = file.processingFormat
                let sampleRate = Float(format.sampleRate)
                let channelCount = UInt32(format.channelCount)
                let chunkSize: AVAudioFrameCount = 1024

                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return }
                let frameDuration = Double(chunkSize) / Double(sampleRate)

                // Pre-allocate the interleaved buffer once and reuse it across
                // chunks. `chunkSize` and `channelCount` are loop invariants, so
                // we size to the maximum-possible frame; short final reads simply
                // leave a stale tail past `totalSamples` that the callback never
                // sees.
                let maxSamples = Int(chunkSize) * Int(channelCount)
                var interleaved = [Float](repeating: 0, count: maxSamples)

                while !Task.isCancelled {
                    try file.read(into: buffer, frameCount: chunkSize)
                    if buffer.frameLength == 0 {
                        file.framePosition = 0
                        continue
                    }

                    guard let floatData = buffer.floatChannelData else { continue }

                    let frames = Int(buffer.frameLength)
                    let totalSamples = frames * Int(channelCount)

                    if channelCount == 2 {
                        let left = floatData[0]
                        let right = floatData[1]
                        for i in 0..<frames {
                            interleaved[i * 2] = left[i]
                            interleaved[i * 2 + 1] = right[i]
                        }
                    } else {
                        let src = floatData[0]
                        for i in 0..<totalSamples {
                            interleaved[i] = src[i]
                        }
                    }

                    interleaved.withUnsafeBufferPointer { ptr in
                        guard let base = ptr.baseAddress else { return }
                        self?.silenceDetector.update(samples: base, count: totalSamples)
                        callback?(base, totalSamples, sampleRate, channelCount)
                    }

                    try await Task.sleep(for: .seconds(frameDuration))
                }
            } catch {
                if !Task.isCancelled {
                    logger.error("File playback error: \(error.localizedDescription)")
                }
            }
            _ = self  // prevent premature dealloc
        }
    }

    // MARK: - Internal Teardown

    private func stopInternal() {
        let mode = lock.withLock { currentMode }

        switch mode {
        case .systemAudio, .application:
            systemCapture.stopCapture()
        case .localFile:
            filePlaybackTask?.cancel()
            filePlaybackTask = nil
        case .localFilePlayback:
            localFilePlaybackProvider?.stop()
            localFilePlaybackProvider = nil
        case nil:
            break
        }

        metadataProvider?.stopObserving()
        silenceDetector.reset()
        cancelPendingReinstall()

        lock.withLock { currentMode = nil }
    }
}
