// DefaultPlaybackActionRouter — App-layer stub implementation of PlaybackActionRouter.
//
// All live-adaptation methods are stubs that log TODO(U.6b) markers.
// toggleMoodLock() is the one non-stub: it toggles a published Bool and the
// live adapter will read it in U.6b.
//
// U.6b semantic specs (carried here for the implementor):
//
//   moreLikeThis():
//     Extend current preset by 30 s in livePlan. Apply a +0.3 additive
//     bias to the family weight in PresetScoringContext for all remaining
//     tracks. Emit a liveAdaptationAck toast: "More like this — [family]".
//
//   lessLikeThis():
//     Schedule an early-out at next structural boundary (or 8 s).
//     Exclude the current family for 10 minutes via a time-stamped penalty
//     in DefaultPresetScorer. Emit ack toast: "Skipping [family] for 10 min".
//
//   reshuffleUpcoming():
//     Call engine.regeneratePlan(lockedTracks: alreadyPlayed, lockedPresets: []).
//     Emit ack toast: "Plan reshuffled from next track".
//
//   presetNudge(_ direction:, immediate:):
//     Build a scored ranking of presets eligible for this track. Advance
//     rank index by +1 (next) or -1 (previous). If immediate: force a cut
//     on the next frame via RenderPipeline.forcePresetSwitch(). Else: schedule
//     the switch at the next predicted structural boundary. Emit ack toast.
//
//   rePlanSession():
//     Call engine.regeneratePlan(lockedTracks: [], lockedPresets: [:]).
//     Preserves current preset for the active track by immediately applying
//     the current preset as the first override. Emit ack toast.
//
//   undoLastAdaptation():
//     Pop the undo stack (PlannedSession snapshots, ≥5 entries).
//     Restore livePlan to the previous snapshot. Emit ack toast.

import Foundation
import Orchestrator
import os.log
import Session

private let logger = Logger(subsystem: "com.phosphene.app", category: "PlaybackActionRouter")

// MARK: - DefaultPlaybackActionRouter

/// Concrete PlaybackActionRouter for U.6. Live-adaptation methods are stubs.
@MainActor
final class DefaultPlaybackActionRouter: PlaybackActionRouter, @unchecked Sendable {

    // MARK: - Mood Lock (non-stub)

    @Published private(set) var isMoodLocked: Bool = false

    // MARK: - SessionManager (for toggleMoodLock side-effects in U.6b)

    private weak var sessionManager: SessionManager?

    // MARK: - Init

    init(sessionManager: SessionManager? = nil) {
        self.sessionManager = sessionManager
    }

    // MARK: - PlaybackActionRouter (stubs)

    func moreLikeThis() {
        logger.info("moreLikeThis — TODO(U.6b): boost family weight, extend preset 30s")
    }

    func lessLikeThis() {
        logger.info("lessLikeThis — TODO(U.6b): exclude family 10 min, early-out at boundary")
    }

    func reshuffleUpcoming() {
        logger.info("reshuffleUpcoming — TODO(U.6b): re-run planner preserving elapsed tracks")
    }

    func presetNudge(_ direction: NudgeDirection, immediate: Bool) {
        logger.info("presetNudge \(direction.rawValue) immediate:\(immediate) — TODO(U.6b)")
    }

    func rePlanSession() {
        logger.info("rePlanSession — TODO(U.6b): re-plan from start, preserve active track")
    }

    func undoLastAdaptation() {
        logger.info("PlaybackActionRouter.undoLastAdaptation() — TODO(U.6b): pop PlannedSession undo stack (≥5 entries)")
    }

    // MARK: - toggleMoodLock (non-stub)

    func toggleMoodLock() {
        isMoodLocked.toggle()
        logger.info("PlaybackActionRouter: moodLock = \(self.isMoodLocked)")
        // TODO(U.6b): plumb isMoodLocked into DefaultLiveAdapter.adapt() to gate mood-override path.
    }
}
