// MockMetadataProvider — Test doubles for metadata protocols.
// MockMetadataProvider: emits canned TrackChangeEvents on demand.
// MockMetadataFetcher: returns configurable PartialTrackProfile results.

import Foundation
@testable import Audio
@testable import Shared

// MARK: - MockMetadataProvider

final class MockMetadataProvider: MetadataProviding, @unchecked Sendable {

    // MARK: - Call Tracking

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var trackChangeCount = 0

    // MARK: - MetadataProviding

    var onTrackChange: ((_ event: TrackChangeEvent) -> Void)?

    private(set) var currentTrack: TrackMetadata?

    func startObserving() {
        startCallCount += 1
    }

    func stopObserving() {
        stopCallCount += 1
        currentTrack = nil
    }

    // MARK: - Test Helpers

    /// Simulate a track change event. Updates `currentTrack` and fires `onTrackChange`.
    func simulateTrackChange(to track: TrackMetadata) {
        let previous = currentTrack
        currentTrack = track
        trackChangeCount += 1
        let event = TrackChangeEvent(previous: previous, current: track)
        onTrackChange?(event)
    }
}

// MARK: - MockMetadataFetcher

final class MockMetadataFetcher: MetadataFetching, @unchecked Sendable {

    // MARK: - Configuration

    /// The result to return from `fetch`. Nil simulates a failed/empty response.
    var stubbedResult: PartialTrackProfile?

    /// Optional delay before returning the result (for timeout testing).
    var fetchDelay: Duration?

    let sourceName: String

    // MARK: - Call Tracking

    private(set) var fetchCallCount = 0
    private(set) var lastQueriedTitle: String?
    private(set) var lastQueriedArtist: String?

    // MARK: - Init

    init(sourceName: String = "MockSource", stubbedResult: PartialTrackProfile? = nil, fetchDelay: Duration? = nil) {
        self.sourceName = sourceName
        self.stubbedResult = stubbedResult
        self.fetchDelay = fetchDelay
    }

    // MARK: - MetadataFetching

    func fetch(title: String, artist: String) async -> PartialTrackProfile? {
        fetchCallCount += 1
        lastQueriedTitle = title
        lastQueriedArtist = artist

        if let delay = fetchDelay {
            try? await Task.sleep(for: delay)
        }

        return stubbedResult
    }
}
