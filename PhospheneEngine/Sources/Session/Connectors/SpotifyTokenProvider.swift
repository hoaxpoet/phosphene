// SpotifyTokenProvider — Client-credentials token acquisition and caching.
// Reads credentials from Info.plist (SpotifyClientID / SpotifyClientSecret).
// Deduplicates concurrent acquire() calls onto a single in-flight Task.

import Foundation
import Shared
import os.log

private let logger = Logging.session

// MARK: - SpotifyTokenProviding

/// Acquires and caches a Spotify client-credentials access token.
public protocol SpotifyTokenProviding: AnyObject, Sendable {
    /// Return a valid Spotify bearer token, refreshing if necessary.
    ///
    /// Throws `PlaylistConnectorError.spotifyAuthFailure` if credentials are
    /// missing, malformed, or the Spotify token endpoint rejects them.
    func acquire() async throws -> String

    /// Evict the cached token, forcing the next `acquire()` to re-authenticate.
    func invalidate() async
}

// MARK: - DefaultSpotifyTokenProvider

/// Default `SpotifyTokenProviding` implementation backed by the Spotify
/// Accounts API (`https://accounts.spotify.com/api/token`).
///
/// Credentials are read once from `Bundle.main.infoDictionary` at init time.
/// A cached token is returned until it is within 60 seconds of expiry.
/// Concurrent callers share a single in-flight refresh Task — no thundering herd.
public actor DefaultSpotifyTokenProvider: SpotifyTokenProviding {

    // MARK: - Nested Types

    private struct CachedToken {
        let value: String
        let expiresAt: Date
    }

    // MARK: - Dependencies

    private let urlSession: URLSession
    private let clientID: String
    private let clientSecret: String

    // MARK: - State

    private var cached: CachedToken?
    /// In-flight refresh task. Concurrent acquire() calls await this instead of
    /// starting a second request.
    private var refreshTask: Task<String, Error>?

    // MARK: - Constants

    // swiftlint:disable:next force_unwrapping
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    /// Refresh the token when this many seconds remain before it expires.
    private static let safetyMarginSeconds: TimeInterval = 60

    // MARK: - Init

    /// Create a token provider reading credentials from `Bundle.main.infoDictionary`.
    ///
    /// Throws `.spotifyAuthFailure` if `SpotifyClientID` or `SpotifyClientSecret`
    /// keys are absent or empty in the bundle's Info.plist.
    ///
    /// - Parameter urlSession: URL session to use for token requests (default: `.shared`).
    public init(urlSession: URLSession = .shared) throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let clientID = (info["SpotifyClientID"] as? String) ?? ""
        let clientSecret = (info["SpotifyClientSecret"] as? String) ?? ""
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw PlaylistConnectorError.spotifyAuthFailure(
                "Spotify credentials not configured. See RUNBOOK §Spotify connector setup."
            )
        }
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.urlSession = urlSession
    }

    /// Create a token provider with explicit credentials (for testing).
    public init(clientID: String, clientSecret: String, urlSession: URLSession = .shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.urlSession = urlSession
    }

    // MARK: - SpotifyTokenProviding

    public func acquire() async throws -> String {
        // Return a cached token that has plenty of life left.
        if let cached, cached.expiresAt.timeIntervalSinceNow > Self.safetyMarginSeconds {
            return cached.value
        }

        // Reuse an existing in-flight refresh rather than starting a second one.
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw PlaylistConnectorError.spotifyAuthFailure("Provider deallocated") }
            return try await self.fetchToken()
        }
        refreshTask = task

        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }

    public func invalidate() async {
        cached = nil
    }

    // MARK: - Private

    private func fetchToken() async throws -> String {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"

        let credentials = "\(clientID):\(clientSecret)"
        guard let credData = credentials.data(using: .utf8) else {
            throw PlaylistConnectorError.spotifyAuthFailure("Failed to encode Spotify credentials")
        }
        let encoded = credData.base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw PlaylistConnectorError.networkFailure(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw PlaylistConnectorError.spotifyAuthFailure("Token endpoint returned non-HTTP response")
        }

        switch http.statusCode {
        case 200:
            break
        case 400, 401:
            throw PlaylistConnectorError.spotifyAuthFailure(
                "Spotify rejected credentials (HTTP \(http.statusCode)). "
                + "Check SpotifyClientID and SpotifyClientSecret in Phosphene.local.xcconfig."
            )
        default:
            throw PlaylistConnectorError.spotifyAuthFailure(
                "Unexpected token endpoint response: HTTP \(http.statusCode)"
            )
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String,
            let expiresIn = json["expires_in"] as? TimeInterval
        else {
            throw PlaylistConnectorError.spotifyAuthFailure("Could not parse Spotify token response")
        }

        let expiresAt = Date().addingTimeInterval(expiresIn)
        cached = CachedToken(value: accessToken, expiresAt: expiresAt)
        logger.info("Spotify: acquired token, expires in \(Int(expiresIn))s")
        return accessToken
    }
}

// MARK: - MissingCredentialsTokenProvider

/// Fallback token provider used when Info.plist credentials are absent.
/// Every `acquire()` call immediately throws `.spotifyAuthFailure` so the
/// error surfaces at connect time with actionable copy.
final class MissingCredentialsTokenProvider: SpotifyTokenProviding, @unchecked Sendable {
    func acquire() async throws -> String {
        throw PlaylistConnectorError.spotifyAuthFailure(
            "Spotify credentials not configured. See RUNBOOK §Spotify connector setup."
        )
    }
    func invalidate() async {}
}
