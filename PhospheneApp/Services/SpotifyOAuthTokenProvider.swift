// SpotifyOAuthTokenProvider — Spotify Authorization Code + PKCE token provider.
// Implements SpotifyTokenProviding for injection into SpotifyWebAPIConnector.
//
// acquire() → silent refresh (Keychain) → .spotifyLoginRequired if no token.
// login() → PKCE + browser → CheckedContinuation → handleCallback(url:) → tokens.
// SpotifyOAuthPlaylistConnector (separate file) wraps PlaylistConnector with
// OAuth-aware 403 remapping (.spotifyLoginRequired ↔ .spotifyPlaylistInaccessible).
//
// File length: ~494 lines, over the 400-line lint limit. The actor owns four
// logically inseparable concerns — actor state + protocol surface, PKCE +
// state plumbing, token-exchange HTTP, and base64URL/form-encoding helpers —
// and splitting across files would require either (a) widening access on the
// `private` token-exchange and continuation helpers to module-internal, or
// (b) duplicating the `Bundle.main.infoDictionary` / Keychain access surface
// across two files. Both compromises lose more than the lint budget gains.
// Revisit when the next significant Spotify-OAuth increment lands.
// swiftlint:disable file_length

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
    /// Optional injected client ID. When `nil` (production), `resolveClientID()`
    /// reads `SpotifyClientID` from `Bundle.main.infoDictionary`. Tests pass a
    /// stub value so they don't depend on the test target's Info.plist.
    private let clientIDOverride: String?

    // MARK: - State

    private var cachedAccessToken: String?
    private var tokenExpiry: Date?
    private var codeVerifier: String?
    /// CSRF/replay guard: the `state` sent on the in-flight authorize request,
    /// verified against the value echoed back in `handleCallback` (CLEAN.2.2.3a).
    private var pendingState: String?
    /// Set to `true` when a valid refresh token has been stored in Keychain.
    private var _isAuthenticated: Bool = false
    /// Continuations awaiting the in-flight `login()` attempt. A concurrent
    /// `login()` coalesces onto this same attempt rather than overwriting it,
    /// so there is exactly one browser round-trip and one timeout (CLEAN.2.2.1).
    private var pendingContinuations: [CheckedContinuation<Void, Error>] = []
    /// Task that fails the in-flight login after a timeout.
    private var timeoutTask: Task<Void, Never>?
    /// In-flight silent-refresh task. Concurrent `acquire()` calls await this
    /// instead of each spending the (rotating) refresh token (CLEAN.2.2.2).
    private var refreshTask: Task<String, Error>?

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
    ///   - clientID: Optional client ID override; when `nil` (production), the
    ///     provider reads `SpotifyClientID` from `Bundle.main.infoDictionary`.
    ///     Tests pass a stub value so they don't depend on the test target's
    ///     Info.plist.
    public init(
        keychainStore: any SpotifyKeychainStoring = SpotifyKeychainStore(),
        urlSession: URLSession = .shared,
        openURL: @Sendable @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        clientID: String? = nil
    ) {
        self.keychainStore = keychainStore
        self.urlSession = urlSession
        self.openURL = openURL
        self.clientIDOverride = clientID
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
        // Coalesce a concurrent login onto the in-flight attempt: one browser
        // round-trip, one continuation set, one timeout. Without this guard a
        // second login() would overwrite the first's continuation (orphaning the
        // caller) and arm a second stray timeout (CLEAN.2.2.1).
        if !pendingContinuations.isEmpty {
            try await withCheckedThrowingContinuation { pendingContinuations.append($0) }
            return
        }

        // Generate PKCE pair + CSRF state.
        let verifier = makePKCEVerifier()
        let challenge = makePKCEChallenge(verifier: verifier)
        let state = randomURLSafeToken(byteCount: 32)
        codeVerifier = verifier
        pendingState = state

        // Build authorize URL.
        let clientID = try resolveClientID()
        guard let authURL = makeAuthorizeURL(clientID: clientID, challenge: challenge, state: state) else {
            codeVerifier = nil
            pendingState = nil
            throw PlaylistConnectorError.spotifyAuthFailure("Failed to construct authorize URL")
        }

        // Open browser.
        openURL(authURL)
        logger.info("SpotifyOAuth: opened browser for authorization")

        // Await callback with timeout.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.pendingContinuations.append(continuation)
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
            components.scheme == "phosphene",
            components.host == "spotify-callback"
        else { return }

        // Check for OAuth error response (user denied, etc.).
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            logger.error("SpotifyOAuth: authorization denied — \(error)")
            finishLogin(.failure(PlaylistConnectorError.spotifyAuthFailure("Authorization denied: \(error)")))
            return
        }

        // CSRF/replay guard: the returned `state` must match what we sent
        // (CLEAN.2.2.3a). A nil `pendingState` means no login is in flight.
        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        guard let expectedState = pendingState, returnedState == expectedState else {
            logger.error("SpotifyOAuth: callback state mismatch — rejecting (possible CSRF/replay)")
            finishLogin(.failure(PlaylistConnectorError.spotifyAuthFailure("Callback state mismatch")))
            return
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            logger.error("SpotifyOAuth: missing code or verifier in callback")
            finishLogin(.failure(PlaylistConnectorError.spotifyAuthFailure("Invalid callback URL")))
            return
        }

        let clientID: String
        do {
            clientID = try resolveClientID()
        } catch {
            finishLogin(.failure(error))
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
                persistRefreshToken(refresh)
                _isAuthenticated = true
            }
            logger.info("SpotifyOAuth: token exchange succeeded; authenticated=\(self._isAuthenticated)")
            finishLogin(.success(()))
        } catch {
            logger.error("SpotifyOAuth: token exchange failed — \(error)")
            finishLogin(.failure(PlaylistConnectorError.spotifyAuthFailure(error.localizedDescription)))
        }
    }

    public func logout() async {
        cachedAccessToken = nil
        tokenExpiry = nil
        codeVerifier = nil
        pendingState = nil
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

        // 2. Coalesce onto an in-flight refresh — concurrent callers must not
        //    each spend the (rotating) refresh token (CLEAN.2.2.2).
        if let inFlight = refreshTask {
            return try await inFlight.value
        }

        // 3. Need a stored refresh token to proceed.
        guard let refreshToken = keychainStore.loadRefreshToken() else {
            throw PlaylistConnectorError.spotifyLoginRequired
        }
        let clientID = try resolveClientID()
        let task = Task { try await self.runSilentRefresh(refreshToken: refreshToken, clientID: clientID) }
        refreshTask = task
        return try await task.value
    }

    /// Spend the stored refresh token for a fresh access token, update the cache,
    /// and rotate the stored refresh token. Clears `refreshTask` on completion so
    /// the next `acquire()` starts clean. On any failure the refresh token is
    /// treated as dead: tokens are cleared and `.spotifyLoginRequired` surfaces.
    private func runSilentRefresh(refreshToken: String, clientID: String) async throws -> String {
        defer { refreshTask = nil }
        do {
            let tok = try await refreshAccessToken(refreshToken: refreshToken, clientID: clientID)
            cachedAccessToken = tok.access
            tokenExpiry = Date().addingTimeInterval(TimeInterval(tok.expiresIn))
            if let newRefresh = tok.refresh {
                persistRefreshToken(newRefresh)
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
            throw PlaylistConnectorError.spotifyLoginRequired
        }
    }

    /// Persist the refresh token, logging (not failing) on a Keychain error: the
    /// access token still works this session; only the next cold start is affected
    /// (CLEAN.2.2.3c).
    private func persistRefreshToken(_ token: String) {
        do {
            try keychainStore.saveRefreshToken(token)
        } catch {
            logger.error("SpotifyOAuth: failed to persist refresh token to Keychain — \(error)")
        }
    }

    public func invalidate() async {
        cachedAccessToken = nil
        tokenExpiry = nil
        logger.debug("SpotifyOAuth: access token invalidated")
    }

    // MARK: - Client ID resolution

    /// Resolve the Spotify OAuth client ID — from the injected override (tests)
    /// or from `Bundle.main.infoDictionary["SpotifyClientID"]` (production).
    private func resolveClientID() throws -> String {
        if let override = clientIDOverride, !override.isEmpty {
            return override
        }
        guard let fromBundle = Bundle.main.infoDictionary?["SpotifyClientID"] as? String,
              !fromBundle.isEmpty else {
            throw PlaylistConnectorError.spotifyAuthFailure("SpotifyClientID missing from Info.plist")
        }
        return fromBundle
    }

    // MARK: - PKCE Helpers

    /// Cryptographically-random URL-safe token (PKCE verifier, OAuth `state`).
    private func randomURLSafeToken(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private func makePKCEVerifier() -> String {
        randomURLSafeToken(byteCount: 96)
    }

    private func makePKCEChallenge(verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private func makeAuthorizeURL(clientID: String, challenge: String, state: String) -> URL? {
        var comps = URLComponents(string: Self.authEndpoint)
        comps?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
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

    /// Conclude the in-flight login attempt: cancel the timeout, clear transient
    /// PKCE/state, and resume (then clear) every coalesced continuation. Safe to
    /// call with no login pending — it simply resumes nothing (CLEAN.2.2.1).
    private func finishLogin(_ result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        codeVerifier = nil
        pendingState = nil
        let conts = pendingContinuations
        pendingContinuations.removeAll()
        for cont in conts {
            cont.resume(with: result)
        }
    }

    private func timeoutLogin() {
        guard !pendingContinuations.isEmpty else { return }
        logger.warning("SpotifyOAuth: login timed out after \(Self.loginTimeoutSeconds)s")
        finishLogin(.failure(PlaylistConnectorError.spotifyAuthFailure("Login timed out")))
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

extension [String: String] {
    /// `application/x-www-form-urlencoded` body. Percent-encodes everything
    /// outside the RFC 3986 "unreserved" set — `.urlQueryAllowed` leaves `+`,
    /// `&`, `=`, `/` intact, which corrupts auth codes / tokens that contain
    /// them (CLEAN.2.2.3b). `internal` (not `private`) so it is unit-testable.
    func formEncoded() -> Data? {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        return map { key, value in
            let key = key.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
            let value = value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
            return "\(key)=\(value)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}
