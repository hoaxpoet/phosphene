// SpotifyKeychainStore — Persists and retrieves the Spotify OAuth refresh token
// using the macOS Keychain (Security.framework).
//
// No sandbox entitlements are required — Phosphene runs unsandboxed
// (com.apple.security.app-sandbox = false).
//
// Default service key: "io.uzume.spotify"
// Default account key: "refresh_token"
//
// RN.1: tokens written before the rename live under "com.phosphene.spotify".
// `loadRefreshToken()` falls back to that service once and re-saves under the
// new one, so the rename does not force the user to reconnect Spotify. The old
// item is left in place — deleting Keychain entries on the user's behalf is not
// this type's call. Pass `legacyService: nil` to opt out (tests do).

import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "io.uzume.mac", category: "SpotifyKeychain")

// MARK: - SpotifyKeychainStoring

/// Stores and retrieves a Spotify OAuth refresh token from the Keychain.
public protocol SpotifyKeychainStoring: Sendable {
    /// Persist a new refresh token, replacing any existing value.
    func saveRefreshToken(_ token: String) throws
    /// Read the stored refresh token, or `nil` if none exists.
    func loadRefreshToken() -> String?
    /// Delete the stored refresh token (e.g. on explicit log-out).
    func deleteRefreshToken()
}

// MARK: - SpotifyKeychainStore

/// Default `SpotifyKeychainStoring` implementation backed by `SecItem*` APIs.
public final class SpotifyKeychainStore: SpotifyKeychainStoring, @unchecked Sendable {

    // MARK: - State

    private let service: String
    private let account: String
    /// Pre-rename service to adopt a token from, once. `nil` disables the fallback.
    private let legacyService: String?

    // MARK: - Init

    /// Create a keychain store.
    ///
    /// - Parameters:
    ///   - service: Keychain service identifier (default: `"io.uzume.spotify"`).
    ///   - account: Keychain account name (default: `"refresh_token"`).
    ///   - legacyService: Pre-rename service to adopt a token from on first read
    ///     (default: the RN.1 legacy service). `nil` disables the fallback.
    public init(
        service: String = "io.uzume.spotify",
        account: String = "refresh_token",
        legacyService: String? = "com.phosphene.spotify"
    ) {
        self.service = service
        self.account = account
        self.legacyService = legacyService
    }

    // MARK: - SpotifyKeychainStoring

    public func saveRefreshToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try to update an existing item first; add if not found.
        let query = baseQuery()
        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let update: [CFString: Any] = [kSecValueData: data]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        } else {
            var item = query
            item[kSecValueData] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            logger.error("Keychain save failed: \(status)")
            throw KeychainError.saveFailed(status)
        }
        logger.debug("Keychain: Spotify refresh token saved")
    }

    public func loadRefreshToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return adoptLegacyRefreshToken()
        }
        return String(data: data, encoding: .utf8)
    }

    public func deleteRefreshToken() {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            logger.debug("Keychain: Spotify refresh token deleted")
        }
    }

    // MARK: - Private

    /// Read the pre-rename item and re-save it under the current service.
    ///
    /// Returns the token so the caller's first read succeeds; the re-save makes
    /// every later read hit the fast path. Never logs the token itself.
    private func adoptLegacyRefreshToken() -> String? {
        guard let legacyService else { return nil }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: legacyService,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        query.removeAll()
        do {
            try saveRefreshToken(token)
            logger.info("Keychain: adopted the pre-rename Spotify refresh token")
        } catch {
            // Returning the token still lets this session authenticate.
            logger.error("Keychain: could not re-save the adopted token")
        }
        return token
    }

    private func baseQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

// MARK: - KeychainError

/// Errors thrown by `SpotifyKeychainStore`.
public enum KeychainError: Error, Sendable {
    case encodingFailed
    case saveFailed(OSStatus)
}
