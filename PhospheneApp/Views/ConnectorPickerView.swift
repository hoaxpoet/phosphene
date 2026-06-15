// ConnectorPickerView — Three-tile picker for Apple Music, Spotify, and Local Folder.
// Presented as a sheet from IdleView. Uses NavigationStack internally so each
// connector flow view is pushed onto the stack — back button returns to this picker.
//
// U.11: reads `spotifyOAuthProvider` from the environment (set by PhospheneApp) to
// build a `SpotifyConnectionViewModel` with OAuth login capability.

import Session
import SwiftUI

// MARK: - ConnectorPickerView

struct ConnectorPickerView: View {
    static let accessibilityID = "phosphene.view.connectorPicker"

    /// Called when a connector successfully identifies a playlist.
    /// `tracks` contains pre-fetched tracks when available (Spotify OAuth path);
    /// passes `[]` for Apple Music (SessionManager fetches via its own connector).
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void

    @StateObject private var viewModel = ConnectorPickerViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.spotifyOAuthProvider) private var spotifyOAuth

    var body: some View {
        NavigationStack(path: $viewModel.connectorPath) {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    tileList
                    Spacer()
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle(String(localized: "connector.picker.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "connector.picker.close_button")) { dismiss() }
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .navigationDestination(for: ConnectorType.self) { type in
                destination(for: type)
            }
        }
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Private

    @ViewBuilder
    private var tileList: some View {
        VStack(spacing: 12) {
            appleMusicTile
            spotifyTile
            localFolderTile
        }
    }

    @ViewBuilder
    private var appleMusicTile: some View {
        if viewModel.appleMusicRunning {
            NavigationLink(value: ConnectorType.appleMusic) {
                ConnectorTileView(type: .appleMusic, isEnabled: true)
            }
            .buttonStyle(.plain)
        } else {
            ConnectorTileView(
                type: .appleMusic,
                isEnabled: false,
                disabledCaption: String(localized: "connector.picker.apple_music_disabled"),
                secondaryActionLabel: String(localized: "connector.picker.open_apple_music_button"),
                onSecondaryAction: { viewModel.openAppleMusic() }
            )
        }
    }

    @ViewBuilder
    private var spotifyTile: some View {
        NavigationLink(value: ConnectorType.spotify) {
            ConnectorTileView(type: .spotify, isEnabled: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var localFolderTile: some View {
        // GAP A (2026-05-28): tile is now enabled — LF.5 shipped 24h prior.
        // Pushes LocalSourceConnectionView (file / folder / playlist picker)
        // onto the parent NavigationStack, matching the AM / Spotify shape.
        NavigationLink(value: ConnectorType.localFolder) {
            ConnectorTileView(type: .localFolder, isEnabled: true)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footer: some View {
        Text(String(localized: "connector.picker.footer"))
            .font(.caption2)
            .foregroundColor(.white.opacity(0.3))
            .multilineTextAlignment(.center)
            .padding(.top, 24)
    }

    @ViewBuilder
    private func destination(for type: ConnectorType) -> some View {
        switch type {
        case .appleMusic:
            // CA.6-FU-3 (2026-05-21): wrapped so the VM survives ConnectorPickerView
            // body re-evaluations (parent `viewModel.appleMusicRunning` flips on
            // NSWorkspace launch/terminate observers — would otherwise rebuild the
            // VM and orphan the in-flight 2 s auto-retry Task). Same shape as
            // `OAuthSpotifyConnectionWrapper` below.
            AppleMusicConnectionWrapper(
                onConnect: onConnect,
                onUseSpotifyInstead: { viewModel.switchConnector(to: .spotify) }
            )
        case .spotify:
            spotifyDestination
        case .localFolder:
            // GAP A (2026-05-28): replaces the LF.4-era "Coming later" stub
            // with the dedicated file / folder / playlist picker.
            LocalSourceConnectionView()
        }
    }

    /// Builds the SpotifyConnectionView wired with the OAuth provider when available.
    /// Falls back to a plain (client-credentials) connector in previews / unit tests.
    ///
    /// Uses `OAuthSpotifyConnectionWrapper` so the ViewModel (and its in-flight Task,
    /// parsedURL, and text state) survive SwiftUI body re-evaluations caused by app
    /// foregrounding via the `phosphene://` URL scheme callback. A ViewModel created
    /// inline in a `@ViewBuilder` property is destroyed on every body re-evaluation;
    /// `@StateObject` inside the wrapper ensures it lives for the view's full lifetime.
    @ViewBuilder
    private var spotifyDestination: some View {
        if let oauth = spotifyOAuth {
            OAuthSpotifyConnectionWrapper(
                oauth: oauth,
                onConnect: onConnect,
                onUseAppleMusicInstead: { viewModel.switchConnector(to: .appleMusic) }
            )
        } else {
            // Fallback: no OAuth provider injected (e.g. SwiftUI preview or plain unit test).
            // SpotifyConnectionView now expects ([TrackIdentity], PlaylistSource) — pass through.
            SpotifyConnectionView(
                viewModel: SpotifyConnectionViewModel(),
                onConnect: onConnect,
                onUseAppleMusicInstead: { viewModel.switchConnector(to: .appleMusic) }
            )
        }
    }
}

// MARK: - AppleMusicConnectionWrapper

/// A thin view wrapper that owns the `AppleMusicConnectionViewModel` as a `@StateObject`,
/// ensuring the VM and its in-flight Tasks survive across SwiftUI body re-evaluations.
///
/// `ConnectorPickerView` re-evaluates whenever its observed `viewModel.appleMusicRunning`
/// flag changes — fired by the NSWorkspace launch/terminate observers (250 ms-debounced).
/// A ViewModel created inline in the `navigationDestination(for:)` `@ViewBuilder` would
/// be rebuilt at each re-eval, orphaning the in-flight 2 s auto-retry Task and reverting
/// the connection state machine to `.idle`. `@StateObject` here persists the VM for the
/// full lifetime of this view regardless of how many times the parent re-evaluates.
///
/// Mirrors the `OAuthSpotifyConnectionWrapper` pattern below (CA.6-FU-3, 2026-05-21).
private struct AppleMusicConnectionWrapper: View {

    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    let onUseSpotifyInstead: () -> Void

    @StateObject private var viewModel = AppleMusicConnectionViewModel()

    var body: some View {
        AppleMusicConnectionView(
            viewModel: viewModel,
            onConnect: onConnect,
            onUseSpotifyInstead: onUseSpotifyInstead
        )
    }
}

// MARK: - OAuthSpotifyConnectionWrapper

/// A thin view wrapper that owns the `SpotifyConnectionViewModel` as a `@StateObject`,
/// ensuring the VM and its in-flight OAuth Task survive across SwiftUI body re-evaluations.
///
/// When the user completes the PKCE browser flow and macOS routes `phosphene://spotify-callback`
/// back to the app, SwiftUI triggers a body re-evaluation of `ConnectorPickerView`. Any
/// ViewModel created inline in a `@ViewBuilder` computed property would be torn down and
/// recreated at that point — losing `parsedURL`, the active `connectTask`, and the
/// post-login connect retry. `@StateObject` here persists the VM for the full lifetime of
/// this view, regardless of how many times the parent re-evaluates.
private struct OAuthSpotifyConnectionWrapper: View {

    let oauth: SpotifyOAuthTokenProvider
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    let onUseAppleMusicInstead: () -> Void

    @StateObject private var viewModel: SpotifyConnectionViewModel

    init(oauth: SpotifyOAuthTokenProvider,
         onConnect: @escaping @Sendable ([TrackIdentity], PlaylistSource) async -> Void,
         onUseAppleMusicInstead: @escaping () -> Void) {
        self.oauth = oauth
        self.onConnect = onConnect
        self.onUseAppleMusicInstead = onUseAppleMusicInstead
        let connector = SpotifyOAuthPlaylistConnector(
            inner: PlaylistConnector(
                spotifyConnector: SpotifyWebAPIConnector(tokenProvider: oauth)
            ),
            oauthProvider: oauth
        )
        _viewModel = StateObject(wrappedValue: SpotifyConnectionViewModel(
            connector: connector,
            loginAction: { try await oauth.login() },
            oauthProvider: oauth
        ))
    }

    var body: some View {
        SpotifyConnectionView(
            viewModel: viewModel,
            onConnect: onConnect,
            onUseAppleMusicInstead: onUseAppleMusicInstead
        )
    }
}
