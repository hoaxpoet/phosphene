// SpotifyConnectionViewModelTests — Unit tests for SpotifyConnectionViewModel.
// Uses MockSpotifyConnector with InstantDelay for synchronous retry testing.
// Increment U.10: silent-degrade tests removed; new error-state tests added.

import Foundation
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
        try await Task.sleep(for: .milliseconds(700))  // debounce: 300ms + 400ms margin
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
        try await Task.sleep(for: .milliseconds(700))
        if case .rejectedKind(.track) = vm.state { } else {
            Issue.record("Expected .rejectedKind(.track), got \(vm.state)")
        }
    }

    @Test("paste garbage URL sets .invalid")
    func pasteGarbage() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "not a spotify link at all"
        try await Task.sleep(for: .milliseconds(700))
        #expect(vm.state == .invalid)
    }

    @Test("connect with 429 retries at backoff schedule [2s, 5s, 15s]")
    func connectRateLimitedRetriesAtBackoffSchedule() async throws {
        // Connector returns 429 every time (initial + 3 retries = 4 calls total).
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.rateLimited(retryAfterSeconds: 1.0))
        )
        let vm = makeVM(connector: connector)

        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))

        guard case .preview = vm.state else {
            Issue.record("Debounce did not fire: expected .preview, got \(vm.state)")
            return
        }

        vm.connect(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(500))

        if case .error = vm.state { } else {
            Issue.record("Expected .error after exhausting retries, got \(vm.state)")
        }
        #expect(connector.callCount == 4)
    }

    @Test("connect with spotifyPlaylistNotFound sets .notFound state")
    func connectNotFound() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.spotifyPlaylistNotFound)
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.connect(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(250))
        #expect(vm.state == .notFound)
    }

    @Test("connect with spotifyPlaylistInaccessible sets .privatePlaylist state")
    func connectPrivatePlaylist() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.spotifyPlaylistInaccessible)
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.connect(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(250))
        #expect(vm.state == .privatePlaylist)
    }

    @Test("connect with spotifyAuthFailure sets .authFailure state")
    func connectAuthFailure() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.spotifyAuthFailure("bad creds"))
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.connect(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(250))
        #expect(vm.state == .authFailure)
    }

    @Test("successful connect calls startSession with .spotifyPlaylistURL source")
    func successfulConnectCallsStartSession() async throws {
        let connector = MockSpotifyConnector(result: .success([]))
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        try await Task.sleep(for: .milliseconds(700))

        // nonisolated(unsafe): written only once in this @Sendable closure, read after Task.sleep.
        nonisolated(unsafe) var capturedSource: PlaylistSource?
        vm.connect(startSession: { _, source in capturedSource = source })
        try await Task.sleep(for: .milliseconds(200))

        if case .spotifyPlaylistURL = capturedSource {
            // Expected — no accessToken associated value.
        } else {
            Issue.record("Expected .spotifyPlaylistURL, got \(String(describing: capturedSource))")
        }
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

// MARK: - SpotifyConnectionViewModel — OAuth state tests

@Suite("SpotifyConnectionViewModel — OAuth states")
@MainActor
struct SpotifyConnectionViewModelOAuthTests {

    @Test("connect with spotifyLoginRequired and unauthenticated provider sets .requiresLogin")
    func connectLoginRequiredUnauthenticated() async throws {
        let connector = MockOAuthConnector(
            result: .failure(PlaylistConnectorError.spotifyLoginRequired)
        )
        let vm = SpotifyConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay(),
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: false)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.connect(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(400))
        #expect(vm.state == .requiresLogin)
    }

    @Test("connect with spotifyLoginRequired and authenticated provider sets .privatePlaylist")
    func connectLoginRequiredAuthenticated() async throws {
        let connector = MockOAuthConnector(
            result: .failure(PlaylistConnectorError.spotifyLoginRequired)
        )
        let vm = SpotifyConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay(),
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: true)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.connect(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(400))
        #expect(vm.state == .privatePlaylist)
    }

    @Test("login action success retries connect and calls startSession")
    func loginActionSuccess() async throws {
        nonisolated(unsafe) var sessionStarted = false
        let vm = SpotifyConnectionViewModel(
            connector: MockOAuthConnector(result: .success([])),
            delayProvider: InstantDelay(),
            loginAction: { },
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: true)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.login(startSession: { _, _ in sessionStarted = true })
        try await Task.sleep(for: .milliseconds(400))
        #expect(sessionStarted)
    }

    @Test("login action failure sets .authFailure")
    func loginActionFailure() async throws {
        let vm = SpotifyConnectionViewModel(
            connector: MockOAuthConnector(result: .success([])),
            delayProvider: InstantDelay(),
            loginAction: { throw PlaylistConnectorError.spotifyAuthFailure("denied") },
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: false)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        try await Task.sleep(for: .milliseconds(700))
        vm.login(startSession: { _, _ in })
        try await Task.sleep(for: .milliseconds(400))
        #expect(vm.state == .authFailure)
    }
}

// MARK: - OAuth Mocks

private final class MockOAuthConnector: PlaylistConnecting, @unchecked Sendable {
    private let result: Result<[TrackIdentity], PlaylistConnectorError>

    init(result: Result<[TrackIdentity], PlaylistConnectorError>) {
        self.result = result
    }

    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        switch result {
        case .success(let tracks): return tracks
        case .failure(let error):  throw error
        }
    }
}

private actor MockOAuthLoginProvider: SpotifyOAuthLoginProviding {
    private let _isAuthenticated: Bool
    init(isAuthenticated: Bool) { self._isAuthenticated = isAuthenticated }
    var isAuthenticated: Bool { _isAuthenticated }
    func login() async throws {}
    func handleCallback(url: URL) async {}
    func logout() async {}
}
