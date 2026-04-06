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

// MARK: - StemSeparating

/// Abstraction over CoreML stem separation.
///
/// Concrete implementation: `StemSeparator` (ML module).
/// Test double: `FakeStemSeparator`.
public protocol StemSeparating: AnyObject, Sendable {
    /// Separate interleaved PCM audio into four stems (vocals, drums, bass, other).
    ///
    /// - Parameters:
    ///   - audio: Interleaved float32 PCM samples.
    ///   - channelCount: Number of channels (1 for mono, 2 for stereo).
    ///   - sampleRate: Sample rate in Hz (will be resampled to 44100 if different).
    /// - Returns: Separation result with metadata and sample count.
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult

    /// Ordered stem labels: `["vocals", "drums", "bass", "other"]`.
    var stemLabels: [String] { get }

    /// Four UMA output buffers, one per stem (same order as `stemLabels`).
    var stemBuffers: [UMABuffer<Float>] { get }
}

// MARK: - StemSeparationResult

/// Result of a stem separation pass.
public struct StemSeparationResult: Sendable {
    /// Per-stem AudioFrame metadata.
    public let stemData: StemData
    /// Number of mono samples written per stem.
    public let sampleCount: Int

    public init(stemData: StemData, sampleCount: Int) {
        self.stemData = stemData
        self.sampleCount = sampleCount
    }
}

// MARK: - StemSeparationError

public enum StemSeparationError: Error, Sendable {
    case modelNotFound
    case modelLoadFailed(String)
    case predictionFailed(String)
    case insufficientSamples(Int)
}

// MARK: - TrackChangeEvent

/// Emitted when the currently playing track changes.
public struct TrackChangeEvent: Sendable {
    /// The previously playing track, or nil if this is the first detection.
    public let previous: TrackMetadata?
    /// The newly detected track.
    public let current: TrackMetadata
    /// When the change was detected.
    public let timestamp: Date

    public init(previous: TrackMetadata? = nil, current: TrackMetadata, timestamp: Date = Date()) {
        self.previous = previous
        self.current = current
        self.timestamp = timestamp
    }
}

// MARK: - MoodClassifying

/// Abstraction over CoreML mood classification.
///
/// Concrete implementation: `MoodClassifier` (ML module).
/// Test double: `StubMoodClassifier`.
public protocol MoodClassifying: AnyObject, Sendable {
    /// Classify mood from audio features.
    ///
    /// - Parameter features: Array of 10 floats:
    ///   `[subBass, lowBass, lowMid, midHigh, highMid, high,
    ///    spectralCentroid, spectralFlux,
    ///    majorKeyCorrelation, minorKeyCorrelation]`
    /// - Returns: EmotionalState with valence and arousal.
    func classify(features: [Float]) throws -> EmotionalState

    /// Latest smoothed emotional state (EMA-filtered).
    var currentState: EmotionalState { get }
}

// MARK: - MoodClassificationError

/// Errors from the mood classification pipeline.
public enum MoodClassificationError: Error, Sendable {
    /// CoreML model bundle not found in the module resources.
    case modelNotFound
    /// CoreML model failed to load.
    case modelLoadFailed(String)
    /// CoreML prediction failed.
    case predictionFailed(String)
    /// Wrong number of input features (expected 20).
    case invalidFeatureCount(Int)
}

// MARK: - MetadataProviding

/// Abstraction over streaming metadata observation (Now Playing polling).
///
/// Concrete implementation: `StreamingMetadata`.
public protocol MetadataProviding: AnyObject, Sendable {
    /// Called when the currently playing track changes.
    var onTrackChange: ((_ event: TrackChangeEvent) -> Void)? { get set }

    /// The currently detected track, or nil if nothing is playing.
    var currentTrack: TrackMetadata? { get }

    /// Start polling for track changes.
    func startObserving()

    /// Stop polling and release resources.
    func stopObserving()
}

// MARK: - PartialTrackProfile

/// Partial metadata returned by a single external API fetcher.
///
/// Multiple `PartialTrackProfile` values are merged into a single
/// `PreFetchedTrackProfile` by `MetadataPreFetcher`.
public struct PartialTrackProfile: Sendable {
    public var bpm: Float?
    public var key: String?
    public var energy: Float?
    public var valence: Float?
    public var danceability: Float?
    public var genreTags: [String]
    public var duration: Double?

    public init(
        bpm: Float? = nil,
        key: String? = nil,
        energy: Float? = nil,
        valence: Float? = nil,
        danceability: Float? = nil,
        genreTags: [String] = [],
        duration: Double? = nil
    ) {
        self.bpm = bpm
        self.key = key
        self.energy = energy
        self.valence = valence
        self.danceability = danceability
        self.genreTags = genreTags
        self.duration = duration
    }
}

// MARK: - MetadataFetching

/// Abstraction over an external music metadata API (MusicBrainz, Spotify, etc.).
///
/// Each concrete fetcher queries one source and returns partial data.
/// `MetadataPreFetcher` runs multiple fetchers in parallel and merges results.
public protocol MetadataFetching: Sendable {
    /// Human-readable name of this source (e.g. "MusicBrainz", "Spotify").
    var sourceName: String { get }

    /// Query this source for track metadata.
    /// Returns nil on failure or timeout — failures are always silent.
    func fetch(title: String, artist: String) async -> PartialTrackProfile?
}
