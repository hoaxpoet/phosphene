// PlaybackActionRouter — Protocol declaring the keyboard-surface live-adaptation actions.
//
// Lives in the Orchestrator module so the contract is defined alongside the types it
// will eventually manipulate (DefaultPresetScorer, DefaultLiveAdapter, DefaultSessionPlanner).
// Concrete implementations live in the app layer (DefaultPlaybackActionRouter).
//
// U.6: all implementations are stubs that log TODO(U.6b) markers.
// U.6b: full semantics — boost family weight, exclude family, nudge at boundary, etc.
//
// Threading: all methods are @MainActor. The router runs on the main thread and may
// dispatch work to background queues as needed by U.6b implementations.

import Foundation

// MARK: - NudgeDirection

/// Which direction to nudge the preset (relative to the current preset in the catalog).
public enum NudgeDirection: String, Sendable {
    case previous
    case next
}

// MARK: - PlaybackActionRouter

/// Declarative contract for in-session live-adaptation keyboard actions.
///
/// One method per user-visible action. Every method is @MainActor — callers
/// on the main thread invoke them directly; the implementations dispatch
/// background work as needed.
///
/// See `docs/ENGINEERING_PLAN.md §U.6b` for the full semantic spec of each stub.
public protocol PlaybackActionRouter: AnyObject, Sendable {

    /// Boost the current preset's family weight for the remaining session.
    ///
    /// U.6b semantic: extends current preset by 30 s and biases scorer toward
    /// the same family for all future tracks in the session.
    @MainActor func moreLikeThis()

    /// Reduce the current preset's family weight for the remaining session.
    ///
    /// U.6b semantic: schedules an early-out at the next structural boundary
    /// (or within 8 s if no boundary is detected) and applies a family-exclusion
    /// penalty for the next 10 minutes.
    @MainActor func lessLikeThis()

    /// Re-plan upcoming tracks with a new random seed, preserving elapsed portion.
    ///
    /// U.6b semantic: calls `DefaultSessionPlanner.plan()` with a fresh seed and
    /// `lockedTracks` covering all already-played tracks. Preserves the current
    /// preset for the active track.
    @MainActor func reshuffleUpcoming()

    /// Nudge to an adjacent preset at the next structural boundary.
    ///
    /// - Parameters:
    ///   - direction: `.previous` or `.next` in scorer-ranked order.
    ///   - immediate: If true, force an immediate cut rather than waiting for a boundary.
    ///
    /// U.6b semantic: schedules the switch in `livePlan` at the next predicted
    /// boundary. If `immediate`, triggers a hard cut on the next render frame.
    @MainActor func presetNudge(_ direction: NudgeDirection, immediate: Bool)

    /// Re-plan the entire session preserving the current preset for this track.
    ///
    /// U.6b semantic: equivalent to `reshuffleUpcoming` but replans from track 0.
    /// Equivalent to pressing "Regenerate" in the plan-preview sheet.
    @MainActor func rePlanSession()

    /// Undo the most recent live-adaptation action.
    ///
    /// U.6b semantic: pops the undo stack (≥5 entries) and restores the previous
    /// `PlannedSession` snapshot.
    @MainActor func undoLastAdaptation()

    /// Toggle the mood-lock gate.
    ///
    /// When locked, the live adapter's mood-override path is disabled — the plan
    /// continues executing even if measured valence/arousal diverges significantly.
    /// Useful when Phosphene mis-classifies the mood of an unusual track.
    @MainActor func toggleMoodLock()

    /// Whether mood lock is currently active. Published so the UI can reflect state.
    @MainActor var isMoodLocked: Bool { get }
}
