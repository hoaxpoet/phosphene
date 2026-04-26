// StreamingMetadataTests — Tests for Now Playing polling and track change detection.

import Testing
import Foundation
@testable import Audio
@testable import Shared

/// Thread-safe wrapper for mutable test state.
private final class AtomicValue<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) { _value = value }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

@Suite("StreamingMetadata")
struct StreamingMetadataTests {

    // MARK: - Helpers

    private func makeInfo(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: Double? = nil
    ) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: album, duration: duration)
    }

    // MARK: - Tests

    @Test func trackChange_differentTitle_emitsEvent() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)
        let info = makeInfo(title: "Bohemian Rhapsody", artist: "Queen")
        metadata.nowPlayingReader = { info }

        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(callCount.value == 1)
    }

    @Test func trackChange_sameTitle_noRedundantEvent() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)
        let info = makeInfo(title: "Hey Jude", artist: "The Beatles")
        metadata.nowPlayingReader = { info }

        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(300))
        metadata.stopObserving()

        #expect(callCount.value == 1)
    }

    @Test func trackChange_eventContainsTitleAndArtist() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let receivedEvent = AtomicValue<TrackChangeEvent?>(nil)
        let info = makeInfo(title: "Stairway to Heaven", artist: "Led Zeppelin", duration: 482)
        metadata.nowPlayingReader = { info }

        metadata.onTrackChange = { event in
            receivedEvent.value = event
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        let event = receivedEvent.value
        #expect(event != nil)
        #expect(event?.current.title == "Stairway to Heaven")
        #expect(event?.current.artist == "Led Zeppelin")
        #expect(event?.current.duration == 482)
        #expect(event?.previous == nil)
    }

    @Test func trackChange_secondTrack_hasPrevious() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let events = AtomicValue<[TrackChangeEvent]>([])

        let trackA = makeInfo(title: "Track A", artist: "Artist A")
        let trackB = makeInfo(title: "Track B", artist: "Artist B")
        let currentInfo = AtomicValue<NowPlayingInfo>(trackA)

        metadata.nowPlayingReader = { currentInfo.value }
        metadata.onTrackChange = { event in
            events.value.append(event)
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))

        currentInfo.value = trackB
        // 300ms gives 250ms margin over the 50ms poll interval — accounts for
        // scheduling jitter under parallel test execution.
        try await Task.sleep(for: .milliseconds(300))
        metadata.stopObserving()

        #expect(events.value.count == 2)
        #expect(events.value[1].previous?.title == "Track A")
        #expect(events.value[1].current.title == "Track B")
    }

    @Test func noNowPlaying_returnsNilMetadata() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)

        metadata.nowPlayingReader = { nil }
        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(200))
        metadata.stopObserving()

        #expect(metadata.currentTrack == nil)
        #expect(callCount.value == 0)
    }

    @Test func conformsToMetadataProviding() {
        let metadata = StreamingMetadata()
        let provider: any MetadataProviding = metadata
        #expect(provider.currentTrack == nil)
    }

    @Test func trackIdentity_caseInsensitive() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)

        let infoUpper = makeInfo(title: "SONG", artist: "ARTIST")
        let infoLower = makeInfo(title: "song", artist: "artist")
        let currentInfo = AtomicValue<NowPlayingInfo>(infoUpper)

        metadata.nowPlayingReader = { currentInfo.value }
        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))

        currentInfo.value = infoLower
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(callCount.value == 1)
    }
}
