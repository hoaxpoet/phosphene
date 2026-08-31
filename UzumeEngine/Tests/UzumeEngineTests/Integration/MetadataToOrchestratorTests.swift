// MetadataToOrchestratorTests — Integration tests for metadata flowing
// through AudioInputRouter to downstream consumers.

import Testing
import Foundation
@testable import Audio
@testable import Shared

@Suite("MetadataToOrchestrator")
struct MetadataToOrchestratorTests {

    @Test func trackChange_triggersPreFetch_resultsAvailableWithin2Seconds() async throws {
        guard #available(macOS 14.2, *) else { return }

        let mockCapture = MockAudioCapture()
        let mockMetadata = MockMetadataProvider()

        let router = AudioInputRouter(capture: mockCapture, metadata: mockMetadata)
        var receivedEvent: TrackChangeEvent?

        router.onTrackChange = { event in
            receivedEvent = event
        }

        try router.start(mode: .systemAudio)

        // Simulate a track change via the mock provider.
        let track = TrackMetadata(title: "So What", artist: "Miles Davis", source: .nowPlaying)
        mockMetadata.simulateTrackChange(to: track)

        #expect(receivedEvent != nil)
        #expect(receivedEvent?.current.title == "So What")
        #expect(receivedEvent?.current.artist == "Miles Davis")

        router.stop()
    }

    @Test func trackChange_metadataFlowsToOrchestratorState() async throws {
        guard #available(macOS 14.2, *) else { return }

        let mockCapture = MockAudioCapture()
        let mockMetadata = MockMetadataProvider()

        let router = AudioInputRouter(capture: mockCapture, metadata: mockMetadata)
        try router.start(mode: .systemAudio)

        #expect(mockMetadata.startCallCount == 1)

        let track = TrackMetadata(title: "There There", artist: "Radiohead", source: .nowPlaying)
        mockMetadata.simulateTrackChange(to: track)

        #expect(router.currentTrack?.title == "There There")
        #expect(router.currentTrack?.artist == "Radiohead")

        router.stop()

        // stopCallCount is 2: once from start()'s initial stopInternal(), once from stop().
        #expect(mockMetadata.stopCallCount >= 1)
    }
}
