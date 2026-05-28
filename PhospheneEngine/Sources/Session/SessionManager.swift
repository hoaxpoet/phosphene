// swiftlint:disable file_length
// SessionManager — Session lifecycle state machine.
// Coordinates PlaylistConnector, SessionPreparer, and StemCache.
// Owns the idle → connecting → preparing → ready → playing → ended lifecycle.
//
// LF.4 (D-131) added startLocalFile(at:) + _completeLocalFileReady; both
// need to write to multiple `@Published private(set)` properties, which
// can't be done from an extension in a separate file. The file_length
// disable above is the tracked acknowledgement — splitting requires
// internal setter helpers which add more lines than they save.
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

    /// LF.5.fix.3-A: monotonic counter incremented by every
    /// `startLocalFiles(at:origin:)` entry. Each call captures the value
    /// pre-await; post-await it bails when the field has advanced (a newer
    /// call has superseded this one). Replaces the broken `cancellationRequested`
    /// post-await check — `_beginMultiFileTransition` resets that flag to
    /// false for the newer call, so an older suspended call always saw false
    /// and proceeded into `_completeLocalFilesReady` with a partial,
    /// cancelled-prep plan (session 2026-05-28T20-57-46Z line 19: A's
    /// 2-of-200 partial plan transitioned to .ready after B took over).
    private var localFileSessionGen: UInt64 = 0

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
    /// Thin wrapper around `startLocalFiles(at:origin:)` (LF.5 / D-132) so the
    /// LF.4 menu / drag-and-drop / env-var entry points keep working with no
    /// behaviour change. See `startLocalFiles(at:origin:)` for the lifecycle.
    ///
    /// - Parameter url: Local audio file URL. Caller must verify the file
    ///   exists and is readable before calling.
    public func startLocalFile(at url: URL) async {
        await startLocalFiles(at: [url], origin: .localFile(url))
    }

    /// Start a multi-file local playback session (LF.5 / D-132).
    ///
    /// Sibling to the streaming-path `startSession(...)` API but driven by a
    /// pre-resolved URL queue instead of a `PlaylistConnecting`. Walks the URL
    /// list sequentially via the `LocalFilePreparing` delegate, populates
    /// `preparingTracks` with one identity per file (placeholder before per-file
    /// preparation, real `local:sha256:<hash>` identity after), advances
    /// `progressiveReadinessLevel` as terminal-ready entries accumulate, and
    /// transitions:
    ///
    ///     `.idle / .ended` → `.preparing` → `.ready`
    ///
    /// The `VisualizerEngine` `.ready` observer installs the first track's
    /// cached `BeatGrid`, starts the LF audio router, and calls `beginPlayback()`
    /// to transition `.ready → .playing`. Mid-session advance to subsequent
    /// queue entries happens in `VisualizerEngine.advanceLocalFileQueue()` (LF.5
    /// Task 8) when the audio router reports end-of-file.
    ///
    /// Same-origin re-entry (identical URL list AND identical `SessionOrigin`
    /// shape) is a no-op. Any other active session is silently replaced via
    /// `cancel()` first (macOS-idiomatic).
    ///
    /// Per Matt's audit sign-off (2026-05-27), callers above this layer should
    /// truncate large queues to ≤ 200 URLs to avoid cache-eviction churn under
    /// the 500 MB cap (~70 cached tracks); the menu / drop handlers in
    /// `LocalFileMenuCommands` enforce that ceiling.
    ///
    /// - Parameters:
    ///   - urls: Ordered list of local audio file URLs. Caller verifies
    ///     readability + extension before passing. Empty list is a no-op
    ///     (logged warning, state unchanged).
    ///   - origin: The `SessionOrigin` to publish. UI uses this for source-aware
    ///     labels — `.localFolder` shows folder name, `.localPlaylist` shows
    ///     M3U filename, `.localFiles` shows track count, `.localFile` shows
    ///     filename.
    public func startLocalFiles(at urls: [URL], origin: SessionOrigin) async {
        guard !urls.isEmpty else {
            logger.warning("SessionManager: startLocalFiles called with empty URL list — no-op")
            return
        }
        if _shouldShortCircuitMultiFileEntry(origin: origin) { return }
        if state != .idle && state != .ended {
            logger.info("SessionManager: startLocalFiles — replacing active session")
            cancel()
        }
        // LF.5.fix.3-A: capture our generation BEFORE _beginMultiFileTransition.
        // `cancellationRequested` was the prior gate but that flag is reset to
        // false inside `_beginMultiFileTransition`, so an older suspended call
        // resuming after a newer call's transition would always see false and
        // proceed. The generation counter is monotonic and assignment-only,
        // so a stale value is unambiguous evidence of supersession.
        localFileSessionGen &+= 1
        let myGen = localFileSessionGen
        _beginMultiFileTransition(urls: urls, origin: origin)

        let placeholders = preparingTracks
        let result = await preparer.prepareLocalFiles(
            urls: urls,
            placeholders: placeholders,
            via: localFilePreparer
        )

        // LF.5.fix.3-A: bail when superseded by a newer startLocalFiles call.
        // (See `localFileSessionGen` doc above.) A still-pending older call
        // must not drive the .ready transition with its now-cancelled prep
        // result — that's the Bug A in the 2026-05-28T20-57-46Z session log
        // (folder A's partial 2-of-200 plan transitioned to .ready after
        // folder B was already in flight).
        if localFileSessionGen != myGen {
            logger.info(
                "SessionManager: startLocalFiles superseded (gen=\(myGen) currentGen=\(self.localFileSessionGen)) — discarding result"
            )
            return
        }
        if cancellationRequested {
            logger.info("SessionManager: startLocalFiles cancelled before .ready transition")
            return
        }

        // Combine the prepared `local:sha256:` identities with any failed
        // placeholders (LF.1 fallthrough rows) into a single plan. Order
        // matches the original URL queue because the preparer walks in order.
        let allTracks = result.cachedTracks + result.failedTracks
        _completeLocalFilesReady(tracks: allTracks)
    }

    /// Same-origin re-entry guard. Returns `true` when the in-flight session
    /// already matches the requested origin and the caller should bail out.
    private func _shouldShortCircuitMultiFileEntry(origin: SessionOrigin) -> Bool {
        if let active = currentSource, active == origin,
           state == .preparing || state == .ready || state == .playing {
            logger.info("SessionManager: startLocalFiles ignored — same origin already active")
            return true
        }
        return false
    }

    /// Shared entry transition for `startLocalFiles(at:origin:)`: clears the
    /// cancellation flag, seeds placeholder identities, flips state to
    /// `.preparing`, and emits the WIRING breadcrumb.
    private func _beginMultiFileTransition(urls: [URL], origin: SessionOrigin) {
        cancellationRequested = false
        sessionSource = nil
        currentSource = origin
        let placeholders = urls.map { Self.makePlaceholderIdentity(url: $0) }
        preparingTracks = placeholders
        progressiveReadinessLevel = .preparing
        state = .preparing
        let firstName = urls.first?.lastPathComponent ?? "?"
        logger.info(
            "SessionManager: preparing \(urls.count) local file(s) — first='\(firstName, privacy: .public)'"
        )
        let openMsg = "WIRING: SessionManager.startLocalFiles ENTER " +
            "count=\(urls.count) first='\(firstName)' origin=\(Self.originLabel(origin))"
        sessionRecorder?.log(openMsg)
    }

    /// Shared transition into `.ready` for the LF.5 multi-file path. Writes the
    /// `SessionPlan`, advances `progressiveReadinessLevel`, clears
    /// `preparingTracks`, and flips state.
    @MainActor
    private func _completeLocalFilesReady(tracks: [TrackIdentity]) {
        currentPlan = SessionPlan(tracks: tracks)
        progressiveReadinessLevel = .fullyPrepared
        preparingTracks = []
        state = .ready
        logger.info("SessionManager: local files ready — \(tracks.count) track(s)")
        let readyMsg = "WIRING: SessionManager.startLocalFiles→ready " +
            "count=\(tracks.count)"
        sessionRecorder?.log(readyMsg)
    }

    /// Synthesise the LF.5 placeholder identity for a local file URL. Used both
    /// by `startLocalFiles` (initial seed) and as a fallback when the
    /// `LocalFilePreparing` delegate returns `nil` for a file.
    private static func makePlaceholderIdentity(url: URL) -> TrackIdentity {
        TrackIdentity(
            title: url.lastPathComponent,
            artist: "local file",
            duration: 0,
            spotifyID: "local:" + url.path
        )
    }

    /// Compact log label for a `SessionOrigin`. Used in `WIRING:` breadcrumbs to
    /// discriminate the four LF entry shapes (`localFile`, `localFiles`,
    /// `localFolder`, `localPlaylist`) without dumping the full URL list.
    private static func originLabel(_ origin: SessionOrigin) -> String {
        switch origin {
        case .playlist: return "playlist"
        case .localFile: return "localFile"
        case .localFiles(let urls): return "localFiles(\(urls.count))"
        case .localFolder(let folder, let expanded):
            return "localFolder('\(folder.lastPathComponent)',\(expanded.count))"
        case .localPlaylist(let playlist, let expanded):
            return "localPlaylist('\(playlist.lastPathComponent)',\(expanded.count))"
        }
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
