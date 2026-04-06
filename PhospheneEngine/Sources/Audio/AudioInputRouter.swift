// AudioInputRouter — Unified audio input abstraction.
// Routes audio from one of three sources into a callback:
//   1. System audio via Core Audio taps (default)
//   2. Specific-app audio via Core Audio taps
//   3. Local file via AVAudioFile (fallback for testing/offline use)
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
    /// Play from a local audio file (testing/offline fallback).
    case localFile(URL)
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

    private var currentMode: InputMode?
    private let systemCapture: any AudioCapturing
    private var filePlaybackTask: Task<Void, Never>?
    private let lock = NSLock()

    /// Monotonically increasing timestamp base.
    private var captureStartTime: Double = 0

    // MARK: - Init

    /// Create an AudioInputRouter.
    ///
    /// - Parameter capture: Audio capture backend. Defaults to `SystemAudioCapture`.
    public init(capture: any AudioCapturing = SystemAudioCapture()) {
        self.systemCapture = capture
    }

    // MARK: - Callback

    /// Called for each chunk of audio samples.
    /// Parameters: (pointer to interleaved float32 samples, sample count, sample rate, channel count).
    /// For system/app capture this is called on a real-time audio thread — do not allocate or block.
    public var onAudioSamples: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                                 _ sampleRate: Float, _ channelCount: UInt32) -> Void)?

    // MARK: - Public API

    /// Start audio input with the given mode.
    ///
    /// - Parameter mode: Which source to use. Defaults to `.systemAudio`.
    public func start(mode: InputMode = .systemAudio) throws {
        stopInternal()

        captureStartTime = CACurrentMediaTime()
        lock.withLock { currentMode = mode }

        switch mode {
        case .systemAudio:
            systemCapture.onAudioBuffer = { [weak self] samples, count, rate, channels in
                self?.onAudioSamples?(samples, count, rate, channels)
            }
            try systemCapture.startCapture(mode: .systemAudio)
            logger.info("Router started: system audio")

        case .application(let bundleID):
            systemCapture.onAudioBuffer = { [weak self] samples, count, rate, channels in
                self?.onAudioSamples?(samples, count, rate, channels)
            }
            try systemCapture.startCapture(mode: .application(bundleIdentifier: bundleID))
            logger.info("Router started: app audio (\(bundleID))")

        case .localFile(let url):
            startFilePlayback(url: url)
            logger.info("Router started: local file (\(url.lastPathComponent))")
        }
    }

    /// Switch to a different input mode.
    public func switchMode(_ mode: InputMode) throws {
        let current = lock.withLock { currentMode }
        guard mode != current else { return }

        stopInternal()
        try start(mode: mode)
    }

    /// Stop all audio input.
    public func stop() {
        stopInternal()
        logger.info("Router stopped")
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

    // MARK: - Local File Playback

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

                while !Task.isCancelled {
                    try file.read(into: buffer, frameCount: chunkSize)
                    if buffer.frameLength == 0 {
                        file.framePosition = 0
                        continue
                    }

                    guard let floatData = buffer.floatChannelData else { continue }

                    let frames = Int(buffer.frameLength)
                    let totalSamples = frames * Int(channelCount)
                    var interleaved = [Float](repeating: 0, count: totalSamples)

                    if channelCount == 2 {
                        let left = floatData[0]
                        let right = floatData[1]
                        for i in 0..<frames {
                            interleaved[i * 2] = left[i]
                            interleaved[i * 2 + 1] = right[i]
                        }
                    } else {
                        let src = UnsafeBufferPointer(start: floatData[0], count: totalSamples)
                        interleaved = Array(src)
                    }

                    interleaved.withUnsafeBufferPointer { ptr in
                        guard let base = ptr.baseAddress else { return }
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
        case nil:
            break
        }

        lock.withLock { currentMode = nil }
    }
}
