// PlaybackChromeArtworkBindingTests — verify that LF.6's
// `currentTrackArtworkDataPublisher` flows into
// `PlaybackChromeViewModel.currentTrack.albumArtData` via the
// `Publishers.CombineLatest` binding added in L3, and that track
// advances update title + artwork together.
//
// Why a separate suite (mirroring `PlaybackChromeIndexBindingTests`): the
// stock `PlaybackChromeViewModelTests` helper doesn't expose the artwork
// publisher; threading it through every existing test for a single
// binding behaviour would be noise.
//
// Tests stand on synthesised Data byte arrays — no audio fixtures needed.
// The LF persistent-cache + `LocalFilePrepResult` plumbing is already
// covered by `PersistentStemCacheTests` ("Roundtrip with artwork persists
// sibling bytes").

import Audio
import Combine
import Foundation
import Orchestrator
import Session
import Shared
import Testing

@testable import PhospheneApp

@Suite("PlaybackChromeArtworkBinding (LF.6)")
@MainActor
struct PlaybackChromeArtworkBindingTests {

    // MARK: - Fixtures

    private final class FakePublisher<Value> {
        private let subject: CurrentValueSubject<Value, Never>
        var publisher: AnyPublisher<Value, Never> { subject.eraseToAnyPublisher() }
        init(_ initial: Value) { subject = CurrentValueSubject(initial) }
        func send(_ value: Value) { subject.send(value) }
    }

    // swiftlint:disable large_tuple
    private func makeViewModel(
        initialTrack: TrackMetadata? = nil,
        initialArtwork: Data? = nil
    ) -> (PlaybackChromeViewModel, FakePublisher<TrackMetadata?>, FakePublisher<Data?>) {
        let trackPub = FakePublisher<TrackMetadata?>(initialTrack)
        let artworkPub = FakePublisher<Data?>(initialArtwork)
        let viewModel = PlaybackChromeViewModel(
            audioSignalStatePublisher: Just(.active).eraseToAnyPublisher(),
            currentTrackPublisher: trackPub.publisher,
            currentTrackArtworkDataPublisher: artworkPub.publisher,
            currentPresetNamePublisher: Just(nil).eraseToAnyPublisher(),
            livePlanPublisher: Just(nil).eraseToAnyPublisher(),
            delay: InstantDelay()
        )
        return (viewModel, trackPub, artworkPub)
    }
    // swiftlint:enable large_tuple

    private func metadata(title: String, artist: String) -> TrackMetadata {
        TrackMetadata(title: title, artist: artist, source: .unknown)
    }

    // MARK: - Tests

    @Test("Track + artwork emission populates TrackInfoDisplay.albumArtData")
    func artworkBytesReachDisplay() async throws {
        let (viewModel, trackPub, artworkPub) = makeViewModel()
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])             // JPEG SOI prefix
        trackPub.send(metadata(title: "Track A", artist: "Artist"))
        artworkPub.send(bytes)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack?.title == "Track A")
        #expect(viewModel.currentTrack?.albumArtData == bytes)
    }

    @Test("Nil artwork emission leaves albumArtData nil")
    func nilArtworkLeavesDisplayNil() async throws {
        let (viewModel, trackPub, _) = makeViewModel()
        trackPub.send(metadata(title: "Track A", artist: "Artist"))
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack?.albumArtData == nil)
    }

    @Test("Track advance updates title + artwork together")
    func trackAdvanceUpdatesBothFields() async throws {
        let (viewModel, trackPub, artworkPub) = makeViewModel()
        let bytesA = Data(repeating: 0xAA, count: 32)
        let bytesB = Data(repeating: 0xBB, count: 32)

        trackPub.send(metadata(title: "Track A", artist: "Artist"))
        artworkPub.send(bytesA)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack?.title == "Track A")
        #expect(viewModel.currentTrack?.albumArtData == bytesA)

        trackPub.send(metadata(title: "Track B", artist: "Artist"))
        artworkPub.send(bytesB)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack?.title == "Track B")
        #expect(viewModel.currentTrack?.albumArtData == bytesB)
    }

    @Test("Track advance to art-free track clears prior artwork")
    func advanceToArtFreeTrackClearsArtwork() async throws {
        let (viewModel, trackPub, artworkPub) = makeViewModel()
        let bytes = Data(repeating: 0xCC, count: 16)

        trackPub.send(metadata(title: "Track A", artist: "Artist"))
        artworkPub.send(bytes)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack?.albumArtData == bytes)

        trackPub.send(metadata(title: "Track B", artist: "Artist"))
        artworkPub.send(nil)                                    // art-free
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack?.title == "Track B")
        #expect(viewModel.currentTrack?.albumArtData == nil)
    }

    @Test("Nil track collapses TrackInfoDisplay even when artwork is non-nil")
    func nilTrackCollapsesDisplay() async throws {
        let (viewModel, trackPub, artworkPub) = makeViewModel()
        artworkPub.send(Data(repeating: 0xDD, count: 8))
        trackPub.send(nil)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.currentTrack == nil)
    }
}
