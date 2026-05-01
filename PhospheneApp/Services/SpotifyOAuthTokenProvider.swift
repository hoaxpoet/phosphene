// SpotifyOAuthTokenProvider — Spotify Authorization Code + PKCE token provider.
// Implements SpotifyTokenProviding for injection into SpotifyWebAPIConnector.
//
// acquire() → silent refresh (Keychain) → .spotifyLoginRequired if no token.
// login() → PKCE + browser → CheckedContinuation → handleCallback(url:) → tokens.
// SpotifyOAuthPlaylistConnector (separate file) wraps PlaylistConnector with
// OAuth-aware 403 remapping (.spotifyLoginRequired ↔ .spotifyPlaylistInaccessible).

import AppKit           // NSWorkspace.shared.open(_:)
import CryptoKit        // SHA256 for PKCE challenge
import Foundation
import Session          // SpotifyTokenProviding, PlaylistConnectorError
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "SpotifyOAuth")

// MARK: - SpotifyOAuthLoginProviding

/// Extended interface for OAuth-capable token providers.
///
/// Exposed to `SpotifyConnectionViewModel` via the injected `loginAction` closure.
/// `isAuthenticated` lets the VM map 403 errors correctly: if authenticated, a 403
/// means "private playlist"; if not authenticated, it means "need to log in".
public protocol SpotifyOAuthLoginProviding: AnyObject, Sendable {
    /// `true` once a valid refresh token is stored in the Keychain.
    var isAuthenticated: Bool { get async }
    /// Initiate the OAuth Authorization Code + PKCE browser flow.
    /// Returns when an access token has been successfully obtained.
    /// Throws `PlaylistConnectorError.spotifyAuthFailure` if the flow fails or times out.
    func login() async throws
    /// Receive the redirect URL from the browser; continues a pending `login()` call.
    func handleCallback(url: URL) async
    /// Remove all stored tokens and mark the provider as unauthenticated.
    func logout() async
}

// MARK: - SpotifyOAuthTokenProvider

/// `SpotifyTokenProviding` + `SpotifyOAuthLoginProviding` actor backed by
/// Authorization Code + PKCE and Keychain refresh-token persistence.
public actor SpotifyOAuthTokenProvider: SpotifyTokenProviding, SpotifyOAuthLoginProviding {

    // MARK: - Dependencies

    private let keychainStore: any SpotifyKeychainStoring
    private let urlSession: URLSession
    /// Injected to open the browser; defaults to `NSWorkspace.shared.open(_:)`.
    private let openURL: @Sendable (URL) -> Void

    // MARK: - State

    private var cachedAccessToken: String?
    private var tokenExpiry: Date?
    private var codeVerifier: String?
    /// Set to `true` when a valid refresh token has been stored in Keychain.
    private var _isAuthenticated: Bool = false
    /// Pending continuation from an in-flight `login()` call.
    private var pendingContinuation: CheckedContinuation<Void, Error>?
    /// Task that cancels the pending continuation after a timeout.
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Constants

    private static let expiryMarginSeconds: TimeInterval = 300  // refresh 5 min early
    private static let loginTimeoutSeconds: TimeInterval = 300  // 5 min browser timeout
    private static let redirectURI = "phosphene://spotify-callback"
    private static let authEndpoint = "https://accounts.spotify.com/authorize"
    private static let tokenEndpoint = "https://accounts.spotify.com/api/token"
    private static let scopes = "playlist-read-private playlist-read-collaborative"

    // MARK: - Init

    /// Create an OAuth token provider.
    ///
    /// - Parameters:
    ///   - keychainStore: Keychain wrapper (default: `SpotifyKeychainStore()`).
    ///   - urlSession: URL session for token exchange calls (default: `.shared`).
    ///   - openURL: Closure to open the Spotify authorize URL (default: `NSWorkspace`).
    public init(
        keychainStore: any SpotifyKeychainStoring = SpotifyKeychainStore(),
        urlSession: URLSession = .shared,
        openURL: @Sendable @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
        self.openURL = openURL
        // Restore auth state from Keychain on init.
        self._isAuthenticated = keychainStore.loadRefreshToken() != nil
    }

    /// Convenience factory for production use. Reads `SpotifyClientID` from Info.plist.
    public static func makeLive(urlSession: URLSession = .shared) -> SpotifyOAuthTokenProvider {
        SpotifyOAuthTokenProvider(urlSession: urlSession)
    }

    // MARK: - SpotifyOAuthLoginProviding

    public var isAuthenticated: Bool {
        _isAuthenticated
    }

    public func login() async throws {
        // Generate PKCE pair.
        let verifier = makePKCEVerifier()
        let challenge = makePKCEChallenge(verifier: verifier)
        codeVerifier = verifier

        // Build authorize URL.
        guard let clientID = Bundle.main.infoDictionary?["SpotifyClientID"] as? String,
              !clientID.isEmpty else {
            throw PlaylistConnectorError.spotifyAuthFailure("SpotifyClientID missing from Info.plist")
        }
        guard let authURL = makeAuthorizeURL(clientID: clientID, challenge: challenge) else {
            throw PlaylistConnectorError.spotifyAuthFailure("Failed to construct authorize URL")
        }

        // Open browser.
        openURL(authURL)
        logger.info("SpotifyOAuth: opened browser for authorization")

        // Await callback with timeout.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingContinuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.loginTimeoutSeconds))
                guard !Task.isCancelled else { return }
                await self?.timeoutLogin()
            }
        }
    }

    public func handleCallback(url: URL) async {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.host == "spotify-callback"
        else { return }

        // Check for OAuth error response (user denied, etc.).
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            logger.error("SpotifyOAuth: authorization denied — \(error)")
            resumeContinuation(throwing: PlaylistConnectorError.spotifyAuthFailure("Authorization denied: \(error)"))
            return
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            logger.error("SpotifyOAuth: missing code or verifier in callback")
            resumeContinuation(throwing: PlaylistConnectorError.spotifyAuthFailure("Invalid callback URL"))
            return
        }

        guard let clientID = Bundle.main.infoDictionary?["SpotifyClientID"] as? String,
              !clientID.isEmpty else {
            resumeContinuation(throwing: PlaylistConnectorError.spotifyAuthFailure("SpotifyClientID missing"))
            return
        }

        do {
            let tok = try await exchangeCode(
                code: code,
                verifier: verifier,
                clientID: clientID
            )
            cachedAccessToken = tok.access
            tokenExpiry = Date().addingTimeInterval(TimeInterval(tok.expiresIn))
            if let refresh = tok.refresh {
                try? keychainStore.saveRefreshToken(refresh)
                _isAuthenticated = true
            }
            codeVerifier = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            logger.info("SpotifyOAuth: token exchange succeeded; authenticated=true")
            resumeContinuation(with: ())
        } catch {
            logger.error("SpotifyOAuth: token exchange failed — \(error)")
            resumeContinuation(throwing: PlaylistConnectorError.spotifyAuthFailure(error.localizedDescription))
        }
    }

    public func logout() async {
        cachedAccessToken = nil
        tokenExpiry = nil
        codeVerifier = nil
        _isAuthenticated = false
        keychainStore.deleteRefreshToken()
        logger.info("SpotifyOAuth: logged out")
    }

    // MARK: - SpotifyTokenProviding

    public func acquire() async throws -> String {
        // 1. Return valid cached token.
        if let token = cachedAccessToken, let expiry = tokenExpiry,
           expiry.timeIntervalSinceNow > Self.expiryMarginSeconds {
            return token
        }

        // 2. Try silent refresh.
        if let refreshToken = keychainStore.loadRefreshToken() {
            guard let clientID = Bundle.main.infoDictionary?["SpotifyClientID"] as? String,
                  !clientID.isEmpty else {
                throw PlaylistConnectorError.spotifyAuthFailure("SpotifyClientID missing from Info.plist")
            }
            do {
                let tok = try await refreshAccessToken(
                    refreshToken: refreshToken,
                    clientID: clientID
                )
                cachedAccessToken = tok.access
                tokenExpiry = Date().addingTimeInterval(TimeInterval(tok.expiresIn))
                if let newRefresh = tok.refresh {
                    try? keychainStore.saveRefreshToken(newRefresh)
                }
                logger.debug("SpotifyOAuth: silent refresh succeeded")
                return tok.access
            } catch {
                // Refresh token expired or revoked — require re-login.
                logger.warning("SpotifyOAuth: silent refresh failed (\(error)); clearing tokens")
                cachedAccessToken = nil
                tokenExpiry = nil
                _isAuthenticated = false
                keychainStore.deleteRefreshToken()
            }
        }

        // 3. No valid token and no refresh token — user must log in.
        throw PlaylistConnectorError.spotifyLoginRequired
    }

    public func invalidate() async {
        cachedAccessToken = nil
        tokenExpiry = nil
        logger.debug("SpotifyOAuth: access token invalidated")
    }

    // MARK: - PKCE Helpers

    private func makePKCEVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 96)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func makePKCEChallenge(verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private func makeAuthorizeURL(clientID: String, challenge: String) -> URL? {
        var comps = URLComponents(string: Self.authEndpoint)
        comps?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        return comps?.url
    }

    // MARK: - Token Exchange

    private struct TokenResponse {
        let access: String
        let refresh: String?
        let expiresIn: Int
    }

    /// Exchange an authorization code for access + refresh tokens.
    private func exchangeCode(
        code: String,
        verifier: String,
        clientID: String
    ) async throws -> TokenResponse {
        guard let url = URL(string: Self.tokenEndpoint) else {
            throw PlaylistConnectorError.networkFailure("Invalid token endpoint URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ].formEncoded()
        return try await parseTokenResponse(request: request)
    }

    /// Exchange a refresh token for a new access (and optionally new refresh) token.
    private func refreshAccessToken(
        refreshToken: String,
        clientID: String
    ) async throws -> TokenResponse {
        guard let url = URL(string: Self.tokenEndpoint) else {
            throw PlaylistConnectorError.networkFailure("Invalid token endpoint URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ].formEncoded()
        return try await parseTokenResponse(request: request)
    }

    private func parseTokenResponse(request: URLRequest) async throws -> TokenResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw PlaylistConnectorError.networkFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PlaylistConnectorError.networkFailure("Non-HTTP response from token endpoint")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<unreadable>"
            logger.error("SpotifyOAuth: token endpoint HTTP \(http.statusCode): \(body)")
            if http.statusCode == 400 {
                // 400 typically means invalid_grant (code already used or refresh revoked).
                throw PlaylistConnectorError.spotifyAuthFailure("Token exchange failed (invalid_grant)")
            }
            throw PlaylistConnectorError.networkFailure("Token endpoint HTTP \(http.statusCode)")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String,
            let expiresIn = json["expires_in"] as? Int
        else {
            throw PlaylistConnectorError.parseFailure("Could not parse token response")
        }

        return TokenResponse(
            access: accessToken,
            refresh: json["refresh_token"] as? String,
            expiresIn: expiresIn
        )
    }

    // MARK: - Continuation Helpers

    private func resumeContinuation(with value: Void) {
        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume(returning: value)
    }

    private func resumeContinuation(throwing error: Error) {
        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume(throwing: error)
    }

    private func timeoutLogin() {
        guard pendingContinuation != nil else { return }
        logger.warning("SpotifyOAuth: login timed out after \(Self.loginTimeoutSeconds)s")
        codeVerifier = nil
        resumeContinuation(throwing: PlaylistConnectorError.spotifyAuthFailure("Login timed out"))
    }
}

// MARK: - Data + Base64URL

private extension Data {
    /// RFC 4648 §5 URL-safe base64 without padding — required by PKCE spec.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Dictionary + form encoding

private extension [String: String] {
    func formEncoded() -> Data? {
        map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}
