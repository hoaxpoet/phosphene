// NowPlayingSurfaceTests — R3.1 (PUB.9): the chrome child's paired-publish +
// single-clear contract (the structural BUG-024 fix for these fields).

import Foundation
import Session
import Shared
import Testing
@testable import PhospheneApp

@Suite("NowPlayingSurface")
@MainActor
struct NowPlayingSurfaceTests {

    private func makeTrack(_ title: String) -> TrackMetadata {
        TrackMetadata(title: title, artist: "A", album: nil, duration: 100, source: .unknown)
    }

    @Test("publishTrack pairs title + index; artwork untouched unless passed")
    func test_publishTrack_pairs() {
        let surface = NowPlayingSurface()
        surface.setArtwork(Data([1, 2, 3]))

        surface.publishTrack(makeTrack("T1"), index: 4)
        #expect(surface.currentTrack?.title == "T1")
        #expect(surface.currentTrackIndex == 4)
        #expect(surface.currentTrackArtworkData == Data([1, 2, 3]),
                "omitted artwork parameter must not clobber existing bytes")

        // The streaming track-change shape: artwork explicitly cleared in the
        // same publish so the previous track's bytes never dress the new title.
        surface.publishTrack(makeTrack("T2"), index: nil, artwork: .some(nil))
        #expect(surface.currentTrack?.title == "T2")
        #expect(surface.currentTrackIndex == nil)
        #expect(surface.currentTrackArtworkData == nil)
    }

    @Test("clear drops every surface in one call")
    func test_clear_dropsAll() {
        let surface = NowPlayingSurface()
        surface.publishTrack(makeTrack("T"), index: 1, artwork: .some(Data([9])))
        surface.setProfile(PreFetchedTrackProfile())

        surface.clear()
        #expect(surface.currentTrack == nil)
        #expect(surface.currentTrackIndex == nil)
        #expect(surface.currentTrackArtworkData == nil)
        #expect(surface.preFetchedProfile == nil)
    }
}
