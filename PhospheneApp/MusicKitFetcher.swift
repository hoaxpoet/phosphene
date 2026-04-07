// MusicKitFetcher — Apple Music catalog lookup for BPM, genre, duration.
// Lives in the app target (not SPM package) because MusicKit requires
// framework linking that SPM doesn't support automatically.

import Foundation
import MusicKit
import Audio
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "MusicKit")

// MARK: - AppMusicKitFetcher

/// Searches the Apple Music catalog for track metadata.
/// Works regardless of which app is playing (Spotify, Apple Music, etc.)
/// since it queries the catalog by title + artist, not the user's library.
final class AppMusicKitFetcher: MetadataFetching, @unchecked Sendable {

    let sourceName = "MusicKit"

    func fetch(title: String, artist: String) async -> PartialTrackProfile? {
        guard MusicAuthorization.currentStatus == .authorized else {
            return nil
        }

        do {
            var request = MusicCatalogSearchRequest(
                term: "\(title) \(artist)",
                types: [Song.self]
            )
            request.limit = 5

            let response = try await request.response()

            // Find best match by title.
            let titleLower = title.lowercased()
            let song = response.songs.first { song in
                song.title.lowercased() == titleLower
                    || song.title.lowercased().contains(titleLower)
            } ?? response.songs.first

            guard let song else { return nil }

            var profile = PartialTrackProfile()

            // Genre tags.
            if !song.genreNames.isEmpty {
                profile.genreTags = song.genreNames
            }

            // Duration.
            if let duration = song.duration {
                profile.duration = duration
            }

            let genres = song.genreNames.joined(separator: ", ")
            let dur = song.duration.map { String(format: "%.0fs", $0) } ?? "nil"
            logger.info("MusicKit: \(song.title) — genres=[\(genres)] dur=\(dur)")

            return profile.genreTags.isEmpty && profile.duration == nil ? nil : profile
        } catch {
            logger.debug("MusicKit search failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Request MusicKit authorization. Call once at app startup.
    static func requestAuthorization() async {
        let status = MusicAuthorization.currentStatus
        if status == .notDetermined {
            let result = await MusicAuthorization.request()
            logger.info("MusicKit authorization: \(String(describing: result))")
        } else {
            logger.info("MusicKit status: \(String(describing: status))")
        }
    }
}
