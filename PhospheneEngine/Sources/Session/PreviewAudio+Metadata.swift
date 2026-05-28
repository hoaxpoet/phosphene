// PreviewAudio+Metadata — LF.5 / D-132 metadata extraction helpers.
//
// Reads `AVAsset.commonMetadata` to populate `LocalFileMetadata` (title /
// artist / album) and optionally raw artwork bytes (PNG / JPEG, depending
// on the container — AVFoundation hands back whatever the file ships).
//
// AVFoundation's `commonKey` mapping handles ID3v2 (MP3), MP4 atoms (M4A
// / AAC), and Vorbis comments (FLAC) under a single API, so one extractor
// covers every LF.5 format. Failures (asset can't be opened, no metadata,
// key absent) return nil per-field rather than throwing — metadata is a
// nice-to-have surface, never load-bearing.

@preconcurrency import AVFoundation
import Foundation

// MARK: - LocalFileMetadata

/// AVAsset-extracted track metadata. Codable for persistence in
/// `PersistentStemCache` metadata.json (schema v2). All fields optional.
public struct LocalFileMetadata: Sendable, Codable, Equatable {

    public let title: String?
    public let artist: String?
    public let album: String?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
    }

    /// `true` when every field is `nil`. Used by callers to decide whether
    /// to fall back to filename-based placeholder identity.
    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil
    }
}

// MARK: - PreviewAudio extension

extension PreviewAudio {

    /// Extract title / artist / album from `AVAsset.commonMetadata`.
    ///
    /// Returns `LocalFileMetadata(title: nil, artist: nil, album: nil)` on any
    /// failure (asset open, metadata load, per-item string load) — metadata is
    /// an optimization, never required for playback. Caller falls back to
    /// filename-derived synthetic identity when every field is nil.
    public static func extractMetadata(at url: URL) async -> LocalFileMetadata {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else {
            return LocalFileMetadata()
        }
        var title: String?
        var artist: String?
        var album: String?
        for item in items {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue:
                title = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyArtist.rawValue:
                artist = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                album = try? await item.load(.stringValue)
            default:
                break
            }
        }
        return LocalFileMetadata(
            title: nonEmpty(title),
            artist: nonEmpty(artist),
            album: nonEmpty(album)
        )
    }

    /// Extract artwork bytes (typically PNG or JPEG) from
    /// `AVAsset.commonMetadata`. Returns `nil` when the file ships no artwork
    /// or the data load fails.
    ///
    /// Persisted as a sibling `artwork.bin` file in the disk cache (LF.5);
    /// the byte format is whatever the container embedded — callers that
    /// render artwork must sniff the magic bytes (PNG / JPEG) themselves.
    public static func extractArtwork(at url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else {
            return nil
        }
        for item in items where item.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    /// Trim whitespace + collapse empty strings to `nil`. Several MP3 / M4A
    /// tools embed empty-string title / artist when the user clears the field
    /// in their tag editor; treating those as nil avoids surfacing blank UI
    /// rows that confusingly stand in for "no metadata."
    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
