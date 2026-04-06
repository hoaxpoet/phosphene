// MusicKitBridge — Optional MusicKit integration for metadata enrichment.
// Gracefully no-ops if MusicKit is unavailable or unauthorized.
// Uses #if canImport(MusicKit) to compile cleanly without the entitlement.

import Foundation
import Shared
import os.log

#if canImport(MusicKit)
import MusicKit
#endif

private let logger = Logging.metadata

// MARK: - MusicKitBridge

/// Optional MusicKit integration for enriching track metadata.
///
/// Queries the Apple Music catalog to fill in artwork URLs, genre,
/// and duration when available. Returns input metadata unchanged
/// on any failure — MusicKit is never a hard dependency.
public enum MusicKitBridge {

    /// Request MusicKit authorization if not yet determined.
    /// No-op if already authorized or denied, or if MusicKit is unavailable.
    public static func requestAuthorizationIfNeeded() async {
        #if canImport(MusicKit)
        let status = MusicAuthorization.currentStatus
        if status == .notDetermined {
            let result = await MusicAuthorization.request()
            logger.info("MusicKit authorization result: \(String(describing: result))")
        }
        #else
        logger.debug("MusicKit not available on this build")
        #endif
    }

    /// Enrich track metadata with MusicKit catalog data.
    ///
    /// Searches by title + artist. Returns the original metadata unchanged
    /// if MusicKit is unauthorized, the search fails, or it times out (3s).
    public static func enrich(_ metadata: TrackMetadata) async -> TrackMetadata {
        #if canImport(MusicKit)
        guard MusicAuthorization.currentStatus == .authorized else {
            logger.debug("MusicKit not authorized, returning original metadata")
            return metadata
        }

        guard let title = metadata.title else { return metadata }

        let searchTerm: String
        if let artist = metadata.artist {
            searchTerm = "\(title) \(artist)"
        } else {
            searchTerm = title
        }

        // Race the search against a 3-second timeout.
        let term = searchTerm
        return await withTaskGroup(of: TrackMetadata.self) { group in
            group.addTask {
                do {
                    var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                    request.limit = 1

                    let response = try await request.response()
                    guard let song = response.songs.first else { return metadata }

                    var enriched = metadata
                    enriched.source = .musicKit

                    if enriched.album == nil {
                        enriched.album = song.albumTitle
                    }
                    if enriched.genre == nil, let genre = song.genreNames.first {
                        enriched.genre = genre
                    }
                    if enriched.duration == nil {
                        enriched.duration = song.duration
                    }
                    if enriched.artworkURL == nil {
                        enriched.artworkURL = song.artwork?.url(width: 300, height: 300)
                    }

                    logger.debug("MusicKit enriched: \(title)")
                    return enriched
                } catch {
                    logger.debug("MusicKit search failed: \(error.localizedDescription)")
                    return metadata
                }
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return metadata
            }

            let result = await group.next() ?? metadata
            group.cancelAll()
            return result
        }
        #else
        return metadata
        #endif
    }
}
