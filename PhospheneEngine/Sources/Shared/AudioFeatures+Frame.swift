// AudioFeatures+Frame — @frozen, SIMD-aligned structs for per-frame audio data.
// AudioFrame, FFTResult, and StemData describe the raw audio capture output
// that flows from Core Audio taps through the analysis pipeline to the GPU.

import Foundation

// MARK: - AudioFrame

/// Metadata header for a block of PCM samples.
/// The actual sample data lives in a `UMABuffer<Float>` — this struct
/// describes which region of that buffer is valid.
@frozen
public struct AudioFrame: Sendable {
    /// Timestamp in seconds since capture start.
    public var timestamp: Double
    /// Sample rate in Hz (typically 48000).
    public var sampleRate: Float
    /// Number of valid samples per channel in the associated buffer.
    public var sampleCount: UInt32
    /// Number of channels (2 for stereo).
    public var channelCount: UInt32
    /// Byte offset into the associated UMABuffer where this frame's samples begin.
    public var bufferOffset: UInt32

    public init(
        timestamp: Double = 0,
        sampleRate: Float = 48000,
        sampleCount: UInt32 = 0,
        channelCount: UInt32 = 2,
        bufferOffset: UInt32 = 0
    ) {
        self.timestamp = timestamp
        self.sampleRate = sampleRate
        self.sampleCount = sampleCount
        self.channelCount = channelCount
        self.bufferOffset = bufferOffset
    }
}

// MARK: - FFTResult

/// Metadata for a single FFT analysis frame.
/// Magnitude and phase bin data live in separate `UMABuffer<Float>` instances,
/// uploaded as Metal buffer bindings for per-bin shader access.
@frozen
public struct FFTResult: Sendable {
    /// Number of magnitude bins (typically 512 from a 1024-point FFT).
    public var binCount: UInt32
    /// Frequency resolution per bin in Hz (sampleRate / fftSize).
    public var binResolution: Float
    /// Dominant (peak magnitude) frequency in Hz.
    public var dominantFrequency: Float
    /// Magnitude of the dominant bin (0–1 after AGC normalization).
    public var dominantMagnitude: Float

    public init(
        binCount: UInt32 = 512,
        binResolution: Float = 0,
        dominantFrequency: Float = 0,
        dominantMagnitude: Float = 0
    ) {
        self.binCount = binCount
        self.binResolution = binResolution
        self.dominantFrequency = dominantFrequency
        self.dominantMagnitude = dominantMagnitude
    }
}

// MARK: - StemData

/// Headers for the four CoreML-separated audio stems.
/// Each stem's PCM data lives in its own UMABuffer; this struct
/// bundles the metadata so the Orchestrator can route per-stem
/// analysis to the correct shader inputs.
@frozen
public struct StemData: Sendable {
    public var vocals: AudioFrame
    public var drums: AudioFrame
    public var bass: AudioFrame
    public var other: AudioFrame

    public init(
        vocals: AudioFrame = AudioFrame(),
        drums: AudioFrame = AudioFrame(),
        bass: AudioFrame = AudioFrame(),
        other: AudioFrame = AudioFrame()
    ) {
        self.vocals = vocals
        self.drums = drums
        self.bass = bass
        self.other = other
    }
}
