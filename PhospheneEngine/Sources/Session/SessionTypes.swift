// SessionTypes — Shared value types for the session preparation pipeline.
// These types flow between PreviewResolver, PreviewDownloader, StemCache,
// and SessionPreparer as the pipeline moves from URL → PCM → stems → profile.

import AVFoundation
import CryptoKit
import Foundation

// MARK: - SessionState

/// The lifecycle state of a Phosphene visualization session.
public enum SessionState: String, Sendable, Equatable {
    /// No session is active.
    case idle
    /// Connecting to the music source and reading the playlist.
    case connecting
    /// Pre-analyzing tracks (stem separation + MIR analysis).
    case preparing
    /// Analysis complete. Waiting for playback to begin.
    case ready
    /// Playback is active.
    case playing
    /// The session has ended.
    case ended
}

// MARK: - ProgressiveReadinessLevel

/// Graduated preparation readiness level that advances independently of `SessionState`.
///
/// Allows `PreparationProgressView` to unlock the "Start now" CTA as soon as a minimum
/// prefix of tracks is ready, while preparation continues in the background.
///
/// `Comparable` ordering matches the case order: `preparing < readyForFirstTracks <
/// partiallyPlanned < fullyPrepared < reactiveFallback`. The `>=` idiom reads naturally
/// for threshold checks such as `progressiveReadinessLevel >= .readyForFirstTracks`.
public enum ProgressiveReadinessLevel: Sendable, Equatable, Comparable {
    /// Fewer than `DefaultProgressiveReadinessThreshold` consecutive tracks are ready from position 1.
    case preparing
    /// At least `DefaultProgressiveReadinessThreshold` consecutive tracks ready; < 50 % total.
    case readyForFirstTracks
    /// At least 50 % of all tracks ready; < 100 %.
    case partiallyPlanned
    /// All non-failed tracks are `.ready` or `.partial` — nothing left to prepare.
    case fullyPrepared
    /// No usable plan is possible (connector failure or all tracks failed).
    case reactiveFallback

    private var sortOrder: Int {
        switch self {
        case .preparing: return 0
        case .readyForFirstTracks: return 1
        case .partiallyPlanned: return 2
        case .fullyPrepared: return 3
        case .reactiveFallback: return 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Minimum number of consecutive ready tracks (from position 1) required to unlock "Start now".
public let defaultProgressiveReadinessThreshold: Int = 3

// MARK: - SessionOrigin

/// What kind of input is driving the current session.
///
/// `.playlist(source)` — connector-driven streaming session (Apple Music, Spotify).
/// `.localFile(url)` — single local-file playback (LF.4). Multi-file ingestion
/// (folder / M3U) is LF.5 territory; that will likely extend this enum or use
/// a separate `.localFolder([URL])` case as appropriate.
public enum SessionOrigin: Sendable, Equatable {
    case playlist(PlaylistSource)
    case localFile(URL)
}

extension SessionOrigin {
    public static func == (lhs: SessionOrigin, rhs: SessionOrigin) -> Bool {
        switch (lhs, rhs) {
        case (.playlist, .playlist): return true   // PlaylistSource itself is not Equatable
        case (.localFile(let l), .localFile(let r)): return l == r
        default: return false
        }
    }

    /// True when this origin represents a local-file session. Consumers that
    /// used to read `VisualizerEngine.localFilePlaybackActive` now read this.
    public var isLocalFile: Bool {
        if case .localFile = self { return true }
        return false
    }

    /// The file URL when this origin is `.localFile`, otherwise `nil`.
    public var localFileURL: URL? {
        if case .localFile(let url) = self { return url }
        return nil
    }
}

// MARK: - SessionPlan

/// A planned visual session for an ordered playlist.
///
/// Lightweight stub for Phase 4 Orchestrator expansion. The Orchestrator
/// will add preset assignments and transition timing per track.
public struct SessionPlan: Sendable {

    /// Ordered list of tracks in the session.
    public let tracks: [TrackIdentity]

    public init(tracks: [TrackIdentity]) {
        self.tracks = tracks
    }
}

// MARK: - PreviewAudio

/// Raw PCM audio decoded from a 30-second preview clip.
///
/// Produced by `PreviewDownloader` and consumed by `SessionPreparer` as the
/// input for stem separation and MIR analysis. All samples are mono Float32,
/// converted from the original stereo AAC/MP3 by averaging channels.
public struct PreviewAudio: Sendable {

    // MARK: - Properties

    /// The track this audio was downloaded for.
    public let trackIdentity: TrackIdentity

    /// Mono Float32 PCM samples, averaged from all source channels.
    public let pcmSamples: [Float]

    /// Sample rate of the decoded audio in Hz (typically 44100).
    public let sampleRate: Int

    /// Duration of the decoded audio in seconds.
    public let duration: TimeInterval

    // MARK: - Init

    /// Create a `PreviewAudio` value.
    ///
    /// - Parameters:
    ///   - trackIdentity: The track this audio corresponds to.
    ///   - pcmSamples: Mono Float32 PCM samples.
    ///   - sampleRate: Sample rate in Hz.
    ///   - duration: Duration in seconds.
    public init(
        trackIdentity: TrackIdentity,
        pcmSamples: [Float],
        sampleRate: Int,
        duration: TimeInterval
    ) {
        self.trackIdentity = trackIdentity
        self.pcmSamples = pcmSamples
        self.sampleRate = sampleRate
        self.duration = duration
    }

    // MARK: - Local-file decode (LF.2 / LF.3)

    /// Decode a local audio file to a mono `PreviewAudio` value via
    /// `AVAudioFile`. Stereo (and higher-channel) inputs are averaged
    /// to mono. The returned `PreviewAudio` carries a synthetic
    /// `TrackIdentity` keyed by the SHA-256 content hash of the file
    /// (`spotifyID = "local:sha256:" + hash`) — renamed/moved copies of
    /// the same bytes hit cache, and the identity is independent of
    /// any path that may rotate across launches.
    ///
    /// Used by the LF.2/LF.3 path
    /// (`VisualizerEngine.prepareAndStartLocalFilePlayback(url:)`) and
    /// by `LocalFilePlaybackFormatCoverageTests` to exercise the
    /// decode + offline-analysis pipeline against MP3 / FLAC / M4A
    /// fixtures.
    ///
    /// - Parameters:
    ///   - url: Local audio file to decode.
    ///   - contentHash: Pre-computed SHA-256 hex string (lowercase) of
    ///     the file. When `nil`, computed inline via
    ///     `PreviewAudio.sha256(of:)`. Callers that already need the
    ///     hash for cache lookup should pass it through to avoid the
    ///     second full-file read.
    public static func fromLocalFile(at url: URL, contentHash: String? = nil) throws -> PreviewAudio {
        let resolvedHash: String
        if let contentHash {
            resolvedHash = contentHash
        } else {
            resolvedHash = try sha256(of: url)
        }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else {
            throw LocalFileDecodeError.emptyFile
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LocalFileDecodeError.bufferAllocationFailed
        }
        try file.read(into: buffer)

        let actualFrames = Int(buffer.frameLength)
        guard actualFrames > 0, let channelData = buffer.floatChannelData else {
            throw LocalFileDecodeError.emptyDecodedBuffer
        }
        let channelCount = Int(format.channelCount)

        var samples: [Float]
        if channelCount == 1 {
            samples = Array(UnsafeBufferPointer(start: channelData[0], count: actualFrames))
        } else {
            samples = [Float](repeating: 0, count: actualFrames)
            let scale = 1.0 / Float(channelCount)
            for ch in 0..<channelCount {
                let ptr = UnsafeBufferPointer(start: channelData[ch], count: actualFrames)
                for i in 0..<actualFrames {
                    samples[i] += ptr[i] * scale
                }
            }
        }

        let sampleRate = Int(format.sampleRate)
        let duration = TimeInterval(actualFrames) / format.sampleRate

        let identity = TrackIdentity(
            title: url.lastPathComponent,
            artist: "local file",
            duration: duration,
            spotifyID: "local:sha256:" + resolvedHash
        )

        return PreviewAudio(
            trackIdentity: identity,
            pcmSamples: samples,
            sampleRate: sampleRate,
            duration: duration
        )
    }

    /// Compute the SHA-256 hex digest of a file's bytes for content-
    /// hash-based cache lookup (LF.3).
    ///
    /// Reads the file in one pass via `Data(contentsOf:)` (memory-mapped
    /// where the OS permits). Caller is responsible for dispatching
    /// off-main when the file is large — for a 5 MB AAC, the hash is
    /// ~30 ms on M2 Pro; for a 50 MB lossless file, ~200 ms.
    ///
    /// Returned hex is lowercase and matches `shasum -a 256 <file>` exactly.
    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - LocalFileDecodeError

/// Failures specific to `PreviewAudio.fromLocalFile(at:)`. Distinct
/// from `PreviewDownloader` errors because the LF path opens the file
/// directly off-disk rather than going through the network → temp-file
/// → AVAudioFile pattern.
public enum LocalFileDecodeError: Error, Sendable {
    case emptyFile
    case bufferAllocationFailed
    case emptyDecodedBuffer
}
