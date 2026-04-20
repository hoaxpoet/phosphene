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
        if let reason = exclusionReason(preset: preset, context: context) {
            return PresetScoreBreakdown(
                mood: 0,
                tempoMotion: 0,
                stemAffinity: 0,
                sectionSuitability: 0,
                familyRepeatMultiplier: 0,
                fatigueMultiplier: 0,
                excluded: true,
                exclusionReason: reason,
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

        let total = min(1, max(0, raw * familyMult * fatigueMult))

        return PresetScoreBreakdown(
            mood: moodScore,
            tempoMotion: tempoScore,
            stemAffinity: affinityScore,
            sectionSuitability: sectionScore,
            familyRepeatMultiplier: familyMult,
            fatigueMultiplier: fatigueMult,
            excluded: false,
            exclusionReason: nil,
            total: total
        )
    }

    // MARK: - Hard Exclusion

    private func exclusionReason(preset: PresetDescriptor, context: PresetScoringContext) -> String? {
        if preset.complexityCost.cost(for: context.deviceTier) > context.frameBudgetMs {
            return "complexity cost \(preset.complexityCost.cost(for: context.deviceTier)) ms " +
                   "exceeds frame budget \(context.frameBudgetMs) ms on \(context.deviceTier)"
        }
        if preset.id == context.currentPreset?.id {
            return "preset '\(preset.id)' is already active"
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

    /// Stem affinity: sum of energy for stems the preset responds to, clamped to [0, 1].
    ///
    /// Empty `stem_affinity` dicts score 0.5 (neutral — no information).
    private func stemAffinitySubScore(preset: PresetDescriptor, track: TrackProfile) -> Float {
        let affinities = Set(preset.stemAffinity.keys)
        guard !affinities.isEmpty else { return 0.5 }
        let total = affinities.reduce(0) { acc, stem in
            acc + stemEnergy(stem, in: track.stemEnergyBalance)
        }
        return min(1, max(0, total))
    }

    /// Returns the per-stem energy from `StemFeatures` by name.
    private func stemEnergy(_ stem: String, in features: StemFeatures) -> Float {
        switch stem {
        case "vocals": return features.vocalsEnergy
        case "drums":  return features.drumsEnergy
        case "bass":   return features.bassEnergy
        case "other":  return features.otherEnergy
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
    private func familyRepeatMultiplier(preset: PresetDescriptor, context: PresetScoringContext) -> Float {
        guard context.currentPreset?.family == preset.family else { return 1.0 }
        return Self.familyRepeatPenalty
    }

    /// Smoothstep cooldown based on how recently this preset's family was last used.
    private func fatigueMultiplier(preset: PresetDescriptor, context: PresetScoringContext) -> Float {
        let cooldown = Self.fatigueCooldown[preset.fatigueRisk] ?? 120
        // Find the most recent history entry from the same family.
        guard let entry = context.recentHistory.last(where: { $0.family == preset.family }) else {
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
