// SpotifyConnectionViewModel — State machine for the Spotify URL-paste connection flow.
//
// Increment U.10: client-credentials auth via SpotifyTokenProvider.
// Connector.connect() now performs real API calls; the silent-degrade path
// (.spotifyAuthRequired → startSession with empty token) has been removed.
// Three new error states surface the typed errors from SpotifyWebAPIConnector:
//   .privatePlaylist  → §9.2 "That playlist is private."
//   .authFailure      → §9.2 "Phosphene couldn't reach Spotify right now."
//   .notFound         → §9.2 "Couldn't find that playlist."

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
    /// HTTP 403 — playlist is private or otherwise inaccessible.
    case privatePlaylist
    /// Auth failure — credentials missing or rejected by Spotify.
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

        let source: PlaylistSource = .spotifyPlaylistURL(parsedURL)
        let initialResult = await attempt(source: source)
        if Task.isCancelled { return }

        switch initialResult {
        case .success:
            await startSession(source)
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
        startSession: @escaping @Sendable (PlaylistSource) async -> Void
    ) async {
        let retryDelays = [2.0, 5.0, 15.0]
        for (index, delay) in retryDelays.enumerated() {
            state = .rateLimited(attempt: index + 1)
            try? await delayProvider.sleep(seconds: delay)
            if Task.isCancelled { return }
            let result = await attempt(source: source)
            switch result {
            case .success:
                await startSession(source)
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

    private enum AttemptResult {
        case success([TrackIdentity])
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
