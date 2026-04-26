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
        preparer: SessionPreparer
    ) {
        self.connector = connector
        self.preparer = preparer
    }

    // MARK: - Lifecycle

    // swiftlint:disable function_body_length
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
    // swiftlint:enable function_body_length

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

    // MARK: - Progressive Readiness Computation

    // swiftlint:disable cyclomatic_complexity
    /// Compute the progressive readiness level from the current track statuses.
    ///
    /// Rules (D-056):
    /// - `.partial` tracks count toward the consecutive prefix only when their cached
    ///   `TrackProfile` has a non-nil BPM **and** at least one genre tag.
    /// - A `.failed` track (or any in-flight track) in the prefix breaks the run.
    /// - `fullyPrepared` requires every track to be in a terminal state
    ///   (`.ready`, `.partial`, or `.failed`) with at least one usable track.
    /// - `reactiveFallback` when all terminal tracks are `.failed` (nothing to plan).
    public static func computeReadiness(
        statuses: [TrackIdentity: TrackPreparationStatus],
        trackList: [TrackIdentity],
        cache: StemCache
    ) -> ProgressiveReadinessLevel {
        guard !trackList.isEmpty else { return .reactiveFallback }

        let threshold = defaultProgressiveReadinessThreshold
        let total = trackList.count

        var prefixCount = 0
        var prefixBroken = false
        var readyCount = 0       // .ready or .partial
        var allTerminal = true

        for track in trackList {
            let status = statuses[track] ?? .queued

            let isTerminal: Bool
            switch status {
            case .ready, .partial, .failed: isTerminal = true
            default:                        isTerminal = false
            }
            if !isTerminal { allTerminal = false }

            let isReady: Bool
            switch status {
            case .ready, .partial: isReady = true
            default:               isReady = false
            }
            if isReady { readyCount += 1 }

            // Prefix: consecutive qualifying tracks from position 1.
            if !prefixBroken {
                let countsForPrefix: Bool
                switch status {
                case .ready:
                    countsForPrefix = true
                case .partial:
                    if let profile = cache.trackProfile(for: track),
                       profile.bpm != nil,
                       !profile.genreTags.isEmpty {
                        countsForPrefix = true
                    } else {
                        countsForPrefix = false
                    }
                default:
                    countsForPrefix = false
                }
                if countsForPrefix { prefixCount += 1 } else { prefixBroken = true }
            }
        }

        if allTerminal && readyCount == 0 { return .reactiveFallback }
        if allTerminal { return .fullyPrepared }
        if prefixCount < threshold { return .preparing }

        let readyPercent = Double(readyCount) / Double(total)
        return readyPercent >= 0.5 ? .partiallyPlanned : .readyForFirstTracks
    }
    // swiftlint:enable cyclomatic_complexity
}
