// AppleMusicConnectionViewModelTests — Unit tests for AppleMusicConnectionViewModel.
// Uses MockAppleMusicConnector to avoid real AppleScript or network calls.

import Session
import Testing
@testable import PhospheneApp

// MARK: - Tests

@Suite("AppleMusicConnectionViewModel")
@MainActor
struct AppleMusicConnectionViewModelTests {

    @Test("beginConnect transitions to .connecting then .noCurrentPlaylist when tracks empty")
    func connectNoCurrentPlaylist() async throws {
        let connector = MockAppleMusicConnector(result: .success([]))
        // Use default RealDelay: auto-retry fires after 2 s, so at 50 ms the
        // state is still .noCurrentPlaylist rather than cycling back to .connecting.
        let vm = AppleMusicConnectionViewModel(connector: connector)
        vm.beginConnect()
        try await Task.sleep(for: .milliseconds(50))
        if case .noCurrentPlaylist = vm.state { } else {
            Issue.record("Expected .noCurrentPlaylist, got \(vm.state)")
        }
    }

    @Test("noCurrentPlaylist schedules auto-retry; retry re-connects")
    func connectNoCurrentPlaylistSchedulesRetry() async throws {
        let connector = MockAppleMusicConnector(results: [
            .success([]),
            .success([makeFakeTrack()])
        ])
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        // First attempt: empty → .noCurrentPlaylist → InstantDelay fires immediately.
        // 500ms gives the full async chain (connect → noCurrentPlaylist → yield →
        // retry → connect → connected) ample time regardless of executor scheduling.
        try await Task.sleep(for: .milliseconds(500))
        // Second attempt should have succeeded.
        if case .connected(let count) = vm.state {
            #expect(count == 1)
        } else {
            #expect(Bool(false), "Expected .connected after retry, got \(vm.state)")
        }
    }

    @Test("connect throws appleMusicNotRunning → .notRunning, no retry")
    func connectNotRunning() async throws {
        let connector = MockAppleMusicConnector(
            result: .failure(PlaylistConnectorError.appleMusicNotRunning)
        )
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.state == .notRunning)
        #expect(connector.callCount == 1)  // no retry after notRunning
    }

    @Test("connect throws parseFailure → .error state")
    func connectParseFailure() async throws {
        let connector = MockAppleMusicConnector(
            result: .failure(PlaylistConnectorError.parseFailure("bad output"))
        )
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        try await Task.sleep(for: .milliseconds(50))
        if case .error = vm.state { } else {
            Issue.record("Expected .error, got \(vm.state)")
        }
    }

    @Test("connect succeeds with tracks → .connected(trackCount:)")
    func connectSuccess() async throws {
        let tracks = [makeFakeTrack(), makeFakeTrack()]
        let connector = MockAppleMusicConnector(result: .success(tracks))
        var startSessionCalled = false
        let vm = AppleMusicConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay()
        )
        vm.beginConnect()
        try await Task.sleep(for: .milliseconds(50))
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
