// SpotifyKeychainStore — Persists and retrieves the Spotify OAuth refresh token
// using the macOS Keychain (Security.framework).
//
// No sandbox entitlements are required — Phosphene runs unsandboxed
// (com.apple.security.app-sandbox = false).
//
// Default service key: "com.phosphene.spotify"
// Default account key: "refresh_token"

import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "SpotifyKeychain")

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

    // MARK: - Init

    /// Create a keychain store.
    ///
    /// - Parameters:
    ///   - service: Keychain service identifier (default: `"com.phosphene.spotify"`).
    ///   - account: Keychain account name (default: `"refresh_token"`).
    public init(
        service: String = "com.phosphene.spotify",
        account: String = "refresh_token"
    ) {
        self.service = service
        self.account = account
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
            return nil
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
