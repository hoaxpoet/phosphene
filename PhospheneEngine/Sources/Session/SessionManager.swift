// SessionManager — Session lifecycle state machine.
// Coordinates PlaylistConnector, SessionPreparer, and StemCache.
// Owns the idle → connecting → preparing → ready → playing → ended lifecycle.

import Combine
import Foundation
import os.log

private let logger = Logging.session

// MARK: - SessionManager

/// Owns the Phosphene session lifecycle.
///
/// In **session mode**, call `startSession(source:)` before playback begins.
/// The manager connects to the playlist, pre-analyzes every track via
/// `SessionPreparer`, and transitions to `.ready`. Call `beginPlayback()`
/// once the user starts their streaming app. The populated `StemCache` is
/// available via `cache` and should be wired to `VisualizerEngine.stemCache`
/// before the first track change.
///
/// In **ad-hoc mode**, call `startAdHocSession()` to skip preparation and
/// transition directly to `.playing`. The engine operates in reactive mode —
/// real-time stem separation fills in after ~10 seconds per track.
@MainActor
public final class SessionManager: ObservableObject {

    // MARK: - Published State

    /// Current session lifecycle state.
    @Published public private(set) var state: SessionState = .idle

    /// The planned session — available after `.ready` or `.playing`.
    /// `nil` in ad-hoc mode and before preparation completes.
    @Published public private(set) var currentPlan: SessionPlan?

    /// The playlist source that originated this session.
    /// Set at `startSession(source:)` entry; nil in ad-hoc mode.
    @Published public private(set) var sessionSource: PlaylistSource?

    /// Tracks currently being prepared. Set when entering `.preparing`.
    /// Cleared when leaving `.preparing` (success, failure, or cancel).
    @Published public private(set) var preparingTracks: [TrackIdentity] = []

    // MARK: - Dependencies

    private let connector: any PlaylistConnecting
    private let preparer: SessionPreparer

    // MARK: - Cancellation

    private var cancellationRequested = false

    // MARK: - Cache

    /// The populated stem cache. Valid after state == `.ready`.
    ///
    /// Wire to `VisualizerEngine.stemCache` before the first track change
    /// so each track loads pre-separated stems immediately on track change.
    public var cache: StemCache { preparer.cache }

    // MARK: - Progress

    /// Per-track preparation progress publisher. Non-nil during `.preparing`.
    ///
    /// Expose to `PreparationProgressView` so it can observe status transitions
    /// without needing access to `SessionPreparer` internals.
    public var preparationProgress: (any PreparationProgressPublishing)? { preparer }

    // MARK: - Init

    /// Create a session manager.
    ///
    /// - Parameters:
    ///   - connector: Reads the ordered playlist from Apple Music or Spotify.
    ///   - preparer: Runs batch stem separation + MIR on 30-second preview clips.
    public init(
        connector: any PlaylistConnecting,
        preparer: SessionPreparer
    ) {
        self.connector = connector
        self.preparer = preparer
    }

    // MARK: - Lifecycle

    /// Start a playlist session.
    ///
    /// Transitions: `.idle`/`.ended` → `.connecting` → `.preparing` → `.ready`.
    ///
    /// Degradation:
    /// - Connection failure → `.ready` with empty plan (live-only reactive mode).
    /// - Partial preparation failure → `.ready` with whichever tracks were cached.
    /// - User cancel during `.preparing` → `.idle` (via `cancel()`).
    ///
    /// A no-op when state is already `.connecting`, `.preparing`, `.ready`,
    /// or `.playing`.
    ///
    /// - Parameter source: The playlist source to connect to.
    public func startSession(source: PlaylistSource) async {
        sessionSource = source
        guard state == .idle || state == .ended else {
            let state = self.state.rawValue
            logger.info("SessionManager: ignoring startSession (state=\(state))")
            return
        }

        cancellationRequested = false
        state = .connecting
        logger.info("SessionManager: connecting")

        let tracks: [TrackIdentity]
        do {
            tracks = try await connector.connect(source: source)
            logger.info("SessionManager: connected — \(tracks.count) track(s)")
        } catch {
            logger.info("SessionManager: connection failed (\(error)) — degrading to empty plan")
            currentPlan = SessionPlan(tracks: [])
            state = .ready
            return
        }

        preparingTracks = tracks
        state = .preparing
        logger.info("SessionManager: preparing \(tracks.count) track(s)")

        let result = await preparer.prepare(tracks: tracks)

        // Guard: cancel() may have fired during prepare; state is already .idle.
        guard !cancellationRequested else {
            preparingTracks = []
            logger.info("SessionManager: preparation cancelled — staying .idle")
            return
        }

        preparingTracks = []
        let allTracks = result.cachedTracks + result.failedTracks
        currentPlan = SessionPlan(tracks: allTracks)
        state = .ready
        logger.info("SessionManager: ready — \(result.cachedTracks.count)/\(allTracks.count) cached")
    }

    /// Start an ad-hoc session without a connected playlist.
    ///
    /// Transitions `.idle`/`.ended` → `.playing` directly. No preview
    /// downloads or stem pre-analysis — the engine operates in live-only
    /// reactive mode. A no-op for any other current state.
    public func startAdHocSession() {
        guard state == .idle || state == .ended else { return }
        state = .playing
        logger.info("SessionManager: ad-hoc session started — reactive mode only")
    }

    /// Signal that the user has started playback.
    ///
    /// Transitions `.ready` → `.playing`. A no-op for any other state.
    public func beginPlayback() {
        guard state == .ready else {
            let state = self.state.rawValue
            logger.info("SessionManager: ignoring beginPlayback (state=\(state))")
            return
        }
        state = .playing
        logger.info("SessionManager: playback started")
    }

    /// Cancel the current operation and return to `.idle`.
    ///
    /// Safe to call from any state. During `.preparing`, cancels the in-flight
    /// preparation pass (current track may finish its MPSGraph predict — ≤ 142 ms).
    /// Transitions state to `.idle` immediately; `startSession` detects the
    /// cancellation flag and returns without setting `.ready`.
    ///
    /// A no-op when state is already `.idle`.
    public func cancel() {
        guard state != .idle else { return }
        cancellationRequested = true
        preparer.cancelPreparation()
        preparingTracks = []
        state = .idle
        logger.info("SessionManager: cancelled — returning to .idle")
    }

    /// End the current session.
    ///
    /// Transitions any state → `.ended`. Safe to call at any point.
    public func endSession() {
        state = .ended
        logger.info("SessionManager: session ended")
    }
}
