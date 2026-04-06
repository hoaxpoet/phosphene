// StreamingMetadata — Polls MPNowPlayingInfoCenter for track changes.
// Detects when the currently playing track changes and emits TrackChangeEvent.
// Conforms to MetadataProviding for dependency injection.

import Foundation
import MediaPlayer
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - StreamingMetadata

/// Observes Now Playing metadata and detects track changes.
///
/// Polls `MPNowPlayingInfoCenter` at a 2-second interval. When the
/// playing track identity changes (title + artist), fires `onTrackChange`.
/// All metadata is optional — gracefully handles nil Now Playing state.
public final class StreamingMetadata: MetadataProviding, @unchecked Sendable {

    // MARK: - State

    private var pollingTask: Task<Void, Never>?
    private var _currentTrack: TrackMetadata?
    private var lastTrackIdentity: String?
    private let lock = NSLock()

    /// Polling interval in seconds.
    private let pollInterval: Duration

    // MARK: - Testability

    /// Override this closure in tests to inject canned Now Playing dictionaries.
    /// Defaults to reading from the real `MPNowPlayingInfoCenter`.
    var nowPlayingReader: () -> [String: Any]? = {
        MPNowPlayingInfoCenter.default().nowPlayingInfo
    }

    // MARK: - Init

    /// Create a streaming metadata observer.
    ///
    /// - Parameter pollInterval: How often to check Now Playing (default 2 seconds).
    public init(pollInterval: Duration = .seconds(2)) {
        self.pollInterval = pollInterval
    }

    // MARK: - MetadataProviding

    public var onTrackChange: ((_ event: TrackChangeEvent) -> Void)?

    public var currentTrack: TrackMetadata? {
        lock.withLock { _currentTrack }
    }

    public func startObserving() {
        stopObserving()

        pollingTask = Task { [weak self] in
            guard let self else { return }
            logger.info("Started observing Now Playing metadata")

            while !Task.isCancelled {
                self.pollNowPlaying()

                do {
                    try await Task.sleep(for: self.pollInterval)
                } catch {
                    break
                }
            }
        }
    }

    public func stopObserving() {
        pollingTask?.cancel()
        pollingTask = nil
        lock.withLock {
            _currentTrack = nil
            lastTrackIdentity = nil
        }
        logger.info("Stopped observing Now Playing metadata")
    }

    // MARK: - Polling

    private func pollNowPlaying() {
        let info = nowPlayingReader()

        guard let info else {
            // Nothing playing — clear state but don't fire event.
            // Silence is handled by audio-level heuristics, not metadata.
            lock.withLock {
                _currentTrack = nil
                lastTrackIdentity = nil
            }
            return
        }

        let title = info[MPMediaItemPropertyTitle] as? String
        let artist = info[MPMediaItemPropertyArtist] as? String
        let album = info[MPMediaItemPropertyAlbumTitle] as? String
        let genre = info[MPMediaItemPropertyGenre] as? String
        let duration = info[MPMediaItemPropertyPlaybackDuration] as? Double

        let identity = trackIdentity(title: title, artist: artist)

        let track = TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            duration: duration,
            source: .nowPlaying
        )

        let (shouldFire, previous) = lock.withLock { () -> (Bool, TrackMetadata?) in
            let prev = _currentTrack
            let changed = identity != lastTrackIdentity
            _currentTrack = track
            lastTrackIdentity = identity
            return (changed, prev)
        }

        if shouldFire {
            logger.info("Track change detected: \(track.title ?? "?") — \(track.artist ?? "?")")
            let event = TrackChangeEvent(previous: previous, current: track)
            onTrackChange?(event)
        }
    }

    // MARK: - Identity

    /// Normalized track identity for change detection.
    /// Case-insensitive to avoid spurious events from metadata formatting.
    private func trackIdentity(title: String?, artist: String?) -> String {
        let t = title?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        let a = artist?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        return "\(t)|\(a)"
    }
}
