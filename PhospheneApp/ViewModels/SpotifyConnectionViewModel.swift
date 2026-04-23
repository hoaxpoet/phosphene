// SpotifyConnectionViewModel — State machine for the Spotify URL-paste connection flow.
//
// PRE-FLIGHT AUDIT NOTES (U.3):
// - No lightweight Spotify preview method exists. Without OAuth (deferred to v2),
//   connector.connect() immediately throws .spotifyAuthRequired (empty token check).
//   For U.3: URL parsing alone provides the "preview" (playlist ID confirmed valid).
//   On Continue, connect() is called for pre-validation with retry logic; if it throws
//   .spotifyAuthRequired, startSession() is called directly (SessionManager degrades
//   gracefully to .ready with empty plan — live-only reactive mode).
// - Rate-limit (HTTP 429) detection: parsed from networkFailure("...: HTTP 429") string.
// - TODO(U.3-followup): Add OAuth flow in v2. Pass real access token to connector and
//   use the returned [TrackIdentity] preview count in the preview card.

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
    /// HTTP 404 — playlist not found (private or deleted).
    case notFound
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

    // MARK: - Private

    private var parsedPlaylistID: String = ""
    private var parsedURL: String = ""
    private var debounceTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(
        connector: any PlaylistConnecting = PlaylistConnector(),
        delayProvider: any DelayProviding = RealDelay()
    ) {
        self.connector = connector
        self.delayProvider = delayProvider
        observeTextChanges()
    }

    // MARK: - Actions

    /// Called when the user taps Continue. Only valid when state == .preview.
    func connect(startSession: @escaping @Sendable (PlaylistSource) async -> Void) {
        guard case .preview(let id) = state, !id.isEmpty else { return }
        connectTask?.cancel()
        connectTask = Task { [weak self] in
            await self?.runConnect(playlistID: id, startSession: startSession)
        }
    }

    // MARK: - Private

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

    private func runConnect(
        playlistID: String,
        startSession: @escaping @Sendable (PlaylistSource) async -> Void
    ) async {
        isConnecting = true
        defer { isConnecting = false }

        let source: PlaylistSource = .spotifyPlaylistURL(parsedURL, accessToken: "")
        let initialResult = await attempt(source: source)
        if Task.isCancelled { return }

        switch initialResult {
        case .success, .authRequired:
            await startSession(source)
        case .notFound:
            state = .notFound
        case .rateLimited:
            await retryAfterRateLimit(source: source, startSession: startSession)
        case .error(let msg):
            state = .error(msg)
        }
    }

    private func retryAfterRateLimit(
        source: PlaylistSource,
        startSession: @escaping @Sendable (PlaylistSource) async -> Void
    ) async {
        let retryDelays = [2.0, 5.0, 15.0]
        for (index, delay) in retryDelays.enumerated() {
            state = .rateLimited(attempt: index + 1)
            try? await delayProvider.sleep(seconds: delay)
            if Task.isCancelled { return }
            let result = await attempt(source: source)
            switch result {
            case .success, .authRequired:
                await startSession(source)
                return
            case .notFound:
                state = .notFound
                return
            case .rateLimited:
                continue
            case .error(let msg):
                state = .error(msg)
                return
            }
        }
        state = .error("Couldn't reach Spotify. Try again in a minute.")
    }

    private enum AttemptResult {
        case success([TrackIdentity])
        case authRequired
        case notFound
        case rateLimited
        case error(String)
    }

    private func attempt(source: PlaylistSource) async -> AttemptResult {
        do {
            let tracks = try await connector.connect(source: source)
            return .success(tracks)
        } catch PlaylistConnectorError.spotifyAuthRequired {
            return .authRequired
        } catch PlaylistConnectorError.networkFailure(let msg) where msg.contains("HTTP 429") {
            return .rateLimited
        } catch PlaylistConnectorError.networkFailure(let msg) where msg.contains("HTTP 404") {
            return .notFound
        } catch PlaylistConnectorError.unrecognizedPlaylistURL {
            return .error("That doesn't look like a Spotify playlist link.")
        } catch {
            return .error("Couldn't reach Spotify.")
        }
    }
}
