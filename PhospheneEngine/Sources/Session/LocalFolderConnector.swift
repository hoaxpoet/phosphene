// LocalFolderConnector — Minimal stub for the Local Folder playlist connector.
// Gated by ENABLE_LOCAL_FOLDER_CONNECTOR compile flag; not enabled in v1.
// Actual folder reading is out of scope until post-v1.

import Foundation

// MARK: - LocalFolderConnector

#if ENABLE_LOCAL_FOLDER_CONNECTOR

/// Reads audio files from a local folder as a playlist.
///
/// v1 stub: always returns an error indicating the feature is not yet available.
/// Replace the body of `connect(source:)` in a future increment with real
/// `AVAsset`-based file enumeration.
public final class LocalFolderConnector: PlaylistConnecting, @unchecked Sendable {

    public init() {}

    public func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        throw PlaylistConnectorError.networkFailure("Local folder connector not yet implemented.")
    }
}

#endif
