// PresetScoringContextExtensionTests — Tests for excludedFamilies and qualityCeiling fields (U.8 Part C).

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

// MARK: - PresetScoringContextExtensionTests

@Suite("PresetScoringContextExtension")
struct PresetScoringContextExtensionTests {

    private let scorer = DefaultPresetScorer()

    // MARK: - excludedFamilies

    @Test func excludedFamilies_default_isEmpty() {
        let ctx = makeContext()
        #expect(ctx.excludedFamilies.isEmpty)
    }

    @Test func excludedFamilies_blockedPreset_isExcluded() {
        let ctx = makeContext(excludedFamilies: [.geometric])
        let preset = makePreset(family: .geometric)
        let breakdown = scorer.breakdown(preset: preset, track: makeTrack(), context: ctx)
        #expect(breakdown.excluded)
        #expect(breakdown.exclusionReason?.contains("blocklist") == true)
    }

    @Test func excludedFamilies_nonBlockedPreset_isNotExcluded() {
        let ctx = makeContext(excludedFamilies: [.geometric])
        let preset = makePreset(family: .fluid)
        let breakdown = scorer.breakdown(preset: preset, track: makeTrack(), context: ctx)
        #expect(!breakdown.excluded)
    }

    @Test func excludedFamilies_emptySet_noExclusions() {
        let ctx = makeContext(excludedFamilies: [])
        let preset = makePreset(family: .geometric)
        let breakdown = scorer.breakdown(preset: preset, track: makeTrack(), context: ctx)
        #expect(!breakdown.excluded)
    }

    // MARK: - qualityCeiling

    @Test func qualityCeiling_default_isAuto() {
        let ctx = makeContext()
        #expect(ctx.qualityCeiling == .auto)
    }

    @Test func qualityCeiling_performance_excludesHighComplexityPreset() {
        // Performance ceiling is 12 ms. A preset at 15 ms cost must be excluded.
        let ctx = makeContext(qualityCeiling: .performance)
        let preset = makePreset(complexityCostMs: 15)
        let breakdown = scorer.breakdown(preset: preset, track: makeTrack(), context: ctx)
        #expect(breakdown.excluded)
        #expect(breakdown.exclusionReason?.contains("quality-ceiling budget") == true)
    }

    @Test func qualityCeiling_ultra_allowsHighComplexity() {
        // Ultra lifts the complexity gate entirely.
        let ctx = makeContext(qualityCeiling: .ultra)
        let preset = makePreset(complexityCostMs: 999)
        let breakdown = scorer.breakdown(preset: preset, track: makeTrack(), context: ctx)
        #expect(!breakdown.excluded)
    }

    @Test func qualityCeiling_auto_usesFrameBudget() {
        // Auto uses tier frameBudgetMs (~16.6 ms for tier1). A 10 ms preset must pass.
        let ctx = makeContext(qualityCeiling: .auto)
        let preset = makePreset(complexityCostMs: 10)
        let breakdown = scorer.breakdown(preset: preset, track: makeTrack(), context: ctx)
        #expect(!breakdown.excluded)
    }

    // MARK: - Backward compatibility

    @Test func init_withoutNewFields_hasDefaults() {
        // Existing callers that don't pass the new params compile and behave as before.
        let ctx = PresetScoringContext(
            deviceTier: .tier2,
            recentHistory: [],
            currentPreset: nil,
            elapsedSessionTime: 0,
            currentSection: nil
        )
        #expect(ctx.excludedFamilies.isEmpty)
        #expect(ctx.qualityCeiling == .auto)
    }

    // MARK: - Helpers

    private func makePreset(
        family: PresetCategory = .fluid,
        complexityCostMs: Float = 1.0
    ) -> PresetDescriptor {
        let json = """
        {
            "name": "TestPreset",
            "family": "\(family.rawValue)",
            "complexity_cost": {"tier1": \(complexityCostMs), "tier2": \(complexityCostMs)}
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    private func makeTrack() -> TrackProfile {
        TrackProfile(
            bpm: 120,
            mood: EmotionalState(valence: 0, arousal: 0),
            stemEnergyBalance: StemFeatures.zero
        )
    }

    private func makeContext(
        deviceTier: DeviceTier = .tier1,
        excludedFamilies: Set<PresetCategory> = [],
        qualityCeiling: QualityCeiling = .auto
    ) -> PresetScoringContext {
        PresetScoringContext(
            deviceTier: deviceTier,
            excludedFamilies: excludedFamilies,
            qualityCeiling: qualityCeiling
        )
    }
}
