// ITunesSearchFetcher — Free, unauthenticated iTunes Search API for genre + duration.
// No developer account, no tokens, no MusicKit authorization needed.
// Works for any track in Apple's catalog regardless of streaming app.

import Foundation
import Audio
import Session
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "iTunes")

// MARK: - ITunesSearchFetcher

/// Searches the iTunes catalog for track metadata.
/// Free API, no authentication required.
final class ITunesSearchFetcher: MetadataFetching, @unchecked Sendable {

    let sourceName = "iTunes"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        self.session = URLSession(configuration: config)
    }

    func fetch(title: String, artist: String) async -> PartialTrackProfile? {
        // PUB.6 (ultra-review): acquire from the process-wide iTunes window.
        // This fetcher previously had NO throttle, so pre-fetch traffic
        // stacked on PreviewResolver's and could exceed the API's 20 req/min
        // (429s that the resolver treats as transient). One shared window
        // (ITunesRateLimiter.shared) now covers all itunes.apple.com callers.
        await ITunesRateLimiter.shared.acquire()

        let query = "\(title) \(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(query)&entity=song&limit=5"

        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)

            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  !results.isEmpty else {
                return nil
            }

            // Find best match by title.
            let titleLower = title.lowercased()
            let match = results.first { result in
                guard let name = result["trackName"] as? String else { return false }
                return name.lowercased() == titleLower
                    || name.lowercased().contains(titleLower)
            } ?? results.first

            guard let song = match else { return nil }

            var profile = PartialTrackProfile()

            if let genre = song["primaryGenreName"] as? String {
                profile.genreTags = [genre]
            }
            if let millis = song["trackTimeMillis"] as? Int {
                profile.duration = Double(millis) / 1000.0
            }

            let trackName = song["trackName"] as? String ?? "?"
            let genre = profile.genreTags.first ?? "nil"
            let dur = profile.duration.map { String(format: "%.0fs", $0) } ?? "nil"
            logger.info("iTunes: \(trackName) genre=\(genre) dur=\(dur)")

            return profile.genreTags.isEmpty && profile.duration == nil
                ? nil : profile
        } catch {
            logger.debug("iTunes search failed: \(error.localizedDescription)")
            return nil
        }
    }
}
