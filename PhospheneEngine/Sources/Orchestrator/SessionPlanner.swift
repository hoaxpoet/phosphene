// SessionPlanner — Greedy forward-walk playlist planner (Increment 4.3, D-032).
//
// Composes DefaultPresetScorer (4.1) and DefaultTransitionPolicy (4.2) to
// produce a fully pre-planned PlannedSession before playback begins.
//
// Algorithm: walk the playlist in order; for each track build a scoring context
// reflecting accumulated history and pick the best eligible preset. Never
// backtracks (O(N × catalog), deterministic). Global optimization over mood arcs
// is a future enhancement (D-032).
//
// Determinism rule: no Date.now(), no random, no environment reads inside plan().

import Foundation
import Shared
import Presets
import Session
import os.log

private let logger = Logging.session

// MARK: - SessionPlanning

/// Protocol for playlist planning implementations.
///
/// Conforming types must be `Sendable` and deterministic: the same
/// `(tracks, catalog, deviceTier)` must always produce byte-identical output.
public protocol SessionPlanning: Sendable {
    /// Synchronously build a `PlannedSession` for the given playlist.
    func plan(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier
    ) throws -> PlannedSession
}

// MARK: - SessionPlanningError

/// Errors thrown by `SessionPlanning` implementations.
public enum SessionPlanningError: Error, Sendable, Equatable {
    /// The track list was empty.
    case emptyPlaylist
    /// The preset catalog was empty.
    case emptyCatalog
    /// Precompilation of a specific preset failed after planning completed.
    case precompileFailed(presetID: String, underlying: String)
}

// MARK: - DefaultSessionPlanner

/// Concrete `SessionPlanning` implementation.
///
/// Selects presets via `DefaultPresetScorer`, schedules transitions via
/// `DefaultTransitionPolicy`. See D-032 for the full design rationale.
///
/// **Fallback ladder (D-018, D-032):**
/// 1. Highest-scoring non-excluded preset in the catalog.
/// 2. All excluded: cheapest non-current preset — `.noEligiblePresets` warning.
/// 3. No alternative: cheapest preset regardless of identity — `.budgetExceeded` too.
///
/// Plans are always producible given a non-empty catalog.
public struct DefaultSessionPlanner: SessionPlanning {

    // MARK: - Dependencies

    private let scorer: any PresetScoring
    private let transitionPolicy: any TransitionDeciding
    private let precompile: (@Sendable (PresetDescriptor) async throws -> Void)?

    /// Fallback track duration when `TrackIdentity.duration` is nil (seconds).
    private static let defaultTrackDuration: TimeInterval = 180

    // MARK: - Init

    public init(
        scorer: any PresetScoring = DefaultPresetScorer(),
        transitionPolicy: any TransitionDeciding = DefaultTransitionPolicy(),
        precompile: (@Sendable (PresetDescriptor) async throws -> Void)? = nil
    ) {
        self.scorer = scorer
        self.transitionPolicy = transitionPolicy
        self.precompile = precompile
    }

    // MARK: - SessionPlanning

    public func plan(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier
    ) throws -> PlannedSession {
        try plan(tracks: tracks, catalog: catalog, deviceTier: deviceTier, seed: 0)
    }

    /// Seeded variant for "Regenerate Plan" (D-047).
    ///
    /// When `seed` is zero, output is byte-identical to the zero-seed run (D-034 preserved).
    /// When nonzero, a deterministic ±0.02 perturbation is added to each preset score before
    /// selection — enough to break ties without changing the ranking meaningfully on non-equal
    /// scores. Two calls with the same nonzero seed produce identical output.
    public func plan(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        seed: UInt64
    ) throws -> PlannedSession {
        guard !tracks.isEmpty else { throw SessionPlanningError.emptyPlaylist }
        guard !catalog.isEmpty else { throw SessionPlanningError.emptyCatalog }

        var sessionClock: TimeInterval = 0
        var history: [PresetHistoryEntry] = []
        var currentPreset: PresetDescriptor?
        var planned: [PlannedTrack] = []
        var warnings: [PlanningWarning] = []

        for (index, (identity, profile)) in tracks.enumerated() {
            let ctx = PresetScoringContext(
                deviceTier: deviceTier,
                recentHistory: history,
                currentPreset: currentPreset,
                elapsedSessionTime: sessionClock
            )
            let (chosen, breakdown) = selectPreset(
                catalog: catalog,
                profile: profile,
                context: ctx,
                trackRef: (index, identity.title),
                seed: seed,
                warnings: &warnings
            )
            if currentPreset?.family == chosen.family {
                warnings.append(familyRepeatWarning(index: index, title: identity.title, chosen: chosen))
            }
            let lastEntry = history.last
            let transition = currentPreset.map {
                buildTransition(from: $0, to: chosen, profile: profile, at: sessionClock, lastEntry: lastEntry)
            }
            let plannedEnd = sessionClock + (identity.duration ?? Self.defaultTrackDuration)
            planned.append(PlannedTrack(
                track: identity,
                trackProfile: profile,
                preset: chosen,
                presetScore: breakdown.total,
                scoreBreakdown: breakdown,
                plannedStartTime: sessionClock,
                plannedEndTime: plannedEnd,
                incomingTransition: transition
            ))
            history.append(PresetHistoryEntry(
                presetID: chosen.id,
                family: chosen.family,
                startTime: sessionClock,
                endTime: plannedEnd
            ))
            currentPreset = chosen
            sessionClock = plannedEnd
        }

        return PlannedSession(
            deviceTier: deviceTier,
            tracks: planned,
            totalDuration: sessionClock,
            warnings: warnings
        )
    }

    // MARK: - planAsync

    /// Builds the plan then awaits precompilation of every distinct preset in the result.
    ///
    /// Precompilation failures are surfaced as `.precompileFailed` after planning
    /// completes — the plan itself is NOT unwound (D-018, D-032).
    public func planAsync(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier
    ) async throws -> PlannedSession {
        let session = try plan(tracks: tracks, catalog: catalog, deviceTier: deviceTier)
        guard let precompile = self.precompile else { return session }

        var seen = Set<String>()
        let distinctPresets = session.tracks.compactMap { entry -> PresetDescriptor? in
            guard seen.insert(entry.preset.id).inserted else { return nil }
            return entry.preset
        }
        for preset in distinctPresets {
            do {
                try await precompile(preset)
            } catch {
                throw SessionPlanningError.precompileFailed(
                    presetID: preset.id,
                    underlying: error.localizedDescription
                )
            }
        }
        return session
    }

    // MARK: - Preset Selection

    // MARK: - Seed Noise (D-047)

    /// Deterministic ±0.02 perturbation for seeded Regenerate Plan.
    ///
    /// Uses a simple LCG chain to produce a float in [-0.02, 0.02] for a given
    /// (seed, trackIndex, presetID) triple. When seed == 0 this is never called.
    private func seededNoise(seed: UInt64, trackIndex: Int, presetID: String) -> Float {
        var hash = seed &+ UInt64(bitPattern: Int64(trackIndex)) &* 2654435761
        hash ^= UInt64(bitPattern: Int64(presetID.hashValue))
        hash = hash &* 6364136223846793005 &+ 1442695040888963407
        let normalized = Float(hash >> 11) / Float(1 << 53)
        return (normalized - 0.5) * 0.04  // [-0.02, 0.02]
    }

    // MARK: - Preset Selection

    /// Returns the best eligible `(preset, breakdown)`, falling back if all are excluded.
    ///
    /// `trackRef` bundles the playlist index and title used for warning messages.
    private func selectPreset( // swiftlint:disable:this function_parameter_count
        catalog: [PresetDescriptor],
        profile: TrackProfile,
        context: PresetScoringContext,
        trackRef: (index: Int, title: String),
        seed: UInt64,
        warnings: inout [PlanningWarning]
    ) -> (PresetDescriptor, PresetScoreBreakdown) {
        let allBDs = catalog.map { preset -> (PresetDescriptor, PresetScoreBreakdown) in
            var bd = scorer.breakdown(preset: preset, track: profile, context: context)
            if seed != 0 {
                let noise = seededNoise(seed: seed, trackIndex: trackRef.index, presetID: preset.id)
                bd = PresetScoreBreakdown(
                    mood: bd.mood,
                    tempoMotion: bd.tempoMotion,
                    stemAffinity: bd.stemAffinity,
                    sectionSuitability: bd.sectionSuitability,
                    familyRepeatMultiplier: bd.familyRepeatMultiplier,
                    fatigueMultiplier: bd.fatigueMultiplier,
                    excluded: bd.excluded,
                    exclusionReason: bd.exclusionReason,
                    familyBoost: bd.familyBoost,
                    excludedReason: bd.excludedReason,
                    total: max(0, min(1, bd.total + noise))
                )
            }
            return (preset, bd)
        }
        if let top = allBDs.filter({ !$0.1.excluded && $0.1.total > 0 }).max(by: { $0.1.total < $1.1.total }) {
            return (top.0, top.1)
        }
        warnings.append(PlanningWarning(
            kind: .noEligiblePresets,
            trackIndex: trackRef.index,
            message: "No eligible preset for track \(trackRef.index) (\(trackRef.title)); "
                   + "all \(catalog.count) catalog presets excluded. Using cheapest fallback."
        ))
        return cheapestFallback(
            catalog: catalog,
            context: context,
            trackIndex: trackRef.index,
            profile: profile,
            warnings: &warnings
        )
    }

    /// Picks the cheapest preset that is not the current preset.
    /// If no alternative exists, returns the globally cheapest with a `.budgetExceeded` warning.
    private func cheapestFallback(
        catalog: [PresetDescriptor],
        context: PresetScoringContext,
        trackIndex: Int,
        profile: TrackProfile,
        warnings: inout [PlanningWarning]
    ) -> (PresetDescriptor, PresetScoreBreakdown) {
        let tier = context.deviceTier
        let sorted = catalog.sorted { $0.complexityCost.cost(for: tier) < $1.complexityCost.cost(for: tier) }
        let excludingID = context.currentPreset?.id
        if let fallback = sorted.first(where: { $0.id != excludingID }) {
            return (fallback, scorer.breakdown(preset: fallback, track: profile, context: context))
        }
        // Single-preset catalog and it is the current one — use it anyway.
        // swiftlint:disable:next force_unwrapping
        let fallback = sorted.first!
        warnings.append(PlanningWarning(
            kind: .budgetExceeded,
            trackIndex: trackIndex,
            message: "Track \(trackIndex): no preset fits tier '\(tier)' budget; "
                   + "using '\(fallback.name)' (\(fallback.complexityCost.cost(for: tier)) ms)."
        ))
        return (fallback, scorer.breakdown(preset: fallback, track: profile, context: context))
    }

    // MARK: - Transition Construction

    /// Builds a `PlannedTransition` using a synthetic `StructuralPrediction` placing the
    /// boundary at the current session clock (confidence 1.0), so `DefaultTransitionPolicy`
    /// fires `.structuralBoundary` at every track change (D-032).
    private func buildTransition(
        from fromPreset: PresetDescriptor,
        to toPreset: PresetDescriptor,
        profile: TrackProfile,
        at sessionClock: TimeInterval,
        lastEntry: PresetHistoryEntry?
    ) -> PlannedTransition {
        let energy = max(0, min(1, 0.5 + 0.4 * profile.mood.arousal))
        let clock = Float(sessionClock)
        let elapsed = lastEntry.map { $0.endTime - $0.startTime } ?? 0
        let ctx = TransitionContext(
            currentPreset: fromPreset,
            elapsedPresetTime: elapsed,
            prediction: StructuralPrediction(
                sectionIndex: 0,
                sectionStartTime: clock,
                predictedNextBoundary: clock,
                confidence: 1.0
            ),
            energy: energy,
            captureTime: clock
        )
        if let decision = transitionPolicy.evaluate(context: ctx) {
            return PlannedTransition(
                fromPreset: fromPreset,
                toPreset: toPreset,
                style: decision.style,
                duration: decision.duration,
                scheduledAt: TimeInterval(decision.scheduledAt),
                reason: decision.rationale
            )
        }
        return PlannedTransition(
            fromPreset: fromPreset,
            toPreset: toPreset,
            style: .crossfade,
            duration: 1.0,
            scheduledAt: sessionClock,
            reason: "Policy returned nil at track change; using default 1 s crossfade."
        )
    }

    // MARK: - Warning Helpers

    private func familyRepeatWarning(
        index: Int,
        title: String,
        chosen: PresetDescriptor
    ) -> PlanningWarning {
        PlanningWarning(
            kind: .forcedFamilyRepeat,
            trackIndex: index,
            message: "\(title): '\(chosen.name)' shares family '\(chosen.family)' with previous."
        )
    }
}

// MARK: - Sendable conformance check (compile-time)

private func _assertSendable(_: some Sendable) {}
private func _checkDefaultSessionPlannerSendable() { _assertSendable(DefaultSessionPlanner()) }
