// PlaybackHealthToastTests — ASH.2 one-per-session band=low nudge.
//
// Dead-tap is deliberately NOT toasted here — the AudioStallOverlayView card
// covers it earlier and more prominently (Matt's call, ASH.2). This suite locks
// down only the low-level toast: it fires once, never repeats, ignores healthy
// bands, and picks the Spotify vs generic remediation copy.

import Audio
import Combine
import Foundation
import Testing
@testable import PhospheneApp

@Suite("PlaybackErrorBridge — signal-health toast")
@MainActor
struct PlaybackHealthToastTests {

    private struct Fixture {
        let health: PassthroughSubject<SignalHealth, Never>
        let toastManager: ToastManager
        let bridge: PlaybackErrorBridge   // held so the [weak self] subscription lives
    }

    private func makeSUT(spotify: Bool? = nil) -> Fixture {
        let health = PassthroughSubject<SignalHealth, Never>()
        let tm = ToastManager()
        let provider: (@MainActor () -> Bool)?
        if let spotify { provider = { spotify } } else { provider = nil }
        let bridge = PlaybackErrorBridge(
            audioSignalStatePublisher: Empty().eraseToAnyPublisher(),
            toastManager: tm,
            signalHealthPublisher: health.eraseToAnyPublisher(),
            isSpotifySourceProvider: provider
        )
        return Fixture(health: health, toastManager: tm, bridge: bridge)
    }

    private func low() -> SignalHealth { SignalHealth(peakBand: .low, peakDBFS: -13) }

    @Test("band=low fires exactly one warning toast tagged audio.levels.low")
    func test_bandLow_firesOneToast() async {
        let fix = makeSUT()
        fix.health.send(low())
        await Task.yield(); await Task.yield()
        #expect(fix.toastManager.visibleToasts.count == 1)
        #expect(fix.toastManager.visibleToasts.first?.severity == .warning)
        #expect(fix.toastManager.visibleToasts.first?.conditionID == "audio.levels.low")
    }

    @Test("a second band=low does not re-toast (one per session per cause)")
    func test_bandLow_twice_onlyOne() async {
        let fix = makeSUT()
        fix.health.send(low())
        await Task.yield(); await Task.yield()
        // Dismiss it, then re-degrade — the latch must still suppress a re-toast.
        if let id = fix.toastManager.visibleToasts.first?.id { fix.toastManager.dismiss(id: id) }
        fix.health.send(low())
        await Task.yield(); await Task.yield()
        #expect(fix.toastManager.visibleToasts.isEmpty)
    }

    @Test("healthy / unknown bands never toast")
    func test_healthy_noToast() async {
        let fix = makeSUT()
        fix.health.send(SignalHealth(peakBand: .healthy, peakDBFS: -6))
        fix.health.send(SignalHealth(peakBand: .unknown))
        await Task.yield(); await Task.yield()
        #expect(fix.toastManager.visibleToasts.isEmpty)
    }

    @Test("Spotify source picks the Normalize-Volume copy; otherwise generic")
    func test_spotifyCopy() async {
        let spotify = makeSUT(spotify: true)
        spotify.health.send(low()); await Task.yield(); await Task.yield()
        #expect(spotify.toastManager.visibleToasts.first?.copy
            == LocalizedCopy.string(for: .audioLevelsLow(isSpotifySource: true)))

        let generic = makeSUT(spotify: false)
        generic.health.send(low()); await Task.yield(); await Task.yield()
        #expect(generic.toastManager.visibleToasts.first?.copy
            == LocalizedCopy.string(for: .audioLevelsLow(isSpotifySource: false)))
    }
}
