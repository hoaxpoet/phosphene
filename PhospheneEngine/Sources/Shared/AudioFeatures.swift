// AudioFeatures — @frozen, SIMD-aligned structs for audio analysis data.
// These types are the shared currency between CPU analysis, GPU shaders,
// and ANE inference. All use value semantics and fixed layouts suitable
// for direct upload to Metal buffers.

import Foundation
import simd

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

// MARK: - FeatureVector

/// Packed per-frame audio features for GPU uniform upload.
///
/// This is the primary struct that shaders receive every frame.
/// 24 floats = 96 bytes, naturally 16-byte aligned.
/// Fields follow the audio data hierarchy: continuous energy first,
/// spectral features second, onset pulses third.
///
/// The matching MSL struct:
/// ```metal
/// struct FeatureVector {
///     float bass, mid, treble;
///     float bass_att, mid_att, treb_att;
///     float sub_bass, low_bass, low_mid, mid_high, high_mid, high;
///     float beat_bass, beat_mid, beat_treble, beat_composite;
///     float spectral_centroid, spectral_flux;
///     float valence, arousal;
///     float time, delta_time;
///     float _pad0, _pad1;
/// };
/// ```
@frozen
public struct FeatureVector: Sendable {

    // --- Layer 1: Continuous energy bands (PRIMARY DRIVER) ---

    /// 3-band instant energy (fast smoothing).
    public var bass: Float
    public var mid: Float
    public var treble: Float

    /// 3-band attenuated energy (heavy smoothing, slow-flowing motion).
    public var bassAtt: Float
    public var midAtt: Float
    public var trebleAtt: Float

    /// 6-band energy (preserves relative differences via total-energy AGC).
    public var subBass: Float
    public var lowBass: Float
    public var lowMid: Float
    public var midHigh: Float
    public var highMid: Float
    public var high: Float

    // --- Layer 4: Onset pulses (ACCENT ONLY) ---

    /// Beat onset pulses, 0–1 with exponential decay.
    public var beatBass: Float
    public var beatMid: Float
    public var beatTreble: Float
    public var beatComposite: Float

    // --- Layer 3: Spectral features ---

    /// Spectral centroid — modulates palette warmth.
    public var spectralCentroid: Float
    /// Continuous spectral flux — rate of timbral change.
    public var spectralFlux: Float

    // --- Emotion (from ML) ---

    /// Valence: -1 (sad/tense) to +1 (happy/relaxed).
    public var valence: Float
    /// Arousal: -1 (calm) to +1 (energetic).
    public var arousal: Float

    // --- Timing ---

    /// Seconds since visualization start.
    public var time: Float
    /// Seconds since last frame.
    public var deltaTime: Float

    // --- Padding to 96 bytes (24 × 4) ---
    // swiftlint:disable:next identifier_name
    public var _pad0: Float
    // swiftlint:disable:next identifier_name
    public var _pad1: Float

    public init(
        bass: Float = 0, mid: Float = 0, treble: Float = 0,
        bassAtt: Float = 0, midAtt: Float = 0, trebleAtt: Float = 0,
        subBass: Float = 0, lowBass: Float = 0, lowMid: Float = 0,
        midHigh: Float = 0, highMid: Float = 0, high: Float = 0,
        beatBass: Float = 0, beatMid: Float = 0, beatTreble: Float = 0,
        beatComposite: Float = 0,
        spectralCentroid: Float = 0, spectralFlux: Float = 0,
        valence: Float = 0, arousal: Float = 0,
        time: Float = 0, deltaTime: Float = 0
    ) {
        self.bass = bass; self.mid = mid; self.treble = treble
        self.bassAtt = bassAtt; self.midAtt = midAtt; self.trebleAtt = trebleAtt
        self.subBass = subBass; self.lowBass = lowBass; self.lowMid = lowMid
        self.midHigh = midHigh; self.highMid = highMid; self.high = high
        self.beatBass = beatBass; self.beatMid = beatMid; self.beatTreble = beatTreble
        self.beatComposite = beatComposite
        self.spectralCentroid = spectralCentroid; self.spectralFlux = spectralFlux
        self.valence = valence; self.arousal = arousal
        self.time = time; self.deltaTime = deltaTime
        self._pad0 = 0; self._pad1 = 0
    }

    /// All-zero feature vector.
    public static let zero = FeatureVector()
}

// MARK: - MetadataSource

/// Where track metadata was obtained from.
public enum MetadataSource: String, Sendable, Equatable, Codable {
    /// From Apple Music via AppleScript.
    case appleMusic
    /// From Spotify via AppleScript.
    case spotify
    /// From MusicKit catalog search.
    case musicKit
    /// Generic Now Playing source.
    case nowPlaying
    /// Source unknown or unavailable.
    case unknown
}

// MARK: - TrackMetadata

/// Metadata for the currently playing track.
///
/// CPU-only — never uploaded to GPU buffers. All fields are optional
/// because metadata may be partially available or entirely absent.
/// Phosphene works at every tier of metadata availability.
public struct TrackMetadata: Sendable, Equatable, Codable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var genre: String?
    public var duration: Double?
    public var artworkURL: URL?
    public var source: MetadataSource

    /// Whether this metadata has enough info to query external APIs.
    public var isFetchable: Bool {
        title != nil && artist != nil
    }

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        duration: Double? = nil,
        artworkURL: URL? = nil,
        source: MetadataSource = .unknown
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.duration = duration
        self.artworkURL = artworkURL
        self.source = source
    }
}

// MARK: - PreFetchedTrackProfile

/// Rich metadata pre-fetched from external music databases.
///
/// Populated asynchronously from MusicBrainz, Spotify Web API, etc.
/// All fields are optional — partial results are expected and valid.
public struct PreFetchedTrackProfile: Sendable, Equatable, Codable {
    /// Beats per minute.
    public var bpm: Float?
    /// Musical key (e.g. "C major", "F# minor").
    public var key: String?
    /// Energy level (0–1).
    public var energy: Float?
    /// Emotional valence: 0 (sad/negative) to 1 (happy/positive).
    public var valence: Float?
    /// Danceability score (0–1).
    public var danceability: Float?
    /// Genre tags from external sources.
    public var genreTags: [String]
    /// Track duration in seconds (from external source, may differ from Now Playing).
    public var duration: Double?
    /// When this profile was fetched.
    public var fetchedAt: Date

    /// Whether any meaningful data was fetched.
    public var hasData: Bool {
        bpm != nil || key != nil || energy != nil ||
        valence != nil || danceability != nil ||
        !genreTags.isEmpty || duration != nil
    }

    public init(
        bpm: Float? = nil,
        key: String? = nil,
        energy: Float? = nil,
        valence: Float? = nil,
        danceability: Float? = nil,
        genreTags: [String] = [],
        duration: Double? = nil,
        fetchedAt: Date = Date()
    ) {
        self.bpm = bpm
        self.key = key
        self.energy = energy
        self.valence = valence
        self.danceability = danceability
        self.genreTags = genreTags
        self.duration = duration
        self.fetchedAt = fetchedAt
    }
}
