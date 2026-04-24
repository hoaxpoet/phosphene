// PresetScoringContextProvider — Builds PresetScoringContext from settings + engine state.
// Full implementation in U.8 Part C.

import Orchestrator
import Presets
import Shared
import Foundation

// MARK: - PresetScoringContextProvider

/// Consolidates SettingsStore + detected device tier + live session state into
/// a PresetScoringContext. Replaces inline PresetScoringContext constructions
/// in VisualizerEngine+Orchestrator.swift.
@MainActor
final class PresetScoringContextProvider {

    private let settingsStore: SettingsStore
    private let detectedTier: DeviceTier

    init(settingsStore: SettingsStore, detectedTier: DeviceTier) {
        self.settingsStore = settingsStore
        self.detectedTier = detectedTier
    }

    /// Effective device tier: override if set, otherwise hardware detection result.
    var effectiveTier: DeviceTier {
        switch settingsStore.deviceTierOverride {
        case .auto:        return detectedTier
        case .forceTier1:  return .tier1
        case .forceTier2:  return .tier2
        }
    }

    /// Builds a complete PresetScoringContext for the given session state.
    ///
    /// `excludedFamilies` and `qualityCeiling` fields are wired in Part C
    /// when `PresetScoringContext` is extended with those fields.
    func build(
        elapsedSessionTime: TimeInterval = 0,
        recentHistory: [PresetHistoryEntry] = [],
        currentPreset: PresetDescriptor? = nil,
        currentSection: SongSection? = nil
    ) -> PresetScoringContext {
        // TODO(PartC): pass excludedFamilies: settingsStore.excludedPresetCategories,
        //              qualityCeiling: settingsStore.qualityCeiling
        //              once PresetScoringContext is extended.
        PresetScoringContext(
            deviceTier: effectiveTier,
            recentHistory: recentHistory,
            currentPreset: currentPreset,
            elapsedSessionTime: elapsedSessionTime,
            currentSection: currentSection
        )
    }
}
