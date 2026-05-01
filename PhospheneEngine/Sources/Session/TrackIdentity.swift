// TrackIdentity — Stable identity for a track in a playlist.
// Used as a cache key throughout the session preparation pipeline.
//
// Equality and hashing are based on the seven identity fields only.
// `spotifyPreviewURL` is a resolution hint that does NOT participate in
// equality or hashing — it is transparent to the cache key contract.

import Foundation

// MARK: - TrackIdentity

/// A stable, deduplication-safe identity for a single playlist track.
///
/// Used as the cache key in `StemCache` and throughout the session
/// preparation pipeline. Title and artist are required; all catalog IDs
/// are optional and are populated as they become available from external APIs.
///
/// `spotifyPreviewURL` is an optional hint field that carries the 30-second
/// preview URL provided directly by the Spotify Web API. When present,
/// `PreviewResolver` uses it without making an iTunes Search API request.
/// This field is excluded from `Equatable` and `Hashable` so it does not
/// affect the cache key contract.
public struct TrackIdentity: Sendable, Codable {

    // MARK: - Required Fields

    /// Track title.
    public let title: String

    /// Primary artist name.
    public let artist: String

    // MARK: - Optional Fields

    /// Album name (may be absent for singles or when metadata is incomplete).
    public let album: String?

    /// Track duration in seconds.
    public let duration: Double?

    // MARK: - Catalog IDs

    /// Apple Music persistent track ID (from AppleScript `persistent ID`).
    public let appleMusicID: String?

    /// Spotify track ID.
    public let spotifyID: String?

    /// MusicBrainz recording ID.
    public let musicBrainzID: String?

    // MARK: - Resolution Hints (excluded from identity)

    /// Spotify-provided 30-second preview URL, or `nil` if Spotify has none.
    ///
    /// Populated by `SpotifyWebAPIConnector` from the `preview_url` field in
    /// the `/items` response. `PreviewResolver` uses this to bypass the iTunes
    /// Search API for Spotify tracks. Not part of the cache key.
    public let spotifyPreviewURL: URL?

    // MARK: - Codable

    /// Excludes `spotifyPreviewURL` from the serialized form — it is a resolution
    /// hint, not a stable identity field, and need not survive encoding round-trips.
    private enum CodingKeys: String, CodingKey {
        case title, artist, album, duration, appleMusicID, spotifyID, musicBrainzID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        appleMusicID = try container.decodeIfPresent(String.self, forKey: .appleMusicID)
        spotifyID = try container.decodeIfPresent(String.self, forKey: .spotifyID)
        musicBrainzID = try container.decodeIfPresent(String.self, forKey: .musicBrainzID)
        spotifyPreviewURL = nil  // hint is never persisted
    }

    // MARK: - Init

    /// Create a track identity.
    ///
    /// - Parameters:
    ///   - title: Track title (required).
    ///   - artist: Primary artist name (required).
    ///   - album: Album name (optional).
    ///   - duration: Duration in seconds (optional).
    ///   - appleMusicID: Apple Music persistent track ID (optional).
    ///   - spotifyID: Spotify track ID (optional).
    ///   - musicBrainzID: MusicBrainz recording ID (optional).
    ///   - spotifyPreviewURL: Spotify-provided preview URL hint (optional, not part of identity).
    public init(
        title: String,
        artist: String,
        album: String? = nil,
        duration: Double? = nil,
        appleMusicID: String? = nil,
        spotifyID: String? = nil,
        musicBrainzID: String? = nil,
        spotifyPreviewURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.appleMusicID = appleMusicID
        self.spotifyID = spotifyID
        self.musicBrainzID = musicBrainzID
        self.spotifyPreviewURL = spotifyPreviewURL
    }
}

// MARK: - Equatable

/// Identity-only equality: `spotifyPreviewURL` is excluded.
extension TrackIdentity: Equatable {
    public static func == (lhs: TrackIdentity, rhs: TrackIdentity) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.duration == rhs.duration &&
        lhs.appleMusicID == rhs.appleMusicID &&
        lhs.spotifyID == rhs.spotifyID &&
        lhs.musicBrainzID == rhs.musicBrainzID
    }
}

// MARK: - Hashable

/// Identity-only hash: `spotifyPreviewURL` is excluded.
extension TrackIdentity: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(artist)
        hasher.combine(album)
        hasher.combine(duration)
        hasher.combine(appleMusicID)
        hasher.combine(spotifyID)
        hasher.combine(musicBrainzID)
    }
}
