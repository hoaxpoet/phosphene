// PresetScorer — Explicit, observable preset scoring for the Orchestrator.
// Per D-014: no black boxes. Sub-scores are individually inspectable.
// Deterministic: same (preset, track, context) → same score, byte-exact.

import Foundation
import Shared
import Presets
import Session

// MARK: - PresetScoreBreakdown

/// The full sub-score breakdown for one (preset, track, context) evaluation.
///
/// Each field is in [0, 1] except where noted. A total of 0 always accompanies
/// `excluded = true`; inspect `exclusionReason` to understand why.
public struct PresetScoreBreakdown: Sendable, Hashable {
    /// Mood compatibility: tracks target color temperature and density against preset range. 0–1.
    public let mood: Float
    /// Tempo / motion match: BPM-derived target motion vs preset motion_intensity. 0–1.
    public let tempoMotion: Float
    /// Stem affinity match: how well the dominant stems in the track align with the preset's responsive stems. 0–1.
    public let stemAffinity: Float
    /// Section suitability: 1.0 if preset suits the current section, 0.3 if not, 1.0 if section unknown. 0–1.
    public let sectionSuitability: Float
    /// Multiplicative penalty for consecutive same-family selection. 1.0 = no penalty; 0.2 = strong penalty.
    public let familyRepeatMultiplier: Float
    /// Multiplicative cooldown penalty for recent reuse of this preset's family. 1.0 = fully cooled; 0 = just used.
    public let fatigueMultiplier: Float
    /// True when this preset is categorically excluded from consideration (perf budget or identity).
    public let excluded: Bool
    /// Human-readable reason for exclusion, nil when `excluded` is false.
    public let exclusionReason: String?
    /// Additive family boost applied after weighted aggregation (U.6b). 0 when none.
    public let familyBoost: Float
    /// Concise reason this preset was filtered, nil when `excluded` is false.
    /// Distinct from `exclusionReason` — this field surfaces the specific gate name
    /// (e.g. "uncertified", "budget", "active") for logging and test assertions.
    public let excludedReason: String?
    /// Final combined score in [0, 1]. Always 0 when `excluded` is true.
    public let total: Float
}

// MARK: - PresetScoring

/// Protocol for preset scoring implementations.
///
/// Conforming types must be `Sendable` and deterministic: the same
/// `(preset, track, context)` tuple must always produce the same score.
public protocol PresetScoring: Sendable {
    /// Returns the final combined score for the preset (0–1, or 0 if excluded).
    func score(
        preset: PresetDescriptor,
        track: TrackProfile,
        context: PresetScoringContext
    ) -> Float

    /// Returns the full breakdown for inspection and debugging.
    func breakdown(
        preset: PresetDescriptor,
        track: TrackProfile,
        context: PresetScoringContext
    ) -> PresetScoreBreakdown
}

// MARK: PresetScoring default extensions

public extension PresetScoring {
    /// Ranks a catalog of presets from highest to lowest score, excluding zeroed presets.
    ///
    /// Ties are broken by the preset's position in the input array (stable sort).
    func rank(
        presets: [PresetDescriptor],
        track: TrackProfile,
        context: PresetScoringContext
    ) -> [(PresetDescriptor, Float)] {
        presets
            .map { ($0, score(preset: $0, track: track, context: context)) }
            .sorted { $0.1 > $1.1 }
    }
}

// MARK: - DefaultPresetScorer

/// Concrete implementation of `PresetScoring` using the weighted sub-score model.
///
/// ## Weight rationale (D-030)
/// - **mood (0.30)**: highest weight — the primary axis of Orchestrator fit.
/// - **stemAffinity (0.25)**: second highest — stems are the most reliable audio signal.
/// - **sectionSuitability (0.25)**: equal to stems — structural fit matters as much.
/// - **tempoMotion (0.20)**: slightly lower — motion maps to BPM but BPM is often missing.
///
/// Weights sum to 1.0 so `raw` is already in [0, 1] and interpretable at a glance.
/// Multiplicative penalties compose cleanly and are separate from exclusions so
/// "why is this score zero" is always answerable from the breakdown.
public struct DefaultPresetScorer: PresetScoring {

    // MARK: Weight constants

    internal static let weightMood: Float              = 0.30
    internal static let weightTempoMotion: Float       = 0.20
    internal static let weightStemAffinity: Float      = 0.25
    internal static let weightSectionSuitability: Float = 0.25

    /// Multiplicative penalty when the candidate shares the same family as the current preset.
    internal static let familyRepeatPenalty: Float = 0.2

    /// Fatigue cooldown windows in seconds, indexed by `FatigueRisk`.
    internal static let fatigueCooldown: [FatigueRisk: Float] = [
        .low: 60,
        .medium: 120,
        .high: 300,
    ]

    /// Section suitability score when the preset does not list the active section.
    internal static let sectionMismatchScore: Float = 0.3

    public init() {}

    // MARK: - PresetScoring

    public func score(
        preset: PresetDescriptor,
        track: TrackProfile,
        context: PresetScoringContext
    ) -> Float {
        breakdown(preset: preset, track: track, context: context).total
    }

    public func breakdown(
        preset: PresetDescriptor,
        track: TrackProfile,
        context: PresetScoringContext
    ) -> PresetScoreBreakdown {
        // -- Hard exclusions -------------------------------------------------
        if let (reason, tag) = exclusionReasonAndTag(preset: preset, context: context) {
            return PresetScoreBreakdown(
                mood: 0,
                tempoMotion: 0,
                stemAffinity: 0,
                sectionSuitability: 0,
                familyRepeatMultiplier: 0,
                fatigueMultiplier: 0,
                excluded: true,
                exclusionReason: reason,
                familyBoost: 0,
                excludedReason: tag,
                total: 0
            )
        }

        // -- Sub-scores -------------------------------------------------------
        let moodScore       = moodSubScore(preset: preset, track: track)
        let tempoScore      = tempoMotionSubScore(preset: preset, track: track)
        let affinityScore   = stemAffinitySubScore(preset: preset, track: track)
        let sectionScore    = sectionSuitabilitySubScore(preset: preset, context: context)

        // -- Multiplicative penalties -----------------------------------------
        let familyMult  = familyRepeatMultiplier(preset: preset, context: context)
        let fatigueMult = fatigueMultiplier(preset: preset, context: context)

        // -- Aggregation ------------------------------------------------------
        let raw = Self.weightMood * moodScore
            + Self.weightTempoMotion * tempoScore
            + Self.weightStemAffinity * affinityScore
            + Self.weightSectionSuitability * sectionScore

        // -- U.6b additive family boost (independent of the four-weight structure) --
        // Diagnostic presets (family == nil) receive no family boost.
        let boost = preset.family.flatMap { context.familyBoosts[$0] } ?? 0

        let total = min(1, max(0, raw * familyMult * fatigueMult + boost))

        return PresetScoreBreakdown(
            mood: moodScore,
            tempoMotion: tempoScore,
            stemAffinity: affinityScore,
            sectionSuitability: sectionScore,
            familyRepeatMultiplier: familyMult,
            fatigueMultiplier: fatigueMult,
            excluded: false,
            exclusionReason: nil,
            familyBoost: boost,
            excludedReason: nil,
            total: total
        )
    }

    // MARK: - Hard Exclusion

    /// Returns `(humanReadableReason, shortTag)` when the preset should be excluded,
    /// or `nil` when the preset is eligible for scoring.
    private func exclusionReasonAndTag(
        preset: PresetDescriptor,
        context: PresetScoringContext
    ) -> (String, String)? {
        // V.7.6.D: diagnostic gate — categorical exclusion, no settings toggle.
        // Diagnostic presets are operational tools (e.g. Spectral Cartograph), never
        // aesthetic content. They render only via manual switch. Per D-074.
        if preset.isDiagnostic {
            return (
                "preset '\(preset.id)' is a diagnostic — manual-switch only",
                "diagnostic"
            )
        }
        // V.6: certification gate — checked after diagnostic so uncertified presets never enter scoring.
        if !context.includeUncertifiedPresets && !preset.certified {
            return (
                "preset '\(preset.id)' is uncertified (certified: false in JSON sidecar)",
                "uncertified"
            )
        }
        if context.sessionExcludedPresets.contains(preset.id) {
            return ("preset '\(preset.id)' excluded by user this session", "session_excluded")
        }
        // Diagnostic presets (family == nil) bypass user family-blocklist gates;
        // they are already gated by the diagnostic check above.
        if let family = preset.family, context.temporarilyExcludedFamilies.contains(family) {
            return (
                "preset '\(preset.id)' family '\(family)' temporarily excluded by user",
                "family_temp_excluded"
            )
        }
        if let family = preset.family, context.excludedFamilies.contains(family) {
            return (
                "preset '\(preset.id)' family '\(family)' is in user blocklist",
                "family_blocklisted"
            )
        }
        if let budget = context.qualityCeiling.complexityThresholdMs(for: context.deviceTier) {
            if preset.complexityCost.cost(for: context.deviceTier) > budget {
                return (
                    "complexity cost \(preset.complexityCost.cost(for: context.deviceTier)) ms " +
                    "exceeds quality-ceiling budget \(budget) ms on \(context.deviceTier)",
                    "budget_exceeded"
                )
            }
        }
        if preset.id == context.currentPreset?.id {
            return ("preset '\(preset.id)' is already active", "active")
        }
        return nil
    }

    // MARK: - Sub-Scores

    /// Mood compatibility: maps track valence/arousal to target preset temperature and density.
    private func moodSubScore(preset: PresetDescriptor, track: TrackProfile) -> Float {
        let valence = track.mood.valence  // -1..+1
        let arousal = track.mood.arousal  // -1..+1

        // Map valence → warm colour target: warm when happy, cool when sad.
        let targetTemp    = max(0, min(1, 0.5 + 0.4 * valence))
        // Map arousal → visual density target: busier when energised.
        let targetDensity = max(0, min(1, 0.5 + 0.4 * arousal))

        let presetTempCenter = (preset.colorTemperatureRange.x + preset.colorTemperatureRange.y) / 2
        let tempScore    = 1 - abs(presetTempCenter - targetTemp)
        let densityScore = 1 - abs(preset.visualDensity - targetDensity)

        return (tempScore + densityScore) / 2
    }

    /// Tempo / motion match: piecewise linear BPM → target motion intensity.
    ///
    /// Anchors: 0→0.2, 70→0.2, 110→0.5, 140→0.7, 200→0.9. Fully smooth at every breakpoint.
    /// Unknown BPM (nil) maps to neutral 0.5 so the scorer doesn't penalise missing metadata.
    private func tempoMotionSubScore(preset: PresetDescriptor, track: TrackProfile) -> Float {
        let target = bpmToTargetMotion(track.bpm)
        return 1 - abs(preset.motionIntensity - target)
    }

    private func bpmToTargetMotion(_ bpm: Float?) -> Float {
        guard let bpm = bpm else { return 0.5 }
        if bpm < 70 { return 0.2 }
        if bpm < 110 { return 0.2 + 0.3 * (bpm - 70) / 40 }
        if bpm < 140 { return 0.5 + 0.2 * (bpm - 110) / 30 }
        // Above 140 BPM: linearly converge to 0.9 at 200 BPM, then clamp.
        return min(0.9, 0.7 + 0.2 * (bpm - 140) / 60)
    }

    /// Stem affinity: mean above-average deviation for stems the preset responds to.
    ///
    /// Empty `stem_affinity` dicts score 0.5 (neutral — no information).
    /// Zero `stemEnergyBalance` (pre-convergence reactive mode) returns 0.5 for all presets.
    /// Uses `stemEnergyDev` fields (D-026/QR.2, D-080) so AGC normalization cannot saturate
    /// the sub-score when multiple affinities are declared.
    private func stemAffinitySubScore(preset: PresetDescriptor, track: TrackProfile) -> Float {
        let affinities = Set(preset.stemAffinity.keys)
        guard !affinities.isEmpty else { return 0.5 }
        guard track.stemEnergyBalance != .zero else { return 0.5 }
        let devSum = affinities.reduce(Float(0)) { acc, stem in
            acc + max(0, stemEnergyDeviation(stem, in: track.stemEnergyBalance))
        }
        return min(1, max(0, devSum / Float(affinities.count)))
    }

    /// Returns the above-average energy deviation for a named stem (D-026).
    private func stemEnergyDeviation(_ stem: String, in features: StemFeatures) -> Float {
        switch stem {
        case "vocals": return features.vocalsEnergyDev
        case "drums":  return features.drumsEnergyDev
        case "bass":   return features.bassEnergyDev
        case "other":  return features.otherEnergyDev
        default:       return 0
        }
    }

    /// Section suitability: full credit if preset lists the section or section is unknown;
    /// `sectionMismatchScore` (0.3) otherwise.
    private func sectionSuitabilitySubScore(
        preset: PresetDescriptor,
        context: PresetScoringContext
    ) -> Float {
        guard let section = context.currentSection else { return 1.0 }
        return preset.sectionSuitability.contains(section) ? 1.0 : Self.sectionMismatchScore
    }

    // MARK: - Multiplicative Penalties

    /// Strong penalty (0.2×) for consecutive same-family selection; 1.0 otherwise.
    /// Presets without a family (diagnostics) never trigger the penalty.
    private func familyRepeatMultiplier(preset: PresetDescriptor, context: PresetScoringContext) -> Float {
        guard let family = preset.family,
              let currentFamily = context.currentPreset?.family,
              family == currentFamily
        else { return 1.0 }
        return Self.familyRepeatPenalty
    }

    /// Smoothstep cooldown based on how recently this preset's family was last used.
    /// Presets without a family (diagnostics) are never cooled down by history.
    private func fatigueMultiplier(preset: PresetDescriptor, context: PresetScoringContext) -> Float {
        let cooldown = Self.fatigueCooldown[preset.fatigueRisk] ?? 120
        guard let family = preset.family else { return 1.0 }
        // Find the most recent history entry from the same family.
        guard let entry = context.recentHistory.last(where: { $0.family == family }) else {
            return 1.0
        }
        let gap = Float(context.elapsedSessionTime - entry.endTime)
        return smoothstep(0, cooldown, gap)
    }

    // MARK: - Math Utilities

    /// Standard smoothstep: 0 when x ≤ edge0, 1 when x ≥ edge1, smooth cubic in between.
    private func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let tt = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return tt * tt * (3 - 2 * tt)
    }
}

// MARK: - Sendable conformance check (compile-time)

private func _assertSendable(_: some Sendable) {}
private func _checkDefaultPresetScorerSendable() { _assertSendable(DefaultPresetScorer()) }
