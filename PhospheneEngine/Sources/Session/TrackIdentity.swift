// TrackIdentity — Stable identity for a track in a playlist.
// Used as a cache key throughout the session preparation pipeline.

import Foundation

// MARK: - TrackIdentity

/// A stable, deduplication-safe identity for a single playlist track.
///
/// Used as the cache key in `StemCache` and throughout the session
/// preparation pipeline. Title and artist are required; all catalog IDs
/// are optional and are populated as they become available from external APIs.
public struct TrackIdentity: Sendable, Equatable, Hashable, Codable {

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
    public init(
        title: String,
        artist: String,
        album: String? = nil,
        duration: Double? = nil,
        appleMusicID: String? = nil,
        spotifyID: String? = nil,
        musicBrainzID: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.appleMusicID = appleMusicID
        self.spotifyID = spotifyID
        self.musicBrainzID = musicBrainzID
    }
}
