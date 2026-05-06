// VisualizerEngine+Orchestrator — App-layer wiring for the AI VJ planner (Increment 4.5).
//
// Owns the live PlannedSession and coordinates between DefaultSessionPlanner,
// DefaultLiveAdapter, and the render/audio paths.
//
// Threading: livePlan is read from the render/audio queues and written from the
// main thread (buildPlan) or the analysis queue (applyLiveUpdate). All access is
// guarded by orchestratorLock — same pattern as stemsStateLock in +Stems.

import Foundation
import Metal
import Orchestrator
import os.log
import Presets
import Session
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

// MARK: - Orchestrator Wiring

extension VisualizerEngine {

    // MARK: - Plan Building

    /// Build and store a `PlannedSession` from the currently-cached tracks.
    ///
    /// Called when `sessionManager.state` transitions to `.ready`. Generates a
    /// random seed (stored so `extendPlan()` produces a prefix-identical plan),
    /// then delegates to the shared `_buildPlan(seed:)` implementation.
    ///
    /// In the progressive-readiness flow (Increment 6.1), this may be called when
    /// only a subset of tracks have cache entries — the remaining tracks are planned
    /// as preparation completes, via `extendPlan()`.
    ///
    /// Failures are logged; `livePlan` is left nil so the render loop continues
    /// in reactive mode (no pre-planned presets).
    @MainActor
    func buildPlan() {
        // A real plan is taking over — end reactive mode.
        reactiveSessionStart = nil

        // Generate a fresh seed for this session; extendPlan() will reuse it.
        let seed = UInt64.random(in: 1...UInt64.max)
        currentSessionPlanSeed = seed
        _buildPlan(seed: seed)
    }

    /// Extend the live plan as more tracks become available during background preparation.
    ///
    /// Uses the **same seed** as `buildPlan()`, so the prefix of the extended plan is
    /// byte-identical to the previous partial plan (planner determinism guarantee, D-047).
    /// A `.partialPreparation` warning is appended when the plan covers fewer tracks than
    /// the full session (per `sessionManager.currentPlan.tracks.count`).
    ///
    /// A no-op if `buildPlan()` has not yet been called for this session (seed is nil).
    @MainActor
    func extendPlan() {
        guard let seed = currentSessionPlanSeed else {
            logger.info("Orchestrator: extendPlan — no seed stored, skipping")
            return
        }
        _buildPlan(seed: seed)
    }

    /// Shared plan-building implementation. Filters to tracks with cache entries and
    /// appends a `.partialPreparation` warning when coverage is incomplete.
    @MainActor
    private func _buildPlan(seed: UInt64) {
        logWiringBuildPlanEnter()   // BUG-006.1
        guard let sessionPlan = sessionManager.currentPlan else {
            logger.info("Orchestrator: no session plan available — skipping")
            logWiringBuildPlanEarlyReturn(reason: "no session plan")
            return
        }
        let fullCount = sessionPlan.tracks.count
        let cache = sessionManager.cache

        // Only plan from tracks that have been cached — uncached tracks have empty
        // profiles which would skew scoring. The reactive path covers remaining tracks.
        let readyTracks: [(TrackIdentity, TrackProfile)] = sessionPlan.tracks.compactMap { identity in
            guard let profile = cache.trackProfile(for: identity) else { return nil }
            return (identity, profile)
        }

        guard !readyTracks.isEmpty else {
            logger.info("Orchestrator: no cached tracks — deferring plan")
            logWiringBuildPlanEarlyReturn(reason: "no cached tracks")
            return
        }

        let catalog = presetLoader.presets.map { $0.descriptor }
        let tier = Self.detectDeviceTier(device: context.device)

        do {
            var plan = try sessionPlanner.plan(
                tracks: readyTracks,
                catalog: catalog,
                deviceTier: tier,
                seed: seed,
                includeUncertifiedPresets: showUncertifiedPresets
            )

            // Attach partial-preparation warning when coverage is incomplete.
            let unplannedCount = fullCount - readyTracks.count
            if unplannedCount > 0 {
                let warning = PlanningWarning(
                    kind: .partialPreparation(unplannedCount: unplannedCount),
                    trackIndex: readyTracks.count,
                    message: "\(unplannedCount) track(s) not yet prepared"
                )
                plan = plan.appendingWarnings([warning])
            }

            orchestratorLock.withLock { livePlan = plan }
            livePlannedSession = plan

            let totalSecs = String(format: "%.0f", plan.totalDuration)
            let warnCount = plan.warnings.count
            logger.info("Orchestrator: plan — \(plan.tracks.count)/\(fullCount) tracks, \(totalSecs)s, \(warnCount) warnings")

            // Pre-load the BeatGrid for the first planned track so Spectral Cartograph
            // shows "PLANNED · UNLOCKED" immediately after plan-build. DSP.3.2.
            let firstTrackTitle = plan.tracks.first?.track.title ?? "<none>"
            let aboutToPreFire = plan.tracks.first?.track != nil
            logWiringBuildPlanDone(firstTrackTitle: firstTrackTitle, aboutToPreFire: aboutToPreFire)

            if let firstTrack = plan.tracks.first?.track {
                resetStemPipeline(for: firstTrack, caller: .preFire)
            }
        } catch {
            logger.error("Orchestrator: plan failed — \(error)")
            logWiringBuildPlanFailed(error)
        }
    }

    // MARK: - Plan Queries

    /// Returns the preset planned for the given session time, or nil if no plan exists.
    ///
    /// Thread-safe: acquires `orchestratorLock`.
    func currentPreset(at sessionTime: TimeInterval) -> PresetDescriptor? {
        orchestratorLock.withLock { livePlan }?.track(at: sessionTime)?.preset
    }

    /// Returns the transition planned near the given session time, or nil if none.
    ///
    /// Thread-safe: acquires `orchestratorLock`.
    func currentTransition(at sessionTime: TimeInterval) -> PlannedTransition? {
        orchestratorLock.withLock { livePlan }?.transition(at: sessionTime)
    }

    // MARK: - Live Adaptation

    /// Evaluate live MIR data against the plan and apply any adaptation.
    ///
    /// Called from the audio/analysis path (background queue). If an adaptation fires,
    /// patches `livePlan` in-place under `orchestratorLock`.
    ///
    /// - Parameters:
    ///   - trackIndex: 0-based index of the currently playing track.
    ///   - elapsedTrackTime: Seconds since this track began playing.
    ///   - boundary: Latest `StructuralPrediction` from the live MIR pipeline.
    ///   - mood: Current `EmotionalState` from the live mood classifier.
    func applyLiveUpdate(
        trackIndex: Int,
        elapsedTrackTime: TimeInterval,
        boundary: StructuralPrediction,
        mood: EmotionalState
    ) {
        guard let plan = orchestratorLock.withLock({ livePlan }) else {
            applyReactiveUpdate(boundary: boundary, mood: mood)
            return
        }

        let catalog = presetLoader.presets.map { $0.descriptor }

        let adaptation = liveAdapter.adapt(
            plan: plan,
            currentTrackIndex: trackIndex,
            elapsedTrackTime: elapsedTrackTime,
            liveBoundary: boundary,
            liveMood: mood,
            catalog: catalog
        )

        // Log each event from the adaptation.
        for event in adaptation.events {
            switch event.kind {
            case .noAdaptation:
                break
            case .boundaryRescheduled, .moodDivergenceDetected, .presetOverrideTriggered:
                logger.info("Orchestrator: [\(event.kind.rawValue)] \(event.message)")
            }
        }

        // Suppress mood-derived preset overrides during: (a) capture-mode switch grace window
        // (silence may produce spurious Δmood), (b) diagnostic hold (user explicitly pinned a
        // diagnostic preset). Boundary rescheduling (updatedTransition) is always allowed. D-061(b,c), DSP.3.1.
        let effectiveAdaptation: LiveAdaptation
        let suppressOverride = isCaptureModeSwitchGraceActive || diagnosticPresetLocked
        if suppressOverride, adaptation.presetOverride != nil {
            effectiveAdaptation = LiveAdaptation(
                updatedTransition: adaptation.updatedTransition,
                presetOverride: nil,
                events: adaptation.events.filter { $0.kind != .presetOverrideTriggered }
            )
            let reason = isCaptureModeSwitchGraceActive ? "grace window" : "diagnostic hold"
            logger.info("Orchestrator: \(reason) active — preset override suppressed")
        } else {
            effectiveAdaptation = adaptation
        }

        // Patch the plan only when something changed.
        guard effectiveAdaptation.updatedTransition != nil || effectiveAdaptation.presetOverride != nil else {
            return
        }

        let patched = plan.applying(effectiveAdaptation, at: trackIndex)
        orchestratorLock.withLock { livePlan = patched }
    }

    // MARK: - Reactive Mode (Ad-Hoc Sessions)

    /// Apply reactive orchestration when no pre-planned session exists.
    ///
    /// Accumulates wall-clock elapsed time from the first call. Suggests preset
    /// switches via `DefaultReactiveOrchestrator.evaluate()` and applies them on
    /// the main thread. A 60 s cooldown prevents switch-thrashing.
    ///
    /// Called from the audio/analysis path (background queue).
    private func applyReactiveUpdate(boundary: StructuralPrediction, mood: EmotionalState) {
        if reactiveSessionStart == nil { reactiveSessionStart = Date() }
        guard let sessionStart = reactiveSessionStart else { return }
        let elapsed = Date().timeIntervalSince(sessionStart)

        let catalog = presetLoader.presets.map { $0.descriptor }
        let currentDesc = presetLoader.currentPreset?.descriptor
        let tier = Self.detectDeviceTier(device: context.device)

        let decision = reactiveOrchestrator.evaluate(
            liveMood: mood,
            liveBoundary: boundary,
            elapsedSessionTime: elapsed,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: tier,
            includeUncertifiedPresets: showUncertifiedPresets
        )

        switch decision.accumulationState {
        case .listening:
            break
        case .ramping, .full:
            if decision.suggestedPreset != nil {
                logger.info("Orchestrator (reactive): \(decision.reason)")
            }
        }

        guard let suggested = decision.suggestedPreset,
              elapsed - lastReactiveSwitchTime >= 60.0 else { return }

        guard let loadedPreset = presetLoader.presets.first(
            where: { $0.descriptor.name == suggested.name }
        ) else {
            logger.warning("Orchestrator (reactive): suggested preset '\(suggested.name)' not in loader")
            return
        }

        lastReactiveSwitchTime = elapsed
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyPreset(loadedPreset)
            self.showPresetName(loadedPreset.descriptor.name)
        }
    }

    // MARK: - Plan Regeneration

    /// Re-run the planner with a random seed, preserving any manually locked track picks.
    ///
    /// Called from `PlanPreviewViewModel.regeneratePlan()` via an injected closure.
    /// Updates both `livePlan` (thread-safe) and `livePlannedSession` (@Published, main actor).
    @MainActor
    func regeneratePlan(lockedTracks: Set<TrackIdentity>, lockedPresets: [TrackIdentity: PresetDescriptor]) {
        guard let sessionPlan = sessionManager.currentPlan else {
            logger.info("Orchestrator: regeneratePlan — no session plan, skipping")
            return
        }
        let tracks: [(TrackIdentity, TrackProfile)] = sessionPlan.tracks.map {
            ($0, sessionManager.cache.trackProfile(for: $0) ?? .empty)
        }
        let catalog = presetLoader.presets.map { $0.descriptor }
        let tier = Self.detectDeviceTier(device: context.device)
        let seed = UInt64.random(in: 1...UInt64.max)
        currentSessionPlanSeed = seed   // so extendPlan() uses the new seed too

        do {
            // includeUncertifiedPresets must propagate here too — otherwise the
            // Plan Preview "Regenerate Plan" button silently throws
            // SessionPlanningError.noEligiblePresets when the catalog is fully
            // uncertified, and the live plan is not updated.
            var plan = try sessionPlanner.plan(
                tracks: tracks,
                catalog: catalog,
                deviceTier: tier,
                seed: seed,
                includeUncertifiedPresets: showUncertifiedPresets
            )
            if !lockedPresets.isEmpty {
                plan = plan.applying(overrides: lockedPresets)
            }
            orchestratorLock.withLock { livePlan = plan }
            livePlannedSession = plan
            logger.info("Orchestrator: plan regenerated (seed=\(seed), locks=\(lockedTracks.count))")
        } catch {
            logger.error("Orchestrator: regeneratePlan failed — \(error)")
        }
    }

    // MARK: - U.6b Router Support

    /// Monotonic wall-clock time used for exclusion-expiry and double-`-` hint windows.
    var currentAbsoluteTime: TimeInterval { Date().timeIntervalSinceReferenceDate }

    /// Descriptor of the currently active preset, or nil.
    var currentPresetDescriptor: PresetDescriptor? { presetLoader.currentPreset?.descriptor }

    /// Extends the current track's planned end time in the live plan, shifting all following tracks.
    @MainActor
    func extendCurrentPreset(by seconds: TimeInterval) {
        let now = currentAbsoluteTime
        orchestratorLock.withLock {
            guard let plan = livePlan else { return }
            livePlan = plan.extendingCurrentPreset(by: seconds, at: now)
        }
        livePlannedSession = orchestratorLock.withLock { livePlan }
    }

    /// Applies the named preset (by ID) and shows its name banner.
    /// `selectPreset(named:)` first so the loader's `currentIndex` matches —
    /// without it, the scorer's `"already active"` exclusion stays stuck on a
    /// stale value and `Shift+→` keeps re-picking the same top preset.
    @MainActor
    func applyPresetByID(_ presetID: String) {
        guard let loaded = presetLoader.presets.first(where: { $0.descriptor.id == presetID }) else {
            logger.warning("Orchestrator: applyPresetByID '\(presetID)' not found in loader")
            return
        }
        presetLoader.selectPreset(named: loaded.descriptor.name)
        applyPreset(loaded)
        showPresetName(loaded.descriptor.name)
    }

    /// Restores the live plan from a saved snapshot (for undo).
    @MainActor
    func restoreLivePlan(_ plan: PlannedSession) {
        orchestratorLock.withLock { livePlan = plan }
        livePlannedSession = plan
    }

    /// Builds a scoring context for the current session state, incorporating adaptation fields.
    @MainActor
    func buildScoringContext(adaptationFields: AdaptationFields) -> PresetScoringContext {
        let tier = Self.detectDeviceTier(device: context.device)
        return PresetScoringContext(
            deviceTier: tier,
            currentPreset: currentPresetDescriptor,
            familyBoosts: adaptationFields.familyBoosts,
            temporarilyExcludedFamilies: adaptationFields.temporarilyExcludedFamilies,
            sessionExcludedPresets: adaptationFields.sessionExcludedPresets,
            // Settings → Visuals → "Show uncertified presets" must propagate here
            // or Shift+→ (presetNudge) produces "no eligible preset found" with
            // a fully-uncertified catalog. Other context builders (lines 98, 233)
            // already pass this; this one was missing.
            includeUncertifiedPresets: showUncertifiedPresets
        )
    }

    /// Index of the currently playing track in the live plan, or 0.
    @MainActor
    func currentTrackIndexInPlan() -> Int {
        guard let plan = orchestratorLock.withLock({ livePlan }) else { return 0 }
        let now = currentAbsoluteTime
        return plan.tracks.firstIndex(where: {
            now >= $0.plannedStartTime && now < $0.plannedEndTime
        }) ?? 0
    }

    /// Track profile for the currently playing track, or nil.
    @MainActor
    func currentTrackProfile() -> TrackProfile? {
        guard let identity = currentTrack.map({ TrackIdentity(
            title: $0.title ?? "",
            artist: $0.artist ?? "",
            duration: $0.duration
        ) }) else { return nil }
        return sessionManager.cache.trackProfile(for: identity)
    }
}
