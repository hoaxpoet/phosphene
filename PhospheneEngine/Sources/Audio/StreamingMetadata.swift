// StreamingMetadata — Polls running music apps for track changes.
// Uses AppleScript to query Apple Music and Spotify directly.
// MediaRemote private framework is blocked for signed apps on macOS 15+.
// Conforms to MetadataProviding for dependency injection.

import AppKit
import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - NowPlayingInfo

/// Parsed Now Playing info in a Sendable form.
public struct NowPlayingInfo: Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: Double?
    public let source: MetadataSource

    public init(title: String?, artist: String?, album: String?, duration: Double?, source: MetadataSource = .nowPlaying) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.source = source
    }
}

// MARK: - AppleScript Bridge

/// Queries running music apps via AppleScript for Now Playing info.
///
/// AppleScript works reliably from signed apps via the Automation framework.
/// Each target app triggers a one-time permission prompt. Supports Apple Music
/// and Spotify. Falls back gracefully if neither is running.
private enum AppleScriptBridge {

    /// Query Apple Music for the current track.
    static func queryAppleMusic() -> NowPlayingInfo? {
        let script = """
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & (trackDuration as text)
            end if
        end tell
        """
        return executeScript(script, appName: "Music", source: .appleMusic)
    }

    /// Query Spotify for the current track.
    static func querySpotify() -> NowPlayingInfo? {
        let script = """
        tell application "Spotify"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & ((trackDuration / 1000) as text)
            end if
        end tell
        """
        return executeScript(script, appName: "Spotify", source: .spotify)
    }

    /// Check if an app is running without launching it.
    static func isAppRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Execute an AppleScript and parse the result.
    private static func executeScript(_ source: String, appName: String, source metadataSource: MetadataSource) -> NowPlayingInfo? {
        guard let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -600 = app not running, -1728 = no current track — both expected.
            if code != -600 && code != -1728 {
                logger.debug("AppleScript error for \(appName): \(error[NSAppleScript.errorMessage] as? String ?? "unknown")")
            }
            return nil
        }

        guard let output = result.stringValue else { return nil }
        let parts = output.components(separatedBy: "||")
        guard parts.count >= 4 else { return nil }

        return NowPlayingInfo(
            title: parts[0].isEmpty ? nil : parts[0],
            artist: parts[1].isEmpty ? nil : parts[1],
            album: parts[2].isEmpty ? nil : parts[2],
            duration: Double(parts[3]),
            source: metadataSource
        )
    }

    /// Query all supported music apps, returning the first hit.
    static func queryNowPlaying() -> NowPlayingInfo? {
        // Check Apple Music first (most common on macOS).
        if isAppRunning("com.apple.Music") {
            if let info = queryAppleMusic() {
                return info
            }
        }

        // Then Spotify.
        if isAppRunning("com.spotify.client") {
            if let info = querySpotify() {
                return info
            }
        }

        return nil
    }
}

// MARK: - StreamingMetadata

/// Observes running music apps and detects track changes.
///
/// Polls Apple Music and Spotify via AppleScript at a 2-second interval.
/// When the playing track identity changes (title + artist), fires `onTrackChange`.
/// All metadata is optional — gracefully handles no music app running.
public final class StreamingMetadata: MetadataProviding, @unchecked Sendable {

    // MARK: - State

    private var pollingTask: Task<Void, Never>?
    private var _currentTrack: TrackMetadata?
    private var lastTrackIdentity: String?
    private let lock = NSLock()

    /// Polling interval.
    private let pollInterval: Duration

    // MARK: - Testability

    /// Override this closure in tests to inject canned Now Playing info.
    /// Defaults to querying music apps via AppleScript.
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
            logger.info("Started observing Now Playing metadata via AppleScript")

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
            // AppleScript is synchronous — run off the cooperative pool.
            info = await Task.detached {
                AppleScriptBridge.queryNowPlaying()
            }.value
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
            source: info.source
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
