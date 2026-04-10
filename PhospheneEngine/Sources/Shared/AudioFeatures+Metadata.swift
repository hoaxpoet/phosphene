// AudioFeatures+Metadata — Track metadata and pre-fetched profile types.
// CPU-only structs for Now Playing information and external API results.
// Never uploaded to GPU buffers.

import Foundation

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
