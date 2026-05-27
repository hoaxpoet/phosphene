// SessionManager — Session lifecycle state machine.
// Coordinates PlaylistConnector, SessionPreparer, and StemCache.
// Owns the idle → connecting → preparing → ready → playing → ended lifecycle.
//
// Increment 6.1: Progressive Session Readiness.
// startSession() no longer blocks until preparation completes. Instead it:
//   1. Connects to the playlist (awaited — can still fail fast).
//   2. Sets currentPlan from the full track list immediately.
//   3. Subscribes to preparer.$trackStatuses to drive progressiveReadinessLevel.
//   4. Launches preparation as a stored Task and returns (state stays .preparing).
// The UI can call startNow() once progressiveReadinessLevel >= .readyForFirstTracks,
// which transitions .preparing → .ready while preparation continues in the background.
// When preparation completes naturally, .preparing → .ready fires automatically;
// if startNow() was already called the Task just updates currentPlan and readiness.

import Combine
import Foundation
import Shared
import os.log

private let logger = Logging.session

// MARK: - SessionManager

/// Owns the Phosphene session lifecycle.
///
/// In **session mode**, call `startSession(source:)` before playback begins.
/// The manager connects to the playlist and pre-analyzes tracks via `SessionPreparer`,
/// transitioning to `.preparing` immediately. It advances to `.ready` either when the
/// user taps "Start now" (`progressiveReadinessLevel >= .readyForFirstTracks`) or when
/// preparation completes naturally.
///
/// In **ad-hoc mode**, call `startAdHocSession()` to skip preparation and
/// transition directly to `.playing`. The engine operates in reactive mode —
/// real-time stem separation fills in after ~10 seconds per track.
@MainActor
public final class SessionManager: ObservableObject {

    // MARK: - Published State

    /// Current session lifecycle state.
    @Published public private(set) var state: SessionState = .idle

    /// Graduated preparation readiness level. Drives "Start now" CTA availability.
    ///
    /// Starts at `.preparing` when preparation begins. Advances as tracks become ready.
    /// Continues updating through `.ready` and `.playing` until `.fullyPrepared`.
    @Published public private(set) var progressiveReadinessLevel: ProgressiveReadinessLevel = .preparing

    /// The planned session — available after `.ready` or `.playing`.
    /// `nil` in ad-hoc mode and before preparation completes.
    @Published public private(set) var currentPlan: SessionPlan?

    /// The playlist source that originated this session.
    /// Set at `startSession(source:)` entry; nil in ad-hoc mode and in local-file mode.
    @Published public private(set) var sessionSource: PlaylistSource?

    /// What kind of input is driving the current session.
    ///
    /// `.playlist(source)` — set at the start of every `startSession(...)` variant.
    /// `.localFile(url)` — set at the start of `startLocalFile(at:)` (LF.4).
    /// `nil` — `.idle` / `.ended`, or `startAdHocSession()` (pre-LF.4 ad-hoc path,
    /// which has no source at all).
    ///
    /// Consumers that need to know "is this a local-file session" should read
    /// `currentSource?.isLocalFile` rather than tracking a parallel boolean.
    @Published public private(set) var currentSource: SessionOrigin?

    /// Tracks currently being prepared. Set when entering `.preparing`.
    /// Cleared when leaving `.preparing` (success, failure, or cancel).
    @Published public private(set) var preparingTracks: [TrackIdentity] = []

    // MARK: - Dependencies

    private let connector: any PlaylistConnecting
    private let preparer: SessionPreparer

    /// App-layer delegate that owns the heavy ML deps used by
    /// `startLocalFile(at:)`. Wired post-init by `VisualizerEngine` so
    /// the engine can hand SessionManager its `StemSeparator` / analyzer /
    /// classifier / BeatGridAnalyzer / `PersistentStemCache` without
    /// SessionManager itself growing those imports. `nil` in test setups
    /// — `startLocalFile(at:)` then logs + degrades to ad-hoc-like state.
    public weak var localFilePreparer: (any LocalFilePreparing)?

    /// Optional SessionRecorder for `WIRING:` instrumentation logs (BUG-006.1).
    /// Wired through from `VisualizerEngine` so handoff to engine cache attach
    /// is observable in `session.log` for diagnosis.
    private let sessionRecorder: SessionRecorder?

    // MARK: - Cancellation

    private var cancellationRequested = false

    // MARK: - Progressive Readiness

    /// Background preparation task. Non-nil while preparation is in flight.
    private var sessionPreparationTask: Task<Void, Never>?

    /// Retains the trackStatuses subscription during preparation.
    private var statusCancellable: AnyCancellable?

    /// Full ordered track list from the connected playlist. Preserved until session ends.
    private var allSessionTracks: [TrackIdentity] = []

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
        preparer: SessionPreparer,
        sessionRecorder: SessionRecorder? = nil
    ) {
        self.connector = connector
        self.preparer = preparer
        self.sessionRecorder = sessionRecorder
    }

    // MARK: - Lifecycle

    /// Start a playlist session.
    ///
    /// Transitions: `.idle`/`.ended` → `.connecting` → `.preparing`.
    ///
    /// The session then advances to `.ready` via either:
    ///   - The user calling `startNow()` once `progressiveReadinessLevel >= .readyForFirstTracks`.
    ///   - Preparation completing naturally (all tracks processed).
    ///
    /// Degradation:
    /// - Connection failure → `.ready` with `.reactiveFallback` readiness.
    /// - User cancel during `.preparing` → `.idle` (via `cancel()`).
    ///
    /// A no-op when state is already `.connecting`, `.preparing`, `.ready`, or `.playing`.
    ///
    /// - Parameter source: The playlist source to connect to.
    public func startSession(source: PlaylistSource) async {
        sessionSource = source
        currentSource = .playlist(source)
        guard state == .idle || state == .ended else {
            let current = self.state.rawValue
            logger.info("SessionManager: ignoring startSession (state=\(current))")
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
            logger.info("SessionManager: connection failed (\(error)) — degrading to reactive fallback")
            currentPlan = SessionPlan(tracks: [])
            progressiveReadinessLevel = .reactiveFallback
            state = .ready
            return
        }

        await _beginPreparation(tracks: tracks)
    }

    /// Start a playlist session using a pre-fetched track list.
    ///
    /// Used when the app layer has already fetched tracks via an OAuth-aware connector
    /// (e.g. Spotify) and re-fetching via `SessionManager`'s own connector would use
    /// the wrong credentials. Skips the `connecting` phase and goes directly to `.preparing`.
    ///
    /// A no-op when state is already `.connecting`, `.preparing`, `.ready`, or `.playing`.
    ///
    /// - Parameters:
    ///   - tracks: Pre-fetched ordered track list.
    ///   - source: The originating playlist source (stored for session metadata).
    public func startSession(preFetchedTracks tracks: [TrackIdentity], source: PlaylistSource) async {
        sessionSource = source
        currentSource = .playlist(source)
        guard state == .idle || state == .ended else {
            let current = self.state.rawValue
            logger.info("SessionManager: ignoring startSession (state=\(current))")
            return
        }

        cancellationRequested = false
        // BUG-006.1 instrumentation: discriminate the Spotify-pre-fetched path
        // from the standard connector-driven `startSession(source:)` path
        // (hypothesis 1).
        let preFetchMsg = "WIRING: SessionManager.startSession SOURCE=spotifyPreFetched " +
            "preFetchedCount=\(tracks.count)"
        sessionRecorder?.log(preFetchMsg)
        logger.info("\(preFetchMsg, privacy: .public)")
        logger.info("SessionManager: connected (pre-fetched) — \(tracks.count) track(s)")
        await _beginPreparation(tracks: tracks)
    }

    /// Shared preparation entry point used by both `startSession` variants.
    private func _beginPreparation(tracks: [TrackIdentity]) async {
        allSessionTracks = tracks
        preparingTracks = tracks
        currentPlan = SessionPlan(tracks: tracks)     // full list available immediately
        progressiveReadinessLevel = .preparing
        state = .preparing
        logger.info("SessionManager: preparing \(tracks.count) track(s)")

        // Subscribe to per-track status changes to drive progressiveReadinessLevel.
        statusCancellable = preparer.$trackStatuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                guard let self else { return }
                self.progressiveReadinessLevel = Self.computeReadiness(
                    statuses: statuses,
                    trackList: self.allSessionTracks,
                    cache: self.preparer.cache
                )
            }

        // Launch preparation in a stored Task so startSession() can return immediately.
        // cancel() interrupts this Task at stage boundaries (≤ 142 ms granularity).
        let prepTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.preparer.prepare(tracks: tracks)

            guard !self.cancellationRequested else {
                logger.info("SessionManager: preparation cancelled")
                return
            }

            // Final bookkeeping.
            self.statusCancellable?.cancel()
            self.statusCancellable = nil
            self.sessionPreparationTask = nil

            // Update currentPlan with the authoritative final list.
            let allTracks = result.cachedTracks + result.failedTracks
            self.currentPlan = SessionPlan(tracks: allTracks)

            // Recompute from final statuses.
            let finalReadiness = Self.computeReadiness(
                statuses: self.preparer.trackStatuses,
                trackList: self.allSessionTracks,
                cache: self.preparer.cache
            )
            self.progressiveReadinessLevel = finalReadiness

            if self.state == .preparing {
                // BUG-006.1 instrumentation: log the .ready transition with cache
                // size so we can confirm the engine has a populated cache to wire
                // (hypothesis 2 discriminator).
                let readyMsg = "WIRING: SessionManager.startSession→ready " +
                    "cacheTrackCount=\(self.preparer.cache.count)"
                self.sessionRecorder?.log(readyMsg)
                logger.info("\(readyMsg, privacy: .public)")

                // Natural completion path — no startNow() was called.
                self.preparingTracks = []
                self.state = .ready
                logger.info("SessionManager: ready — \(result.cachedTracks.count)/\(allTracks.count) cached")
            } else {
                // startNow() already advanced state; background prep is now done.
                logger.info("SessionManager: background prep complete — \(result.cachedTracks.count)/\(allTracks.count) cached")
            }
        }
        sessionPreparationTask = prepTask
        // Returns here while preparation runs in the background.
    }

    /// Advance from `.preparing` to `.ready` immediately.
    ///
    /// Only valid when `progressiveReadinessLevel >= .readyForFirstTracks`.
    /// The background preparation Task **continues running** so remaining tracks
    /// are cached while the user is listening.
    ///
    /// A no-op when state is not `.preparing` or when the readiness threshold is not met.
    public func startNow() {
        guard state == .preparing,
              progressiveReadinessLevel >= .readyForFirstTracks else {
            logger.info("SessionManager: startNow ignored (state=\(self.state.rawValue))")
            return
        }
        // BUG-006.1 instrumentation: this is the user-driven .ready transition;
        // distinguish it from natural completion above.
        let nowMsg = "WIRING: SessionManager.startSession→ready (startNow) " +
            "cacheTrackCount=\(preparer.cache.count)"
        sessionRecorder?.log(nowMsg)
        logger.info("\(nowMsg, privacy: .public)")
        preparingTracks = []
        state = .ready
        logger.info("SessionManager: startNow — .preparing → .ready (background prep continues)")
    }

    /// Start an ad-hoc session without a connected playlist.
    ///
    /// Transitions `.idle`/`.ended` → `.playing` directly. No preview
    /// downloads or stem pre-analysis — the engine operates in live-only
    /// reactive mode. A no-op for any other current state.
    public func startAdHocSession() {
        guard state == .idle || state == .ended else { return }
        progressiveReadinessLevel = .reactiveFallback
        state = .playing
        logger.info("SessionManager: ad-hoc session started — reactive mode only")
    }

    /// Start a single-file local playback session (LF.4 / D-131).
    ///
    /// Transitions: `.idle`/`.ended` → `.preparing` → `.ready`. The caller
    /// (the `VisualizerEngine` `.ready` observer) is responsible for
    /// installing the cached `BeatGrid` via `resetStemPipeline(for:)`,
    /// starting the LF audio router, and calling `beginPlayback()` to
    /// transition `.ready → .playing`.
    ///
    /// Replace-on-open: if the session is already active in a streaming
    /// or different-file mode, `cancel()` is called first. Same-URL
    /// re-entry is a no-op (avoids re-running pre-analysis when the user
    /// re-picks the same file).
    ///
    /// Preparation work is delegated to `localFilePreparer` (typically
    /// `VisualizerEngine`), which owns the ML deps. When the delegate is
    /// `nil` or returns `nil`, the session still transitions to `.ready` —
    /// playback proceeds without the cached install (LF.1 fallthrough).
    ///
    /// - Parameter url: Local audio file URL. Caller must verify the file
    ///   exists and is readable before calling.
    public func startLocalFile(at url: URL) async {
        // Same-URL re-entry: no-op (avoid re-running pre-analysis when the user
        // re-picks the same file from the menu).
        if let active = currentSource, case .localFile(let activeURL) = active,
           activeURL == url,
           state == .preparing || state == .ready || state == .playing {
            logger.info("SessionManager: startLocalFile ignored — same URL already active")
            return
        }

        // Replace-on-open: if any other session is active, end it cleanly.
        if state != .idle && state != .ended {
            logger.info("SessionManager: startLocalFile — replacing active session")
            cancel()
        }

        cancellationRequested = false
        sessionSource = nil
        currentSource = .localFile(url)
        // Surface a placeholder track in `preparingTracks` so PreparationProgressView
        // renders a row for the duration of the ~2 s analyzePreview window. The
        // synthetic LF identity (with `local:sha256:` prefix) replaces this once
        // the off-main worker resolves the file hash.
        let placeholderIdentity = TrackIdentity(
            title: url.lastPathComponent,
            artist: "local file",
            duration: 0,
            spotifyID: "local:" + url.path
        )
        preparingTracks = [placeholderIdentity]
        progressiveReadinessLevel = .preparing
        state = .preparing
        logger.info("SessionManager: preparing local file \(url.lastPathComponent, privacy: .public)")

        let openMsg = "WIRING: SessionManager.startLocalFile ENTER " +
            "file='\(url.lastPathComponent)'"
        sessionRecorder?.log(openMsg)

        guard let preparer = localFilePreparer else {
            logger.warning("SessionManager: no localFilePreparer wired — degrading to no-cache start")
            _completeLocalFileReady(result: nil, url: url)
            return
        }

        let result = await preparer.prepareLocalFile(url: url)

        guard !cancellationRequested else {
            logger.info("SessionManager: local-file preparation cancelled")
            return
        }

        if let result {
            // Write the cached entry into the shared StemCache so the engine's
            // resetStemPipeline(for:) call on `.ready` finds it via loadForPlayback.
            self.preparer.cache.store(result.cached, for: result.identity)
        }

        _completeLocalFileReady(result: result, url: url)
    }

    /// Shared transition into `.ready` for the LF.4 path. Writes the single-track
    /// `SessionPlan`, advances `progressiveReadinessLevel`, and flips state.
    /// Called both on prep success (cache install will follow on the engine side)
    /// and on prep failure (LF.1 fallthrough — engine starts audio without a
    /// cached install).
    @MainActor
    private func _completeLocalFileReady(result: LocalFilePrepResult?, url: URL) {
        let identity: TrackIdentity
        if let result {
            identity = result.identity
        } else {
            // No prep result — synthesise a placeholder identity. The engine's
            // `resetStemPipeline(for:)` on `.ready` will take the cache-miss
            // branch and the live pipeline catches up after ~10 s.
            identity = TrackIdentity(
                title: url.lastPathComponent,
                artist: "local file",
                duration: 0,
                spotifyID: "local:" + url.path
            )
        }
        preparingTracks = [identity]
        currentPlan = SessionPlan(tracks: [identity])
        progressiveReadinessLevel = .fullyPrepared
        preparingTracks = []
        state = .ready
        let sourceLabel = result?.source.label ?? "noCache"
        logger.info(
            "SessionManager: local file ready (\(sourceLabel, privacy: .public)) — \(url.lastPathComponent, privacy: .public)"
        )
        let readyMsg = "WIRING: SessionManager.startLocalFile→ready " +
            "file='\(url.lastPathComponent)' source=\(sourceLabel)"
        sessionRecorder?.log(readyMsg)
    }

    /// Signal that the user has started playback.
    ///
    /// Transitions `.ready` → `.playing`. A no-op for any other state.
    public func beginPlayback() {
        guard state == .ready else {
            let current = self.state.rawValue
            logger.info("SessionManager: ignoring beginPlayback (state=\(current))")
            return
        }
        state = .playing
        logger.info("SessionManager: playback started")
    }

    /// Cancel the current operation and return to `.idle`.
    ///
    /// Safe to call from any state. During `.preparing`, cancels the in-flight
    /// preparation pass (current track may finish its MPSGraph predict — ≤ 142 ms).
    /// Resume preparation for tracks that previously failed due to network errors.
    ///
    /// Pass-through to `SessionPreparer.resumeFailedNetworkTracks()`. Safe to call
    /// when state is not `.preparing` — the preparer will find no eligible tracks
    /// and return immediately. D-061(d).
    public func resumeFailedNetworkTracks() async {
        await preparer.resumeFailedNetworkTracks()
    }

    /// Transitions state to `.idle` immediately.
    ///
    /// A no-op when state is already `.idle`.
    public func cancel() {
        guard state != .idle else { return }
        cancellationRequested = true
        preparer.cancelPreparation()
        sessionPreparationTask?.cancel()
        sessionPreparationTask = nil
        statusCancellable?.cancel()
        statusCancellable = nil
        preparingTracks = []
        progressiveReadinessLevel = .preparing
        currentSource = nil
        sessionSource = nil
        currentPlan = nil
        state = .idle
        logger.info("SessionManager: cancelled — returning to .idle")
    }

    /// End the current session.
    ///
    /// Transitions any state → `.ended`. Safe to call at any point.
    public func endSession() {
        currentSource = nil
        state = .ended
        logger.info("SessionManager: session ended")
    }

    // Progressive readiness computation lives in `SessionManager+Readiness.swift`.
}
