// AppleMusicConnectionViewModelTests — Unit tests for AppleMusicConnectionViewModel.
// Uses MockAppleMusicConnector to avoid real AppleScript or network calls.
//
// Determinism note (hardening pass, 2026-06-01): these tests previously waited a
// fixed 300 ms / 1500 ms wall-clock margin for the async connect chain to settle,
// then asserted `vm.state`. Under the parallel app run, @MainActor contention
// could delay the chain past the margin → intermittent failures. The waits are
// now bounded-yield polls on `vm.state` (no wall-clock), so the flake class is
// eliminated. `connectNoCurrentPlaylist` keeps the default RealDelay so its 2 s
// auto-retry stays pending during the sub-millisecond poll (asserting the
// pre-retry state); every other test injects InstantDelay.

import Session
import Testing
@testable import PhospheneApp

// MARK: - Tests

@Suite("AppleMusicConnectionViewModel")
@MainActor
struct AppleMusicConnectionViewModelTests {

    /// Poll `vm.state` until `predicate` holds (bounded yields — no wall-clock).
    private func awaitState(
        _ vm: AppleMusicConnectionViewModel,
        until predicate: (AppleMusicConnectionState) -> Bool
    ) async {
        var yields = 0
        while !predicate(vm.state) && yields < 5000 { await Task.yield(); yields += 1 }
    }

    @Test("beginConnect transitions to .connecting then .noCurrentPlaylist when tracks empty")
    func connectNoCurrentPlaylist() async {
        let connector = MockAppleMusicConnector(result: .success([]))
        // Default RealDelay: the 2 s auto-retry stays pending while the poll (which
        // finishes in microseconds) observes the pre-retry .noCurrentPlaylist state.
        let vm = AppleMusicConnectionViewModel(connector: connector)
        vm.beginConnect()
        await awaitState(vm) { if case .noCurrentPlaylist = $0 { return true }; return false }
        if case .noCurrentPlaylist = vm.state { } else {
            Issue.record("Expected .noCurrentPlaylist, got \(vm.state)")
        }
    }

    @Test("noCurrentPlaylist schedules auto-retry; retry re-connects")
    func connectNoCurrentPlaylistSchedulesRetry() async {
        let connector = MockAppleMusicConnector(results: [
            .success([]),
            .success([makeFakeTrack()])
        ])
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        // First attempt empty → .noCurrentPlaylist → InstantDelay fires → retry →
        // .connected. Poll the full chain deterministically.
        await awaitState(vm) { if case .connected = $0 { return true }; return false }
        if case .connected(let count) = vm.state {
            #expect(count == 1)
        } else {
            #expect(Bool(false), "Expected .connected after retry, got \(vm.state)")
        }
    }

    @Test("connect throws appleMusicNotRunning → .notRunning, no retry")
    func connectNotRunning() async {
        let connector = MockAppleMusicConnector(
            result: .failure(PlaylistConnectorError.appleMusicNotRunning)
        )
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        await awaitState(vm) { $0 == .notRunning }
        #expect(vm.state == .notRunning)
        #expect(connector.callCount == 1)  // no retry after notRunning
    }

    @Test("connect throws parseFailure → .error state")
    func connectParseFailure() async {
        let connector = MockAppleMusicConnector(
            result: .failure(PlaylistConnectorError.parseFailure("bad output"))
        )
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        await awaitState(vm) { if case .error = $0 { return true }; return false }
        if case .error = vm.state { } else {
            Issue.record("Expected .error, got \(vm.state)")
        }
    }

    @Test("connect succeeds with tracks → .connected(trackCount:)")
    func connectSuccess() async {
        let tracks = [makeFakeTrack(), makeFakeTrack()]
        let connector = MockAppleMusicConnector(result: .success(tracks))
        var startSessionCalled = false
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        await awaitState(vm) { if case .connected = $0 { return true }; return false }
        if case .connected(let count) = vm.state {
            #expect(count == 2)
            startSessionCalled = true  // view would call onConnect here
        }
        #expect(startSessionCalled)
    }

    @Test("view identifiers are stable")
    func viewIdentifiers() {
        #expect(AppleMusicConnectionView.accessibilityID == "phosphene.view.appleMusic.connection")
    }
}

// MARK: - Helpers

private func makeFakeTrack() -> TrackIdentity {
    TrackIdentity(title: "Test Track", artist: "Test Artist")
}

// MARK: - MockAppleMusicConnector

private final class MockAppleMusicConnector: PlaylistConnecting, @unchecked Sendable {
    typealias ConnectResult = Result<[TrackIdentity], PlaylistConnectorError>

    private var results: [ConnectResult]
    private(set) var callCount = 0

    init(result: ConnectResult) {
        self.results = [result]
    }

    init(results: [ConnectResult]) {
        self.results = results
    }

    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        let idx = min(callCount, results.count - 1)
        callCount += 1
        switch results[idx] {
        case .success(let tracks): return tracks
        case .failure(let error):  throw error
        }
    }
}
