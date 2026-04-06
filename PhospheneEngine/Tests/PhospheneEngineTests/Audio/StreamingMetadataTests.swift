// StreamingMetadataTests — Tests for Now Playing polling and track change detection.

import Testing
import Foundation
import MediaPlayer
@testable import Audio
@testable import Shared

@Suite("StreamingMetadata")
struct StreamingMetadataTests {

    // MARK: - Helpers

    /// Create a Now Playing dictionary matching MPNowPlayingInfoCenter format.
    private func nowPlayingDict(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        duration: Double? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [:]
        if let title { dict[MPMediaItemPropertyTitle] = title }
        if let artist { dict[MPMediaItemPropertyArtist] = artist }
        if let album { dict[MPMediaItemPropertyAlbumTitle] = album }
        if let genre { dict[MPMediaItemPropertyGenre] = genre }
        if let duration { dict[MPMediaItemPropertyPlaybackDuration] = duration }
        return dict
    }

    // MARK: - Tests

    @Test func trackChange_differentTitle_emitsEvent() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        var callCount = 0
        let dict = nowPlayingDict(title: "Bohemian Rhapsody", artist: "Queen")
        metadata.nowPlayingReader = { dict }

        metadata.onTrackChange = { _ in
            callCount += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(callCount == 1)
    }

    @Test func trackChange_sameTitle_noRedundantEvent() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        var callCount = 0
        let dict = nowPlayingDict(title: "Hey Jude", artist: "The Beatles")
        metadata.nowPlayingReader = { dict }

        metadata.onTrackChange = { _ in
            callCount += 1
        }

        metadata.startObserving()
        // Wait long enough for multiple poll cycles.
        try await Task.sleep(for: .milliseconds(300))
        metadata.stopObserving()

        // Should fire exactly once on first detection, not on subsequent polls.
        #expect(callCount == 1)
    }

    @Test func trackChange_eventContainsTitleAndArtist() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        var receivedEvent: TrackChangeEvent?
        let dict = nowPlayingDict(title: "Stairway to Heaven", artist: "Led Zeppelin", duration: 482)
        metadata.nowPlayingReader = { dict }

        metadata.onTrackChange = { event in
            receivedEvent = event
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(receivedEvent != nil)
        #expect(receivedEvent?.current.title == "Stairway to Heaven")
        #expect(receivedEvent?.current.artist == "Led Zeppelin")
        #expect(receivedEvent?.current.duration == 482)
        #expect(receivedEvent?.previous == nil)
    }

    @Test func trackChange_secondTrack_hasPrevious() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        var events: [TrackChangeEvent] = []

        let trackA = nowPlayingDict(title: "Track A", artist: "Artist A")
        let trackB = nowPlayingDict(title: "Track B", artist: "Artist B")
        var currentDict: [String: Any] = trackA

        metadata.nowPlayingReader = { currentDict }
        metadata.onTrackChange = { event in
            events.append(event)
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))

        // Switch to track B.
        currentDict = trackB
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(events.count == 2)
        #expect(events[1].previous?.title == "Track A")
        #expect(events[1].current.title == "Track B")
    }

    @Test func noNowPlaying_returnsNilMetadata() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        var callCount = 0

        metadata.nowPlayingReader = { nil }
        metadata.onTrackChange = { _ in
            callCount += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(200))
        metadata.stopObserving()

        #expect(metadata.currentTrack == nil)
        #expect(callCount == 0)
    }

    @Test func conformsToMetadataProviding() {
        let metadata = StreamingMetadata()
        let provider: any MetadataProviding = metadata
        #expect(provider.currentTrack == nil)
    }

    @Test func trackIdentity_caseInsensitive() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        var callCount = 0

        let dictUpper = nowPlayingDict(title: "SONG", artist: "ARTIST")
        let dictLower = nowPlayingDict(title: "song", artist: "artist")
        var currentDict: [String: Any] = dictUpper

        metadata.nowPlayingReader = { currentDict }
        metadata.onTrackChange = { _ in
            callCount += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))

        // Switch to same track with different case — should NOT fire.
        currentDict = dictLower
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(callCount == 1)
    }
}
