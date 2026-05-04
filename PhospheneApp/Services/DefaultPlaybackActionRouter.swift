// swiftlint:disable file_length
// DefaultPlaybackActionRouter — Live-adaptation keyboard action semantics (U.6b).
//
// Architecture note (D-058):
//   Adaptation preference state (familyBoosts, temporaryFamilyExclusions, etc.) lives HERE
//   on the router rather than on VisualizerEngine+Orchestrator. These are user-action
//   preferences, not planner state. Keeping them on the router makes them injectable /
//   testable without requiring a Metal context. The engine reads them back at plan-build
//   time via the `adaptationFields(at:)` snapshot method.
//
// All engine operations are injected as closures at init so that unit tests can supply
// in-memory doubles without a VisualizerEngine (same pattern as PlanPreviewViewModel).

import Combine
import Foundation
import Orchestrator
import os.log
import Presets
import Session
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "PlaybackActionRouter")

// MARK: - AdaptationFields

/// Snapshot of the user-driven adaptation preferences at a given session time.
///
/// Passed to `PresetScoringContextProvider.build(...)` so the planner can honour
/// family boosts and exclusions without a direct reference to the router.
struct AdaptationFields: Sendable {
    let familyBoosts: [PresetCategory: Float]
    let temporarilyExcludedFamilies: Set<PresetCategory>
    let sessionExcludedPresets: Set<String>

    static let empty = AdaptationFields(
        familyBoosts: [:],
        temporarilyExcludedFamilies: [],
        sessionExcludedPresets: []
    )
}

// MARK: - DefaultPlaybackActionRouter

/// Concrete PlaybackActionRouter with full U.6b live-adaptation semantics.
///
/// Adaptation preference state lives here (not on VisualizerEngine) so that
/// tests can verify state mutations without Metal. Engine operations are
/// injected as closures; use the `live(engine:toastBridge:)` factory for the
/// real app and the memberwise init for tests.
@MainActor
final class DefaultPlaybackActionRouter: PlaybackActionRouter, @unchecked Sendable {

    // MARK: - Mood Lock (non-stub, wired in U.6)

    @Published private(set) var isMoodLocked: Bool = false

    // MARK: - U.6b Adaptation Preferences

    /// Additive boost per aesthetic family. Capped at 0.3; pressing `+` twice is idempotent.
    private(set) var familyBoosts: [PresetCategory: Float] = [:]

    /// Family → session-relative expiry (seconds). Pre-filtered to active entries at query time.
    private(set) var temporaryFamilyExclusions: [PresetCategory: TimeInterval] = [:]

    /// Preset IDs excluded by the user for this entire session (survives family-expiry).
    private(set) var sessionExcludedPresets: Set<String> = []

    /// Bounded stack of plan snapshots for undo. Capacity: 8. Push BEFORE every mutation.
    private(set) var adaptationHistory: [PlannedSession] = []
    private static let historyCapacity = 8

    /// Session-relative time of the last `lessLikeThis()` call (for 90s ambient-hint window).
    private(set) var lastNegativeNudgeAt: TimeInterval?

    /// Gate so the double-`-` ambient hint fires at most once per session.
    private(set) var ambientHintShown = false

    /// Preset ID of the preset that was playing before the most recent transition.
    private(set) var lastPlayedPresetID: String?

    // MARK: - Injected Dependencies

    private let sessionManager: SessionManager?
    private let toastBridge: LiveAdaptationToastBridge?
    private var sessionStateCancellable: AnyCancellable?

    // Engine interface closures (injectable for testing)
    private let getSessionTime: () -> TimeInterval
    private let getCurrentPresetID: () -> String?
    private let getCurrentPresetFamily: () -> PresetCategory?
    private let getLivePlan: () -> PlannedSession?
    private let getCatalog: () -> [PresetDescriptor]
    private let getTrackProfile: () -> TrackProfile?
    private let getCurrentTrackIndex: () -> Int
    private let getScoringContext: (AdaptationFields) -> PresetScoringContext
    private let onExtendCurrentPreset: (TimeInterval) -> Void
    private let onReshuffle: (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void
    private let onRePlanSession: () -> Void
    private let onApplyPresetOverride: (String, Bool) -> Void
    private let onRestorePlan: (PlannedSession) -> Void
    private let onShowPlanPreview: () -> Void

    // Ceiling timers for boundary-or-8s transitions.
    private var ceilingTimerTask: Task<Void, Never>?

    // MARK: - Init

    /// Designated init — use closures for injectable testing.
    ///
    /// All closure parameters default to no-ops so the existing
    /// `DefaultPlaybackActionRouter()` calls in tests remain valid.
    init(
        sessionManager: SessionManager? = nil,
        toastBridge: LiveAdaptationToastBridge? = nil,
        getSessionTime: @escaping () -> TimeInterval = { 0 },
        getCurrentPresetID: @escaping () -> String? = { nil },
        getCurrentPresetFamily: @escaping () -> PresetCategory? = { nil },
        getLivePlan: @escaping () -> PlannedSession? = { nil },
        getCatalog: @escaping () -> [PresetDescriptor] = { [] },
        getTrackProfile: @escaping () -> TrackProfile? = { nil },
        getCurrentTrackIndex: @escaping () -> Int = { 0 },
        getScoringContext: @escaping (AdaptationFields) -> PresetScoringContext = { _ in
            .initial(deviceTier: .tier1)
        },
        onExtendCurrentPreset: @escaping (TimeInterval) -> Void = { _ in },
        onReshuffle: @escaping (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void = { _, _ in },
        onRePlanSession: @escaping () -> Void = {},
        onApplyPresetOverride: @escaping (String, Bool) -> Void = { _, _ in },
        onRestorePlan: @escaping (PlannedSession) -> Void = { _ in },
        onShowPlanPreview: @escaping () -> Void = {}
    ) {
        self.sessionManager = sessionManager
        self.toastBridge = toastBridge
        self.getSessionTime = getSessionTime
        self.getCurrentPresetID = getCurrentPresetID
        self.getCurrentPresetFamily = getCurrentPresetFamily
        self.getLivePlan = getLivePlan
        self.getCatalog = getCatalog
        self.getTrackProfile = getTrackProfile
        self.getCurrentTrackIndex = getCurrentTrackIndex
        self.getScoringContext = getScoringContext
        self.onExtendCurrentPreset = onExtendCurrentPreset
        self.onReshuffle = onReshuffle
        self.onRePlanSession = onRePlanSession
        self.onApplyPresetOverride = onApplyPresetOverride
        self.onRestorePlan = onRestorePlan
        self.onShowPlanPreview = onShowPlanPreview

        // Reset all adaptation state whenever a new session begins or the old one ends.
        if let mgr = sessionManager {
            sessionStateCancellable = mgr.$state.sink { [weak self] state in
                if state == .connecting || state == .ended {
                    self?.resetAdaptationState()
                }
            }
        }
    }

    // MARK: - AdaptationFields Snapshot

    /// Returns the current adaptation preferences resolved at `sessionTime`.
    ///
    /// Prunes expired `temporaryFamilyExclusions` as a side effect.
    func adaptationFields(at sessionTime: TimeInterval) -> AdaptationFields {
        // Prune expired entries in-place.
        temporaryFamilyExclusions = temporaryFamilyExclusions.filter { $0.value > sessionTime }
        return AdaptationFields(
            familyBoosts: familyBoosts,
            temporarilyExcludedFamilies: Set(temporaryFamilyExclusions.keys),
            sessionExcludedPresets: sessionExcludedPresets
        )
    }

    // MARK: - State Reset

    /// Clears all U.6b preference state. Called on session start/end and `buildPlan()`.
    func resetAdaptationState() {
        familyBoosts = [:]
        temporaryFamilyExclusions = [:]
        sessionExcludedPresets = []
        adaptationHistory = []
        lastNegativeNudgeAt = nil
        ambientHintShown = false
        lastPlayedPresetID = nil
        ceilingTimerTask?.cancel()
        ceilingTimerTask = nil
    }

    /// Record the most-recently-played preset before a transition completes.
    ///
    /// Called by the engine's transition-application path to populate the
    /// `lastPlayedPresetID` used by `presetNudge(.previous)`.
    func recordPresetTransition(outgoingPresetID: String) {
        lastPlayedPresetID = outgoingPresetID
    }

    // MARK: - V.7.6.2 Segment-Aware Helpers

    /// Find the next `PlannedPresetSegment` in the live plan after the segment that
    /// currently contains `sessionTime`. Returns nil when there is no plan, no
    /// matching active segment, or the active segment is the last in the session.
    private func nextPlannedSegment(
        in plan: PlannedSession?,
        sessionTime: TimeInterval,
        currentPresetID: String?
    ) -> PlannedPresetSegment? {
        guard let plan else { return nil }

        // Flatten all segments in playback order so we can look up "next".
        let allSegments: [PlannedPresetSegment] = plan.tracks.flatMap { $0.segments }
        guard let activeIdx = allSegments.firstIndex(where: { seg in
            sessionTime >= seg.plannedStartTime && sessionTime < seg.plannedEndTime
        }) else { return nil }

        let nextIdx = activeIdx + 1
        guard nextIdx < allSegments.count else { return nil }

        // Avoid suggesting the same preset back-to-back unless the planner did.
        let candidate = allSegments[nextIdx]
        if let currentPresetID, candidate.preset.id == currentPresetID {
            // Walk forward until we find a different preset, or fall back to the planner's pick.
            for forward in (nextIdx + 1)..<allSegments.count where allSegments[forward].preset.id != currentPresetID {
                return allSegments[forward]
            }
        }
        return candidate
    }

    // MARK: - Undo Stack Helpers

    private func pushHistory() {
        guard let plan = getLivePlan() else { return }
        adaptationHistory.append(plan)
        if adaptationHistory.count > Self.historyCapacity {
            adaptationHistory.removeFirst()
        }
    }

    // MARK: - PlaybackActionRouter

    func moreLikeThis() {
        let family = getCurrentPresetFamily()
        pushHistory()
        if let family {
            // Idempotent: max(existing, 0.3) — pressing `+` twice stays at 0.3.
            familyBoosts[family] = max(familyBoosts[family, default: 0], 0.3)
        }
        onExtendCurrentPreset(30)
        let familyName = family?.displayName ?? "this style"
        toastBridge?.emitAck("Boosted \(familyName)")
        logger.info("U.6b: moreLikeThis family=\(family?.rawValue ?? "nil") boost=+0.3 extend=30s")
    }

    func lessLikeThis() {
        let family = getCurrentPresetFamily()
        let presetID = getCurrentPresetID()
        let sessionTime = getSessionTime()
        pushHistory()

        if let family {
            temporaryFamilyExclusions[family] = sessionTime + 600  // 10 minutes
        }
        if let presetID {
            sessionExcludedPresets.insert(presetID)
        }

        // Double-`-` ambient hint: two presses within 90s → emit once per session.
        if let prev = lastNegativeNudgeAt, (sessionTime - prev) < 90, !ambientHintShown {
            let hint = PhospheneToast(
                severity: .info,
                copy: "Not quite hitting the mark? Try ⌘R to re-plan.",
                source: .liveAdaptationAck
            )
            // Toast bridge may not be available in tests; emit directly if nil.
            toastBridge?.emitAck("Not quite hitting the mark? Try ⌘R to re-plan.")
            _ = hint  // hint struct built for logging parity; bridge does the actual enqueue
            ambientHintShown = true
        }
        lastNegativeNudgeAt = sessionTime

        let familyName = family?.displayName ?? "this style"
        toastBridge?.emitAck("Excluding \(familyName) for 10 min")

        // Schedule early-out: fire at next structural boundary (handled by LiveAdapter's
        // normal path since the family is now excluded) OR force at 8s ceiling.
        ceilingTimerTask?.cancel()
        ceilingTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            // Check if the boundary path already fired a transition (live plan changed).
            // If the current preset is still the excluded one, force a nudge.
            if let currentID = self.getCurrentPresetID(),
               let excludedID = presetID, currentID == excludedID {
                self.onApplyPresetOverride(currentID, true)
            }
        }

        logger.info("U.6b: lessLikeThis family=\(family?.rawValue ?? "nil") presetID=\(presetID ?? "nil") expiry=+600s")
    }

    func reshuffleUpcoming() {
        guard let plan = getLivePlan() else {
            logger.info("U.6b: reshuffleUpcoming — no live plan, skipping")
            return
        }
        pushHistory()

        let trackIndex = getCurrentTrackIndex()

        // Played tracks (indices 0..<trackIndex): lock their TrackIdentities.
        let playedTracks = Set(plan.tracks.prefix(trackIndex).map(\.track))

        // Current track: lock its current preset.
        var lockedPresets: [TrackIdentity: PresetDescriptor] = [:]
        if trackIndex < plan.tracks.count {
            let current = plan.tracks[trackIndex]
            lockedPresets[current.track] = current.preset
        }

        onReshuffle(playedTracks, lockedPresets)
        toastBridge?.emitAck("Upcoming reshuffled")
        logger.info("U.6b: reshuffleUpcoming played=\(playedTracks.count) lockedPresets=\(lockedPresets.count)")
    }

    func presetNudge(_ direction: NudgeDirection, immediate: Bool) {
        pushHistory()

        let fields = adaptationFields(at: getSessionTime())
        let context = getScoringContext(fields)
        let catalog = getCatalog()
        let profile = getTrackProfile() ?? TrackProfile.empty
        let scorer = DefaultPresetScorer()

        // Manual override: Shift+arrow (immediate==true) always walks the full
        // catalog alphabetically. The scorer-driven "stylistic nudge at
        // boundary" path (plain arrow, immediate==false) is preserved for
        // normal listening, but `immediate` is the user explicitly taking
        // control — they want a predictable cycle, not a fresh-scored pick
        // that may collapse to a 2–3 preset cycle when sub-scores are
        // degenerate (TrackProfile.empty / no plan / metadata-driven profiles
        // that don't differentiate descriptors).
        if immediate && !catalog.isEmpty {
            if reactiveWalkNudge(direction: direction, immediate: immediate, catalog: catalog) {
                return
            }
        }

        switch direction {
        case .next:
            // V.7.6.2: prefer the next planned segment (within current track or, failing that,
            // the first segment of the next track) over a fresh-scoring nudge. Falls back to
            // scoring when there is no live plan or the current preset is the last segment.
            if let plannedNext = nextPlannedSegment(in: getLivePlan(),
                                                    sessionTime: getSessionTime(),
                                                    currentPresetID: getCurrentPresetID()) {
                let suffix = immediate ? "" : " — at next boundary"
                toastBridge?.emitAck("Nudged forward\(suffix)")
                onApplyPresetOverride(plannedNext.preset.id, immediate)
                if !immediate {
                    scheduleNudgeCeiling(presetID: plannedNext.preset.id)
                }
                logger.info("U.6b: presetNudge(.next) plannedSegment=\(plannedNext.preset.id) immediate=\(immediate)")
                return
            }

            let ranked = scorer.rank(presets: catalog, track: profile, context: context)
            guard let top = ranked.first(where: { $0.1 > 0 }) else {
                logger.warning("U.6b: presetNudge(.next) — no eligible preset found")
                return
            }
            let suffix = immediate ? "" : " — at next boundary"
            toastBridge?.emitAck("Nudged forward\(suffix)")
            onApplyPresetOverride(top.0.id, immediate)

            if !immediate {
                scheduleNudgeCeiling(presetID: top.0.id)
            }
            logger.info("U.6b: presetNudge(.next) preset=\(top.0.id) immediate=\(immediate)")

        case .previous:
            guard let prevID = lastPlayedPresetID else {
                logger.warning("U.6b: presetNudge(.previous) — no lastPlayedPresetID, no-op")
                return
            }
            let suffix = immediate ? "" : " — at next boundary"
            toastBridge?.emitAck("Nudged back\(suffix)")
            onApplyPresetOverride(prevID, immediate)

            if !immediate {
                scheduleNudgeCeiling(presetID: prevID)
            }
            logger.info("U.6b: presetNudge(.previous) preset=\(prevID) immediate=\(immediate)")
        }
    }

    /// Alphabetical walk through the full catalog for the reactive / ad-hoc
    /// nudge fallback. Returns `true` if a preset was applied (the caller
    /// should `return`); `false` if the catalog was empty.
    ///
    /// Diagnostic presets (`is_diagnostic: true`, e.g. Spectral Cartograph) are
    /// included here. D-074 keeps them out of orchestrator auto-selection but
    /// `Shift+arrow` is explicit manual-switch — exactly the path D-074
    /// reserves for reaching diagnostic surfaces.
    private func reactiveWalkNudge(
        direction: NudgeDirection,
        immediate: Bool,
        catalog: [PresetDescriptor]
    ) -> Bool {
        let eligible = catalog.sorted { $0.name < $1.name }
        guard !eligible.isEmpty else {
            logger.warning("U.6b: presetNudge — empty catalog")
            return false
        }
        let count = eligible.count
        let currentIdx = eligible.firstIndex(where: { $0.id == getCurrentPresetID() })
        let nextIdx: Int
        switch direction {
        case .next:
            nextIdx = (((currentIdx ?? -1) + 1) % count + count) % count
        case .previous:
            nextIdx = (((currentIdx ?? 0) - 1) % count + count) % count
        }
        let nextDesc = eligible[nextIdx]
        let suffix = immediate ? "" : " — at next boundary"
        let label = direction == .next ? "Nudged forward" : "Nudged back"
        toastBridge?.emitAck("\(label)\(suffix)")
        onApplyPresetOverride(nextDesc.id, immediate)
        if !immediate {
            scheduleNudgeCeiling(presetID: nextDesc.id)
        }
        logger.info("U.6b: presetNudge(.\(String(describing: direction))) reactive-walk → \(nextDesc.id)")
        return true
    }

    func rePlanSession() {
        pushHistory()
        onRePlanSession()
        onShowPlanPreview()
        toastBridge?.emitAck("Replanned")
        logger.info("U.6b: rePlanSession")
    }

    func undoLastAdaptation() {
        guard let snapshot = adaptationHistory.popLast() else {
            toastBridge?.emitAck("Nothing to undo")
            logger.info("U.6b: undoLastAdaptation — history empty, no-op")
            return
        }
        // Restore livePlan only. Preference state (familyBoosts / exclusions) is
        // intentionally preserved — see D-058(b).
        onRestorePlan(snapshot)
        toastBridge?.emitAck("Undone")
        logger.info("U.6b: undoLastAdaptation — plan restored (history remaining: \(self.adaptationHistory.count))")
    }

    func toggleMoodLock() {
        isMoodLocked.toggle()
        logger.info("PlaybackActionRouter: moodLock = \(self.isMoodLocked)")
    }

    // MARK: - Private Helpers

    private func scheduleNudgeCeiling(presetID: String) {
        ceilingTimerTask?.cancel()
        ceilingTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            if let currentID = self.getCurrentPresetID(), currentID != presetID {
                // Boundary already fired a transition — skip.
                return
            }
            self.onApplyPresetOverride(presetID, true)
        }
    }
}

// MARK: - Live Factory

extension DefaultPlaybackActionRouter {

    /// Creates a router wired to a live `VisualizerEngine`.
    ///
    /// Use this in `PlaybackView.setup()`. All closures capture `engine` weakly
    /// to avoid retain cycles.
    @MainActor
    static func live(
        engine: VisualizerEngine,
        toastBridge: LiveAdaptationToastBridge?,
        onShowPlanPreview: @escaping () -> Void
    ) -> DefaultPlaybackActionRouter {
        DefaultPlaybackActionRouter(
            sessionManager: engine.sessionManager,
            toastBridge: toastBridge,
            getSessionTime: { [weak engine] in engine?.currentAbsoluteTime ?? 0 },
            getCurrentPresetID: { [weak engine] in engine?.currentPresetDescriptor?.id },
            getCurrentPresetFamily: { [weak engine] in engine?.currentPresetDescriptor?.family },
            getLivePlan: { [weak engine] in engine?.orchestratorLock.withLock { engine?.livePlan } },
            getCatalog: { [weak engine] in engine?.presetLoader.presets.map(\.descriptor) ?? [] },
            getTrackProfile: { [weak engine] in engine?.currentTrackProfile() },
            getCurrentTrackIndex: { [weak engine] in engine?.currentTrackIndexInPlan() ?? 0 },
            getScoringContext: { [weak engine] fields in
                engine?.buildScoringContext(adaptationFields: fields) ?? .initial(deviceTier: .tier1)
            },
            onExtendCurrentPreset: { [weak engine] seconds in engine?.extendCurrentPreset(by: seconds) },
            onReshuffle: { [weak engine] locked, lockedPresets in
                engine?.regeneratePlan(lockedTracks: locked, lockedPresets: lockedPresets)
            },
            onRePlanSession: { [weak engine] in
                engine?.regeneratePlan(lockedTracks: [], lockedPresets: [:])
            },
            onApplyPresetOverride: { [weak engine] presetID, _ in engine?.applyPresetByID(presetID) },
            onRestorePlan: { [weak engine] plan in engine?.restoreLivePlan(plan) },
            onShowPlanPreview: onShowPlanPreview
        )
    }
}
// swiftlint:enable file_length
