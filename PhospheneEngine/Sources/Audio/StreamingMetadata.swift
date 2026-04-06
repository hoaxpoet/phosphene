// StreamingMetadata — Polls system Now Playing state for track changes.
// Uses the MediaRemote private framework to read other apps' Now Playing
// info (Spotify, Apple Music, etc.). MPNowPlayingInfoCenter only exposes
// the host app's own metadata — MediaRemote reads the system-wide state.
// Conforms to MetadataProviding for dependency injection.

import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - NowPlayingInfo

/// Parsed Now Playing info in a Sendable form.
/// Used by both MediaRemoteBridge (production) and tests (injected).
public struct NowPlayingInfo: Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: Double?

    public init(title: String?, artist: String?, album: String?, duration: Double?) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

// MARK: - MediaRemote Bridge

/// Dynamically loaded interface to MediaRemote.framework.
///
/// MediaRemote is a private framework that provides system-wide Now Playing
/// information. We load it dynamically to avoid linking against private APIs
/// at build time. The app sandbox is already disabled for Core Audio taps,
/// so this works without additional entitlements.
private enum MediaRemoteBridge {

    /// Dictionary keys used by MediaRemote for Now Playing info.
    static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let durationKey = "kMRMediaRemoteNowPlayingInfoDuration"

    /// Function signature for MRMediaRemoteGetNowPlayingInfo.
    private typealias GetNowPlayingInfoFunc = @convention(c) (
        DispatchQueue,
        @escaping ([String: Any]) -> Void
    ) -> Void

    /// Cached function pointer — loaded once on first access.
    private static let getNowPlayingInfo: GetNowPlayingInfoFunc? = {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework"
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: path)) else {
            logger.error("Failed to load MediaRemote.framework")
            return nil
        }
        guard let pointer = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString
        ) else {
            logger.error("Failed to find MRMediaRemoteGetNowPlayingInfo")
            return nil
        }
        return unsafeBitCast(pointer, to: GetNowPlayingInfoFunc.self)
    }()

    /// Serial queue for MediaRemote callbacks — avoids main queue
    /// deadlocks when called from Swift concurrency tasks.
    private static let callbackQueue = DispatchQueue(label: "com.phosphene.mediaremote")

    /// Query the system-wide Now Playing info asynchronously.
    /// Returns nil if MediaRemote is unavailable or nothing is playing.
    static func fetchNowPlayingInfo() async -> NowPlayingInfo? {
        guard let fn = getNowPlayingInfo else { return nil }

        return await withCheckedContinuation { continuation in
            fn(callbackQueue) { info in
                if info.isEmpty {
                    continuation.resume(returning: nil)
                } else {
                    let parsed = NowPlayingInfo(
                        title: info[titleKey] as? String,
                        artist: info[artistKey] as? String,
                        album: info[albumKey] as? String,
                        duration: info[durationKey] as? Double
                    )
                    continuation.resume(returning: parsed)
                }
            }
        }
    }
}

// MARK: - StreamingMetadata

/// Observes system-wide Now Playing metadata and detects track changes.
///
/// Polls MediaRemote at a 2-second interval. When the playing track
/// identity changes (title + artist), fires `onTrackChange`.
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

    /// Override this closure in tests to inject canned Now Playing info.
    /// Defaults to querying MediaRemote for system-wide Now Playing state.
    var nowPlayingReader: (@Sendable () async -> NowPlayingInfo?)? = nil

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
            logger.info("Started observing Now Playing metadata via MediaRemote")

            while !Task.isCancelled {
                await self.pollNowPlaying()

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

    private func pollNowPlaying() async {
        let info: NowPlayingInfo?
        if let reader = nowPlayingReader {
            info = await reader()
        } else {
            info = await MediaRemoteBridge.fetchNowPlayingInfo()
        }

        guard let info else {
            lock.withLock {
                _currentTrack = nil
                lastTrackIdentity = nil
            }
            return
        }

        let title = info.title
        let artist = info.artist
        let album = info.album
        let duration = info.duration

        let identity = trackIdentity(title: title, artist: artist)

        let track = TrackMetadata(
            title: title,
            artist: artist,
            album: album,
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
