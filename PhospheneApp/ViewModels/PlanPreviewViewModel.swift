// PlanPreviewViewModel — Observable state for PlanPreviewView (Increment U.5 Parts B & D).
//
// Part B: Display-only. Builds PlanPreviewRow values from PlannedSession and
// updates them when the plan publisher fires (e.g., after regeneration).
//
// Part D: Adds regeneratePlan() which re-runs the planner with a random seed,
// preserving manually locked track picks. manuallyLockedTracks persists through
// regeneration cycles; it is in-memory only (not persisted across sessions).
//
// Part C: Row-tap preview loop deferred to U.5b — see PresetPreviewController.swift.
// TODO(U.5.C): Wire PresetPreviewController into previewRow(_:) when U.5b lands.

import Combine
import Foundation
import Orchestrator
import Presets
import Session
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "PlanPreview")

// MARK: - PlanPreviewRow

/// View data for one track in the plan preview list.
struct PlanPreviewRow: Identifiable {
    let id: TrackIdentity
    let trackIndex: Int
    let trackTitle: String
    let trackArtist: String
    let presetName: String
    let presetFamily: String
    let duration: TimeInterval
    let incomingTransition: TransitionSummary?
    let isLocked: Bool
    let presetDescriptor: PresetDescriptor
}

// MARK: - TransitionSummary

/// Collapsed view of a `PlannedTransition` for display in `PlanPreviewTransitionView`.
struct TransitionSummary: Equatable {
    let style: String
    let duration: TimeInterval?
    let isStructural: Bool
}

// MARK: - PlanPreviewViewModel

/// ViewModel for `PlanPreviewView`.
///
/// Subscribes to the plan publisher and derives `rows` whenever the plan changes.
/// `manuallyLockedTracks` persists through Regenerate — those tracks keep the
/// user-chosen preset and are not subject to planner re-randomization.
@MainActor
final class PlanPreviewViewModel: ObservableObject {

    // MARK: - Published State

    /// Rows in playlist order, one per planned track.
    @Published private(set) var rows: [PlanPreviewRow] = []

    /// Tracks the user has manually locked to a specific preset.
    @Published private(set) var manuallyLockedTracks: Set<TrackIdentity> = []

    /// [TrackIdentity: PresetDescriptor] for locked tracks — used by regeneratePlan.
    private(set) var lockedPresets: [TrackIdentity: PresetDescriptor] = [:]

    /// True while a regeneration is in flight (shows spinner on button).
    @Published private(set) var isRegenerating: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    /// Called to re-plan with a seed. Passes locked track set + preset map.
    private let onRegenerate: @MainActor (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void

    // MARK: - Init

    /// - Parameters:
    ///   - initialPlan: Optional starting plan (nil = reactive mode / no plan).
    ///   - planPublisher: Emits updated plans as they arrive (regeneration, engine rebuild).
    ///   - onRegenerate: Closure to re-run the planner. Receives locked-track info;
    ///     updates `engine.livePlannedSession` internally so the publisher fires.
    init(
        initialPlan: PlannedSession?,
        planPublisher: AnyPublisher<PlannedSession?, Never>,
        onRegenerate: @escaping @MainActor (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void
    ) {
        self.onRegenerate = onRegenerate

        if let plan = initialPlan {
            rows = buildRows(from: plan, locked: [])
        }

        planPublisher
            .compactMap { $0 }
            .sink { [weak self] plan in
                guard let self else { return }
                rows = buildRows(from: plan, locked: manuallyLockedTracks)
                isRegenerating = false
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    /// Swap the preset for a track and lock it against regeneration.
    func swapPreset(for track: TrackIdentity, to preset: PresetDescriptor) {
        manuallyLockedTracks.insert(track)
        lockedPresets[track] = preset

        rows = rows.map { row in
            guard row.id == track else { return row }
            return PlanPreviewRow(
                id: row.id,
                trackIndex: row.trackIndex,
                trackTitle: row.trackTitle,
                trackArtist: row.trackArtist,
                presetName: preset.name,
                presetFamily: preset.family?.rawValue ?? "diagnostic",
                duration: row.duration,
                incomingTransition: row.incomingTransition,
                isLocked: true,
                presetDescriptor: preset
            )
        }
        logger.info("PlanPreview: locked '\(track.title)' → '\(preset.name)'")
    }

    /// Remove the manual lock for a track; restores the planner's original pick
    /// (the row reverts on the next regeneration pass).
    func resetLock(for track: TrackIdentity) {
        manuallyLockedTracks.remove(track)
        lockedPresets.removeValue(forKey: track)
        rows = rows.map { row in
            guard row.id == track else { return row }
            return PlanPreviewRow(
                id: row.id,
                trackIndex: row.trackIndex,
                trackTitle: row.trackTitle,
                trackArtist: row.trackArtist,
                presetName: row.presetName,
                presetFamily: row.presetFamily,
                duration: row.duration,
                incomingTransition: row.incomingTransition,
                isLocked: false,
                presetDescriptor: row.presetDescriptor
            )
        }
    }

    /// Re-run the planner with a fresh random seed, preserving locked picks.
    ///
    /// `isRegenerating` flips true immediately (drives a spinner on the button).
    /// Flips back to false when the plan publisher delivers the new plan.
    func regeneratePlan() {
        guard !isRegenerating else { return }
        isRegenerating = true
        onRegenerate(manuallyLockedTracks, lockedPresets)
    }

    /// Preview the preset for a row (stub — see PresetPreviewController.swift).
    ///
    /// TODO(U.5.C): Replace stub with PresetPreviewController.startPreview(...).
    func previewRow(_ row: PlanPreviewRow) {
        logger.info("PlanPreview: row-tap preview not yet implemented (U.5b)")
    }

    // MARK: - Private

    private func buildRows(from plan: PlannedSession, locked: Set<TrackIdentity>) -> [PlanPreviewRow] {
        plan.tracks.enumerated().map { index, track in
            let transition = track.incomingTransition.map { tx in
                TransitionSummary(
                    style: tx.style.rawValue,
                    duration: tx.style == .cut ? nil : tx.duration,
                    isStructural: tx.reason.hasPrefix("Structural boundary")
                )
            }
            return PlanPreviewRow(
                id: track.track,
                trackIndex: index,
                trackTitle: track.track.title,
                trackArtist: track.track.artist,
                presetName: lockedPresets[track.track]?.name ?? track.preset.name,
                presetFamily: lockedPresets[track.track]?.family?.rawValue
                    ?? track.preset.family?.rawValue
                    ?? "diagnostic",
                duration: track.plannedEndTime - track.plannedStartTime,
                incomingTransition: transition,
                isLocked: locked.contains(track.track),
                presetDescriptor: lockedPresets[track.track] ?? track.preset
            )
        }
    }
}
