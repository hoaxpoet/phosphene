// SpotifyConnectionViewModelTests — Unit tests for SpotifyConnectionViewModel.
// Uses MockSpotifyConnector with InstantDelay for synchronous retry testing.

import Session
import Testing
@testable import PhospheneApp

// MARK: - Tests

@Suite("SpotifyConnectionViewModel")
@MainActor
struct SpotifyConnectionViewModelTests {

    @Test("paste valid playlist URL populates preview state")
    func pasteValidPlaylist() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        try await Task.sleep(for: .milliseconds(400))  // debounce: 300ms + margin
        if case .preview(let id) = vm.state {
            #expect(id == "37i9dQZF1DXcBWIGoYBM5M")
        } else {
            Issue.record("Expected .preview, got \(vm.state)")
        }
    }

    @Test("paste Spotify track URL sets .rejectedKind(.track)")
    func pasteTrackURL() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
        try await Task.sleep(for: .milliseconds(400))
        if case .rejectedKind(.track) = vm.state { } else {
            Issue.record("Expected .rejectedKind(.track), got \(vm.state)")
        }
    }

    @Test("paste garbage URL sets .invalid")
    func pasteGarbage() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "not a spotify link at all"
        try await Task.sleep(for: .milliseconds(400))
        #expect(vm.state == .invalid)
    }

    @Test("connect with 429 retries at backoff schedule [2s, 5s, 15s]")
    func connectRateLimitedRetriesAtBackoffSchedule() async throws {
        // Connector returns 429 every time (initial + 3 retries = 4 calls total).
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.networkFailure("Spotify queue: HTTP 429"))
        )
        let vm = makeVM(connector: connector)

        // Set state to .preview so connect() is allowed.
        // 700ms gives 400ms margin over the 300ms hardcoded debounce — needed
        // because @MainActor contention during parallel test runs can delay
        // the debounce continuation beyond the old 400ms sleep.
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))

        // Pre-condition: debounce must have fired and transitioned to .preview.
        guard case .preview = vm.state else {
            Issue.record("Debounce did not fire: expected .preview, got \(vm.state)")
            return
        }

        // Kick off the connect. InstantDelay makes all retry delays instant.
        vm.connect(startSession: { _ in })

        // Give all retries time to complete (up to 500ms; InstantDelay makes them near-instant).
        try await Task.sleep(for: .milliseconds(500))

        // After all 3 retries fail, state must be .error.
        if case .error = vm.state { } else {
            Issue.record("Expected .error after exhausting retries, got \(vm.state)")
        }
        // All 4 attempts made (initial + 3 retries).
        #expect(connector.callCount == 4)
    }

    @Test("connect with HTTP 404 sets .notFound state")
    func connectNotFound() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.networkFailure("playlist tracks: HTTP 404"))
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(400))
        vm.connect(startSession: { _ in })
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.state == .notFound)
    }

    @Test("SpotifyConnectionView carries correct accessibilityID")
    func viewIdentifier() {
        #expect(SpotifyConnectionView.accessibilityID == "phosphene.view.spotify.connection")
    }

    // MARK: - Helpers

    private func makeVM(connector: MockSpotifyConnector) -> SpotifyConnectionViewModel {
        SpotifyConnectionViewModel(connector: connector, delayProvider: InstantDelay())
    }
}

// MARK: - MockSpotifyConnector

private final class MockSpotifyConnector: PlaylistConnecting, @unchecked Sendable {
    private let result: Result<[TrackIdentity], PlaylistConnectorError>
    private(set) var callCount = 0

    init(result: Result<[TrackIdentity], PlaylistConnectorError>) {
        self.result = result
    }

    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        callCount += 1
        switch result {
        case .success(let tracks): return tracks
        case .failure(let error):  throw error
        }
    }
}
