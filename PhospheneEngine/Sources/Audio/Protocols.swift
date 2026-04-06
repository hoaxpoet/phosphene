// Protocols — Dependency injection interfaces for audio capture and processing.
// Extracted from SystemAudioCapture, AudioBuffer, and FFTProcessor to enable
// test doubles and loose coupling.

import Foundation
import Metal
import Shared

// MARK: - AudioCapturing

/// Abstraction over system audio capture (Core Audio taps or test doubles).
///
/// Concrete implementation: `SystemAudioCapture`.
@available(macOS 14.2, *)
public protocol AudioCapturing: AnyObject, Sendable {
    /// Called on each audio IO callback with interleaved float32 PCM samples.
    /// Parameters: (pointer to samples, sample count, sample rate, channel count).
    /// Called on a real-time audio thread — do not allocate or block.
    var onAudioBuffer: ((_ samples: UnsafePointer<Float>, _ sampleCount: Int,
                         _ sampleRate: Float, _ channelCount: UInt32) -> Void)? { get set }

    /// Whether audio capture is currently active.
    var isCapturing: Bool { get }

    /// Sample rate reported by the capture source (typically 48kHz).
    var sampleRate: Float { get }

    /// Number of audio channels (typically 2 for stereo).
    var channelCount: UInt32 { get }

    /// Start capturing audio.
    func startCapture(mode: CaptureMode) throws

    /// Stop the current audio capture session.
    func stopCapture()
}

// MARK: - AudioBuffering

/// Abstraction over audio ring buffer for GPU consumption.
///
/// Concrete implementation: `AudioBuffer`.
public protocol AudioBuffering: AnyObject, Sendable {
    /// Write interleaved float32 PCM from a raw pointer into the ring buffer.
    @discardableResult
    func write(from pointer: UnsafePointer<Float>, count: Int) -> Int

    /// Copy the most recent N interleaved samples from the ring buffer.
    func latestSamples(count: Int) -> [Float]

    /// Most recent RMS level (linear, 0–1 range).
    var currentRMS: Float { get }

    /// The underlying MTLBuffer for binding to a Metal encoder.
    var metalBuffer: MTLBuffer { get }

    /// Reset the buffer to empty state.
    func reset()
}

// MARK: - FFTProcessing

/// Abstraction over FFT analysis.
///
/// Concrete implementation: `FFTProcessor`.
public protocol FFTProcessing: AnyObject, Sendable {
    /// Perform FFT on mono samples and write magnitudes to the output buffer.
    @discardableResult
    func process(samples: [Float], sampleRate: Float) -> FFTResult

    /// Mix interleaved stereo samples down to mono, then run FFT.
    @discardableResult
    func processStereo(interleavedSamples: [Float], sampleRate: Float) -> FFTResult

    /// UMA buffer holding magnitude bins for GPU binding.
    var magnitudeBuffer: UMABuffer<Float> { get }

    /// Most recent FFT result metadata.
    var latestResult: FFTResult { get }
}
