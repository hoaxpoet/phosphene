// SpotifyConnectionViewModel — State machine for the Spotify URL-paste connection flow.
//
// Increment U.10: client-credentials auth via SpotifyTokenProvider.
// Increment U.11: OAuth Authorization Code + PKCE replaces client-credentials.
//
// New states added in U.11:
//   .requiresLogin       → user has not authenticated with Spotify yet; shows login CTA
//   .waitingForCallback  → browser open, waiting for phosphene://spotify-callback redirect
//
// Error mapping when authenticated:
//   .spotifyLoginRequired with oauthProvider.isAuthenticated == true
//       → mapped to .privatePlaylist (the playlist is genuinely private / inaccessible)
//   .spotifyLoginRequired with oauthProvider.isAuthenticated == false
//       → mapped to .requiresLogin (the user needs to log in first)
//
// loginAction is injected from ConnectorPickerView so the VM stays free of
// AppKit/NSWorkspace dependencies. In tests it can be replaced with a stub.

import Combine
import Session

// MARK: - SpotifyConnectionState

enum SpotifyConnectionState: Equatable {
    /// No URL entered yet.
    case empty
    /// Debounce in-flight; URL not yet parsed.
    case parsing
    /// URL parsed as a valid Spotify playlist. `playlistID` is the extracted ID.
    case preview(playlistID: String)
    /// Input is a Spotify URL but for a non-playlist kind (track, album, artist).
    case rejectedKind(SpotifyURLKind)
    /// Input is not a Spotify URL.
    case invalid
    /// HTTP 429 received; `attempt` is 1-indexed (1 of 3).
    case rateLimited(attempt: Int)
    /// HTTP 404 — playlist not found (deleted or wrong link).
    case notFound
    /// HTTP 403 while authenticated — playlist is private or otherwise inaccessible.
    case privatePlaylist
    /// User needs to authenticate with Spotify (OAuth). Shows "Log in with Spotify" CTA.
    case requiresLogin
    /// OAuth browser is open; waiting for the phosphene://spotify-callback redirect.
    case waitingForCallback
    /// Auth failure — credentials missing, rejected, or OAuth flow failed.
    case authFailure
    /// Unrecoverable error. Message is user-facing.
    case error(String)
}

// MARK: - SpotifyConnectionViewModel

@MainActor
final class SpotifyConnectionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var text: String = ""
    @Published private(set) var state: SpotifyConnectionState = .empty
    @Published private(set) var isConnecting: Bool = false

    // MARK: - Dependencies

    private let connector: any PlaylistConnecting
    private let delayProvider: any DelayProviding
    /// Called when state reaches `.requiresLogin` and the user taps "Log in with Spotify".
    /// Injected from ConnectorPickerView so the VM has no AppKit dependency.
    /// Returns when a valid access token has been obtained (or throws on failure/timeout).
    private let loginAction: (@Sendable () async throws -> Void)?
    /// Read to distinguish "need to log in" (unauthenticated 403) from
    /// "playlist is private" (authenticated 403).
    private let oauthProvider: (any SpotifyOAuthLoginProviding)?

    // MARK: - Private

    private var parsedPlaylistID: String = ""
    private var parsedURL: String = ""
    private var debounceTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(
        connector: any PlaylistConnecting = PlaylistConnector(),
        delayProvider: any DelayProviding = RealDelay(),
        loginAction: (@Sendable () async throws -> Void)? = nil,
        oauthProvider: (any SpotifyOAuthLoginProviding)? = nil
    ) {
        self.connector = connector
        self.delayProvider = delayProvider
        self.loginAction = loginAction
        self.oauthProvider = oauthProvider
        observeTextChanges()
    }

    // MARK: - Actions

    /// Called when the user taps Continue. Only valid when state == .preview.
    func connect(startSession: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void) {
        guard case .preview(let id) = state, !id.isEmpty else { return }
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.runConnect(playlistID: id, startSession: startSession)
        }
    }

    /// Called when the user taps "Log in with Spotify" from the `.requiresLogin` state.
    func login(startSession: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void) {
        guard let loginAction else {
            state = .authFailure
            return
        }
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.runLogin(loginAction: loginAction, startSession: startSession)
        }
    }

    // MARK: - Private — Text Parsing

    private func observeTextChanges() {
        $text
            .dropFirst()
            .sink { [weak self] newValue in
                self?.handleTextChange(newValue)
            }
            .store(in: &cancellables)
    }

    private func handleTextChange(_ input: String) {
        debounceTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            state = .empty
            parsedPlaylistID = ""
            parsedURL        = ""
            return
        }
        state = .parsing
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.parseURL(trimmed)
        }
    }

    private func parseURL(_ input: String) {
        let kind = SpotifyURLParser.parse(input)
        switch kind {
        case .playlist(let id):
            parsedPlaylistID = id
            parsedURL        = input
            state            = .preview(playlistID: id)
        case .track, .album, .artist:
            parsedPlaylistID = ""
            parsedURL        = ""
            state            = .rejectedKind(kind)
        case .invalid:
            parsedPlaylistID = ""
            parsedURL        = ""
            state            = .invalid
        }
    }

    // MARK: - Private — Connect

    private func runConnect(
        playlistID: String,
        startSession: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    ) async {
        isConnecting = true
        defer { isConnecting = false }

        let source: PlaylistSource = .spotifyPlaylistURL(parsedURL)
        let initialResult = await attempt(source: source)
        if Task.isCancelled { return }

        await applyResult(initialResult, source: source, startSession: startSession)
    }

    private func runLogin(
        loginAction: @Sendable () async throws -> Void,
        startSession: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    ) async {
        isConnecting = true
        defer { isConnecting = false }

        state = .waitingForCallback
        do {
            try await loginAction()
        } catch {
            state = .authFailure
            return
        }

        // Login succeeded — retry the connect with the new OAuth token.
        guard !parsedURL.isEmpty else {
            state = .empty
            return
        }
        let source: PlaylistSource = .spotifyPlaylistURL(parsedURL)
        let result = await attempt(source: source)
        if Task.isCancelled { return }
        await applyResult(result, source: source, startSession: startSession, afterLogin: true)
    }

    /// Apply an `AttemptResult` to the current state. `afterLogin` changes the
    /// `.requiresLogin` mapping to `.authFailure` (still no token after a fresh login).
    private func applyResult(
        _ result: AttemptResult,
        source: PlaylistSource,
        startSession: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void,
        afterLogin: Bool = false
    ) async {
        switch result {
        case .success(let tracks):
            // Pass pre-fetched tracks so SessionManager can skip re-fetching via its own
            // connector (which would use client-credentials and get a 401 for OAuth-gated playlists).
            await startSession(tracks, source)
        case .requiresLogin:
            state = afterLogin ? .authFailure : .requiresLogin
        case .privatePlaylist:
            state = .privatePlaylist
        case .notFound:
            state = .notFound
        case .authFailure:
            state = .authFailure
        case .rateLimited:
            await retryAfterRateLimit(source: source, startSession: startSession)
        case .error(let msg):
            state = .error(msg)
        }
    }

    private func retryAfterRateLimit(
        source: PlaylistSource,
        startSession: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    ) async {
        let retryDelays = [2.0, 5.0, 15.0]
        for (index, delay) in retryDelays.enumerated() {
            state = .rateLimited(attempt: index + 1)
            try? await delayProvider.sleep(seconds: delay)
            if Task.isCancelled { return }
            let result = await attempt(source: source)
            switch result {
            case .success(let tracks):
                await startSession(tracks, source)
                return
            case .requiresLogin:
                state = .requiresLogin
                return
            case .privatePlaylist:
                state = .privatePlaylist
                return
            case .notFound:
                state = .notFound
                return
            case .authFailure:
                state = .authFailure
                return
            case .rateLimited:
                continue
            case .error(let msg):
                state = .error(msg)
                return
            }
        }
        state = .error("Couldn't reach Spotify. Check your network or try a different source.")
    }

    // MARK: - Private — Attempt

    private enum AttemptResult {
        case success([TrackIdentity])
        case requiresLogin
        case privatePlaylist
        case notFound
        case authFailure
        case rateLimited
        case error(String)
    }

    private func attempt(source: PlaylistSource) async -> AttemptResult {
        do {
            let tracks = try await connector.connect(source: source)
            return .success(tracks)
        } catch PlaylistConnectorError.spotifyAuthFailure {
            return .authFailure
        } catch PlaylistConnectorError.spotifyLoginRequired {
            // Map to the right visual state based on whether the user is already authenticated.
            // SpotifyOAuthPlaylistConnector already handles most of this, but the oauthProvider
            // check provides a fallback when the connector is a plain PlaylistConnector.
            let authenticated = await oauthProvider?.isAuthenticated ?? false
            return authenticated ? .privatePlaylist : .requiresLogin
        } catch PlaylistConnectorError.spotifyPlaylistInaccessible {
            return .privatePlaylist
        } catch PlaylistConnectorError.spotifyPlaylistNotFound {
            return .notFound
        } catch PlaylistConnectorError.rateLimited {
            return .rateLimited
        } catch PlaylistConnectorError.unrecognizedPlaylistURL {
            return .error("That doesn't look like a Spotify playlist link.")
        } catch {
            return .error("Couldn't reach Spotify.")
        }
    }
}
