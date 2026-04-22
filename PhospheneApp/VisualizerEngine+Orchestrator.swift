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

    /// Build and store a `PlannedSession` from the current session state.
    ///
    /// Call this when `sessionManager.state` transitions to `.ready`.
    /// Reads `(TrackIdentity, TrackProfile)` pairs from the session cache, builds
    /// the catalog from `presetLoader`, and runs `DefaultSessionPlanner.plan()`.
    ///
    /// Failures are logged; `livePlan` is left nil so the render loop continues
    /// in reactive mode (no pre-planned presets).
    @MainActor
    func buildPlan() {
        guard let sessionPlan = sessionManager.currentPlan else {
            logger.info("Orchestrator: no session plan available — skipping build")
            return
        }
        let manager = sessionManager
        // A real plan is taking over — end reactive mode.
        reactiveSessionStart = nil

        let identities = sessionPlan.tracks
        let cache = manager.cache

        // Pair each TrackIdentity with its cached TrackProfile (fall back to empty).
        let tracks: [(TrackIdentity, TrackProfile)] = identities.map { identity in
            let profile = cache.trackProfile(for: identity) ?? TrackProfile.empty
            return (identity, profile)
        }

        let catalog = presetLoader.presets.map { $0.descriptor }
        let tier = Self.detectDeviceTier(device: context.device)

        do {
            let plan = try sessionPlanner.plan(tracks: tracks, catalog: catalog, deviceTier: tier)
            orchestratorLock.withLock { livePlan = plan }

            let presetNames = plan.tracks.map { $0.preset.name }.joined(separator: ", ")
            let totalSecs = String(format: "%.0f", plan.totalDuration)
            logger.info("Orchestrator: plan built — \(plan.tracks.count) tracks, \(totalSecs)s, \(plan.warnings.count) warnings")
            logger.info("Orchestrator: planned presets — [\(presetNames)]")
        } catch {
            logger.error("Orchestrator: plan failed — \(error)")
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

        // Patch the plan only when something changed.
        guard adaptation.updatedTransition != nil || adaptation.presetOverride != nil else {
            return
        }

        let patched = plan.applying(adaptation, at: trackIndex)
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
            deviceTier: tier
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

    // MARK: - Device Tier Detection

    /// Infer the Apple Silicon generation from the Metal device name.
    ///
    /// Returns `.tier2` for M3/M4 devices, `.tier1` for all others (M1, M2,
    /// or unrecognised names — conservative fallback).
    static func detectDeviceTier(device: MTLDevice) -> DeviceTier {
        let name = device.name.lowercased()
        if name.contains("m3") || name.contains("m4") { return .tier2 }
        return .tier1
    }
}
